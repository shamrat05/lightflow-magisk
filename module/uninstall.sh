#!/system/bin/sh

MODDIR=${0%/*}
MARKER=/data/adb/lightflow
WIFI_SCAN_STATE="$MARKER/wifi_scan_always_enabled"
DISABLED_PACKAGES="$MODDIR/disabled-background-packages.conf"
DISABLED_STATE_DIR="$MARKER/disabled-packages"
MEMORY_STATE_DIR="$MARKER/memory"
POWER_STATE_DIR="$MARKER/power"

sh "$MODDIR/agy-launcher.sh" uninstall

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

if [ -f "$MEMORY_STATE_DIR/mglru_enabled" ] && [ -w /sys/kernel/mm/lru_gen/enabled ]; then
  cat "$MEMORY_STATE_DIR/mglru_enabled" > /sys/kernel/mm/lru_gen/enabled
fi
if [ -f "$MEMORY_STATE_DIR/page_cluster" ] && [ -w /proc/sys/vm/page-cluster ]; then
  cat "$MEMORY_STATE_DIR/page_cluster" > /proc/sys/vm/page-cluster
fi
rm -f "$MEMORY_STATE_DIR/mglru_enabled" "$MEMORY_STATE_DIR/page_cluster"
rmdir "$MEMORY_STATE_DIR" >/dev/null 2>&1

restore_setting() {
  key="$1"
  file="$POWER_STATE_DIR/$key"
  [ -f "$file" ] || return
  value=$(head -n 1 "$file")
  case "$value" in
    null|'') settings delete global "$key" >/dev/null 2>&1 ;;
    *) settings put global "$key" "$value" >/dev/null 2>&1 ;;
  esac
  rm -f "$file"
}

restore_setting cached_apps_freezer
restore_setting app_standby_enabled
restore_setting dynamic_power_savings_enabled
restore_setting automatic_power_save_mode
if [ -f "$POWER_STATE_DIR/adaptive_power_saver" ]; then
  adaptive_state=$(head -n 1 "$POWER_STATE_DIR/adaptive_power_saver")
  case "$adaptive_state" in
    true|false) cmd power set-adaptive-power-saver-enabled "$adaptive_state" >/dev/null 2>&1 ;;
  esac
  rm -f "$POWER_STATE_DIR/adaptive_power_saver"
fi
rmdir "$POWER_STATE_DIR" >/dev/null 2>&1

if [ -f "$WIFI_SCAN_STATE" ]; then
  wifi_scan_state=$(head -n 1 "$WIFI_SCAN_STATE")
  case "$wifi_scan_state" in
    null|'') settings delete global wifi_scan_always_enabled >/dev/null 2>&1 ;;
    0|1) settings put global wifi_scan_always_enabled "$wifi_scan_state" >/dev/null 2>&1 ;;
  esac
  rm -f "$WIFI_SCAN_STATE"
fi
rm -f /data/adb/lightflow.log
