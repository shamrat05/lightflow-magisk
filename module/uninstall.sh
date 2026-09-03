#!/system/bin/sh

MODDIR=${0%/*}
MARKER=/data/adb/lightflow
WIFI_SCAN_STATE="$MARKER/wifi_scan_always_enabled"
DISABLED_PACKAGES="$MODDIR/disabled-background-packages.conf"
DISABLED_STATE_DIR="$MARKER/disabled-packages"

# Restore only the app-ops this module touches. Refresh and animation settings
# are intentionally left at the user's current values.
while IFS= read -r pkg; do
  case "$pkg" in
    ''|\#*) continue ;;
  esac
  pm path "$pkg" >/dev/null 2>&1 || continue
  cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND default >/dev/null 2>&1
  cmd appops set "$pkg" RUN_IN_BACKGROUND default >/dev/null 2>&1
done < "$MODDIR/notification-packages.conf"

while IFS= read -r pkg; do
  case "$pkg" in
    ''|\#*) continue ;;
  esac
  state_file="$DISABLED_STATE_DIR/$pkg"
  if [ -f "$state_file" ] && [ "$(head -n 1 "$state_file")" = enabled ]; then
    pm enable "$pkg" >/dev/null 2>&1
  fi
  rm -f "$state_file"
done < "$DISABLED_PACKAGES"
rmdir "$DISABLED_STATE_DIR" >/dev/null 2>&1

if [ -f "$WIFI_SCAN_STATE" ]; then
  wifi_scan_state=$(head -n 1 "$WIFI_SCAN_STATE")
  case "$wifi_scan_state" in
    null|'') settings delete global wifi_scan_always_enabled >/dev/null 2>&1 ;;
    0|1) settings put global wifi_scan_always_enabled "$wifi_scan_state" >/dev/null 2>&1 ;;
  esac
  rm -f "$WIFI_SCAN_STATE"
fi
rm -f /data/adb/lightflow.log
