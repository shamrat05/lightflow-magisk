#!/system/bin/sh

# LightFlow deliberately uses only reversible framework settings and app-ops.
# It does not change thermal limits, CPU governors, ZRAM, SELinux, or vendor props.

MODDIR=${0%/*}
LOG=/data/adb/lightflow.log
MARKER=/data/adb/lightflow
NOTIFICATION_PACKAGES="$MODDIR/notification-packages.conf"
WIFI_SCAN_STATE="$MARKER/wifi_scan_always_enabled"

mkdir -p "$MARKER"
sleep 20

# Keep the responsive 90 Hz preference while retaining 60 Hz idle and 120 Hz headroom.
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

printf '%s LightFlow active: adaptive refresh, 0.5x animation, notification-safe appops\n' "$(date '+%F %T')" >> "$LOG"
