#!/system/bin/sh

# LightFlow uses reversible settings and a backed-up agy launch hook.
# It does not change thermal limits, CPU governors, ZRAM, SELinux, or vendor props.

MODDIR=${0%/*}
LOG=/data/adb/lightflow.log
MARKER=/data/adb/lightflow
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
NOTIFICATION_PACKAGES="$MODDIR/notification-packages.conf"
DISABLED_PACKAGES="$MODDIR/disabled-background-packages.conf"
WIFI_SCAN_STATE="$MARKER/wifi_scan_always_enabled"
DISABLED_STATE_DIR="$MARKER/disabled-packages"
MEMORY_STATE_DIR="$MARKER/memory"
POWER_STATE_DIR="$MARKER/power"

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

# Install once per boot; subsequent agent launches inherit their own policy.
sh "$MODDIR/agy-launcher.sh" >> "$LOG" 2>&1
sh "$MODDIR/auto-optimize.sh" >> "$LOG" 2>&1

# These are preferences; app requests and vendor policy decide the actual rate.
settings put system min_refresh_rate 60 >/dev/null 2>&1
settings put system peak_refresh_rate 120 >/dev/null 2>&1
settings put system user_refresh_rate 90 >/dev/null 2>&1
settings delete system customized_refresh_rate >/dev/null 2>&1

# Snappier transitions without a permanent rendering or CPU boost.
settings put global window_animation_scale 0.5 >/dev/null 2>&1
settings put global transition_animation_scale 0.5 >/dev/null 2>&1
settings put global animator_duration_scale 0.5 >/dev/null 2>&1

# Keep an established Wi-Fi link available during doze so push delivery and
# Wi-Fi-to-cellular recovery are not delayed. Android/Oplus still controls
# roaming and validation. No MTU, DNS, congestion-control, or iptables hacks.
settings put global wifi_sleep_policy 2 >/dev/null 2>&1

# Wi-Fi scanning while Wi-Fi is off is separate from keeping an established
# connection alive. It repeatedly wakes the radio for location and network
# discovery, so it costs battery without helping FCM or an active Wi-Fi link.
# Preserve the prior value once so uninstall can restore the user's setting.
# The settings service can be unavailable briefly during boot; never persist
# that error as though it were a setting value.
if [ -f "$WIFI_SCAN_STATE" ]; then
  wifi_scan_state=$(head -n 1 "$WIFI_SCAN_STATE")
  case "$wifi_scan_state" in
    0|1|null) ;;
    *) rm -f "$WIFI_SCAN_STATE" ;;
  esac
fi

if [ ! -f "$WIFI_SCAN_STATE" ]; then
  wifi_scan_state=$(settings get global wifi_scan_always_enabled 2>/dev/null)
  case "$wifi_scan_state" in
    0|1|null) printf '%s\n' "$wifi_scan_state" > "$WIFI_SCAN_STATE" ;;
  esac
fi
settings put global wifi_scan_always_enabled 0 >/dev/null 2>&1

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
save_setting() {
  namespace="$1"
  key="$2"
  file="$POWER_STATE_DIR/$key"
  [ -f "$file" ] && return
  value=$(settings get "$namespace" "$key" 2>/dev/null)
  case "$value" in
    ''|null) printf '%s\n' null > "$file" ;;
    *) printf '%s\n' "$value" > "$file" ;;
  esac
}

save_setting global cached_apps_freezer
save_setting global app_standby_enabled
save_setting global dynamic_power_savings_enabled
save_setting global automatic_power_save_mode
if [ ! -f "$POWER_STATE_DIR/adaptive_power_saver" ]; then
  if dumpsys power 2>/dev/null | grep -q 'adaptive=true'; then
    printf '%s\n' true > "$POWER_STATE_DIR/adaptive_power_saver"
  else
    printf '%s\n' false > "$POWER_STATE_DIR/adaptive_power_saver"
  fi
fi

# Only request the freezer when ActivityManager confirms kernel freezer support.
if dumpsys activity settings 2>/dev/null | grep -q 'use_freezer=true'; then
  settings put global cached_apps_freezer enabled >/dev/null 2>&1
fi
settings put global app_standby_enabled 1 >/dev/null 2>&1
settings put global dynamic_power_savings_enabled 1 >/dev/null 2>&1
settings put global automatic_power_save_mode 1 >/dev/null 2>&1
cmd power set-adaptive-power-saver-enabled true >/dev/null 2>&1

# These apps may use normal background execution so FCM/app notifications are not
# intentionally blocked. Do not add them to the Doze whitelist: that costs battery.
while IFS= read -r pkg; do
  case "$pkg" in
    ''|\#*) continue ;;
  esac
  pm path "$pkg" >/dev/null 2>&1 || continue
  cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
  cmd appops set "$pkg" RUN_IN_BACKGROUND allow >/dev/null 2>&1
done < "$NOTIFICATION_PACKAGES"

# Disable only optional Meta companion packages. The primary Facebook apps are
# intentionally excluded: their normal background operation is needed for
# notifications, media upload, and a responsive next launch. Save the initial
# state once so uninstall restores only packages this module disabled itself.
while IFS= read -r pkg; do
  case "$pkg" in
    ''|\#*) continue ;;
  esac
  pm path "$pkg" >/dev/null 2>&1 || continue
  state_file="$DISABLED_STATE_DIR/$pkg"
  if [ ! -f "$state_file" ]; then
    if pm list packages -d "$pkg" | grep -qx "package:$pkg"; then
      printf '%s\n' disabled > "$state_file"
    else
      printf '%s\n' enabled > "$state_file"
    fi
  fi
  pm disable-user --user 0 "$pkg" >/dev/null 2>&1
  am force-stop "$pkg" >/dev/null 2>&1
done < "$DISABLED_PACKAGES"

if [ -n "$BOOT_ID" ]; then
  printf '%s\n' "$BOOT_ID" > "$MARKER/last_boot_id"
fi
printf '%s LightFlow active (boot %s): adaptive refresh, kernel reclaim, cached-app freezer, adaptive power, notification-safe appops, optional Meta companions disabled\n' "$(date '+%F %T')" "$BOOT_ID" >> "$LOG"
