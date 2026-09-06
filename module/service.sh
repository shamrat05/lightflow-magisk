#!/system/bin/sh

# LightFlow uses reversible settings and a backed-up agy launch hook.
# It does not change thermal limits, CPU governors, ZRAM, SELinux, or vendor props.

MODDIR=${0%/*}
LOG=/data/adb/lightflow.log
MARKER=/data/adb/lightflow
NOTIFICATION_PACKAGES="$MODDIR/notification-packages.conf"
DISABLED_PACKAGES="$MODDIR/disabled-background-packages.conf"
WIFI_SCAN_STATE="$MARKER/wifi_scan_always_enabled"
DISABLED_STATE_DIR="$MARKER/disabled-packages"
MEMORY_STATE_DIR="$MARKER/memory"

mkdir -p "$MARKER"
mkdir -p "$DISABLED_STATE_DIR"
mkdir -p "$MEMORY_STATE_DIR"

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

printf '%s LightFlow active: adaptive refresh, low-overhead memory reclaim, notification-safe appops, optional Meta companions disabled\n' "$(date '+%F %T')" >> "$LOG"
