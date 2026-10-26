#!/system/bin/sh

# LightFlow uses reversible settings and a backed-up agy launch hook.
# Thermal limits, CPU governors, ZRAM size and SELinux remain stock.

MODDIR=${0%/*}
case "$(getprop ro.product.model):$(getprop ro.build.version.sdk)" in
  RMX3741:35) ;;
  *) exit 0 ;;
esac
LOG=/data/adb/lightflow.log
MARKER=/data/adb/lightflow
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
NOTIFICATION_PACKAGES="$MODDIR/notification-packages.conf"
DISABLED_PACKAGES="$MODDIR/disabled-background-packages.conf"
DISABLED_STATE_DIR="$MARKER/disabled-packages"
MEMORY_STATE_DIR="$MARKER/memory"
POWER_STATE_DIR="$MARKER/power"
FACEBOOK_BACKGROUND_RESET="$MARKER/facebook-background-exemption-reset-v1.9.4"

mkdir -p "$MARKER"
mkdir -p "$DISABLED_STATE_DIR"
mkdir -p "$MEMORY_STATE_DIR"
mkdir -p "$POWER_STATE_DIR"

# Wait for boot readiness, with a bound so this never becomes a resident loop.
attempt=0
while [ "$(getprop sys.boot_completed)" != 1 ]; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 120 ]; then
    printf '%s LightFlow skipped: boot did not complete\n' "$(date '+%F %T')" >> "$LOG"
    exit 1
  fi
  sleep 2
done

# An installed helper can launch after unlock even if refreshing its app-owned
# marker failed during boot. This property is volatile and read once per launch.
if [ -n "$BOOT_ID" ] && setprop sys.lightflow.codex.boot "$BOOT_ID" && \
   [ "$(getprop sys.lightflow.codex.boot)" = "$BOOT_ID" ]; then
  printf '%s Codex launch gate published for this boot\n' "$(date '+%F %T')" >> "$LOG"
else
  printf '%s Codex launch gate publication not verified; helper will check independently\n' "$(date '+%F %T')" >> "$LOG"
fi

# Install once per boot; subsequent agent launches inherit their own policy.
sh "$MODDIR/agy-launcher.sh" >> "$LOG" 2>&1
if ! sh "$MODDIR/codex-launcher.sh" >> "$LOG" 2>&1; then
  printf '%s Codex launcher refresh failed; existing launcher preserved\n' "$(date '+%F %T')" >> "$LOG"
fi
sh "$MODDIR/auto-optimize.sh" >> "$LOG" 2>&1
sh "$MODDIR/io-policy.sh" boot >> "$LOG" 2>&1
sh "$MODDIR/weather-policy.sh" apply >> "$LOG" 2>&1
sh "$MODDIR/sleep-log-policy.sh" apply >> "$LOG" 2>&1
sh "$MODDIR/oem-diagnostics-policy.sh" apply >> "$LOG" 2>&1
sh "$MODDIR/hosts-policy.sh" apply >> "$LOG" 2>&1

# These are preferences; app requests and vendor policy decide the actual rate.
settings put system min_refresh_rate 60 >/dev/null 2>&1
settings put system peak_refresh_rate 120 >/dev/null 2>&1
settings put system user_refresh_rate 90 >/dev/null 2>&1
settings delete system customized_refresh_rate >/dev/null 2>&1

# Snappier transitions without a permanent rendering or CPU boost.
settings put global window_animation_scale 0.5 >/dev/null 2>&1
settings put global transition_animation_scale 0.5 >/dev/null 2>&1
settings put global animator_duration_scale 0.5 >/dev/null 2>&1

# Restore only the swappiness value managed by older LightFlow releases.
sh "$MODDIR/thermal-memory-policy.sh" restore >> "$LOG" 2>&1

# Wi-Fi sleep policy is unused by the platform from Android 11/API 30.
# Keep legacy behavior only on older firmware; modern Android controls radio
# power saving, roaming and validation without an obsolete settings write.
sdk=$(getprop ro.build.version.sdk)
case "$sdk" in
  ''|*[!0-9]*) ;;
  *) [ "$sdk" -ge 30 ] || settings put global wifi_sleep_policy 2 >/dev/null 2>&1 ;;
esac

# Back up and verify Wi-Fi/BLE discovery switches independently. A failed
# settings read or backup must not be followed by an unowned settings write.
sh "$MODDIR/radio-scan-policy.sh" apply >> "$LOG" 2>&1

# RMX3741 has 8 GB RAM with LZ4 ZRAM. Keep the kernel's modern, low-overhead
# reclaim path available without changing the vendor LMKD thresholds, ZRAM
# size, or swappiness. Those vendor values already favor app retention; making
# them more aggressive would trade multitasking for compression CPU and heat.
memory_total_kb=$(awk '/MemTotal:/ { print $2 }' /proc/meminfo)
if [ "$memory_total_kb" -ge 6000000 ] && [ "$memory_total_kb" -le 12000000 ]; then
  if [ -w /sys/kernel/mm/lru_gen/enabled ]; then
    mglru_state_file="$MEMORY_STATE_DIR/mglru_enabled"
    if [ ! -f "$mglru_state_file" ]; then
      cat /sys/kernel/mm/lru_gen/enabled > "$mglru_state_file"
    fi
    printf '%s\n' 0x3 > /sys/kernel/mm/lru_gen/enabled
  fi

  if [ -w /proc/sys/vm/page-cluster ]; then
    page_cluster_state_file="$MEMORY_STATE_DIR/page_cluster"
    if [ ! -f "$page_cluster_state_file" ]; then
      cat /proc/sys/vm/page-cluster > "$page_cluster_state_file"
    fi
    printf '%s\n' 0 > /proc/sys/vm/page-cluster
  fi
fi

# Use Android's own cached-process freezer and adaptive power policy. These
# controls act on every app without a resident monitor. Save each prior value
# so uninstall returns the device to the user's state.
sh "$MODDIR/power-policy.sh" >> "$LOG" 2>&1

# Use the existing Zygisk/Vector runtime; no resident memory polling.
if ! sh "$MODDIR/guard-policy.sh" start >> "$LOG" 2>&1; then
  printf '%s LightFlow system guard NOT enabled; stock memory policy retained\n' "$(date '+%F %T')" >> "$LOG"
fi

# These apps may use normal background execution so FCM/app notifications are not
# intentionally blocked. Do not add them to the Doze whitelist: that costs battery.
# Facebook was exempted by LightFlow 1.9.3. Reset that old exemption once so a
# cached Facebook process can be frozen; Messenger remains in the notification
# list above. Do not repeat this write after the migration marker is present.
if [ ! -f "$FACEBOOK_BACKGROUND_RESET" ] && pm path com.facebook.katana >/dev/null 2>&1; then
  if cmd appops set com.facebook.katana RUN_ANY_IN_BACKGROUND default >/dev/null 2>&1 && \
     cmd appops set com.facebook.katana RUN_IN_BACKGROUND default >/dev/null 2>&1; then
    printf '%s\n' reset > "$FACEBOOK_BACKGROUND_RESET"
    printf '%s Facebook background exemption reset for v1.9.4\n' "$(date '+%F %T')" >> "$LOG"
  fi
fi
while IFS= read -r pkg; do
  case "$pkg" in
    ''|\#*) continue ;;
  esac
  pm path "$pkg" >/dev/null 2>&1 || continue
  cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
  cmd appops set "$pkg" RUN_IN_BACKGROUND allow >/dev/null 2>&1
done < "$NOTIFICATION_PACKAGES"

# Disable only the optional packages in the reviewed list. Save the initial
# state once so uninstall restores only packages this module disabled itself.
while IFS= read -r pkg; do
  case "$pkg" in
    ''|\#*) continue ;;
  esac
  pm path "$pkg" >/dev/null 2>&1 || continue
  state_file="$DISABLED_STATE_DIR/$pkg"
  if [ ! -f "$state_file" ]; then
    if pm list packages --user 0 -d "$pkg" | grep -qx "package:$pkg"; then
      printf '%s\n' disabled > "$state_file"
    else
      printf '%s\n' enabled > "$state_file"
    fi
  fi
  pm disable-user --user 0 "$pkg" >/dev/null 2>&1
  am force-stop --user 0 "$pkg" >/dev/null 2>&1
done < "$DISABLED_PACKAGES"

if [ -n "$BOOT_ID" ]; then
  printf '%s\n' "$BOOT_ID" > "$MARKER/last_boot_id"
fi
printf '%s LightFlow active (boot %s): refresh preferences, kernel reclaim, cached-app freezer, adaptive power, notification-safe appops, optional package/diagnostic policy applied\n' "$(date '+%F %T')" "$BOOT_ID" >> "$LOG"
