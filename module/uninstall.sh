#!/system/bin/sh

MODDIR=${0%/*}

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
rm -f /data/adb/lightflow.log
