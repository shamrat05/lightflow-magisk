#!/system/bin/sh

# Restore only the app-ops this module touches. Refresh and animation settings
# are intentionally left at the user's current values.
for pkg in \
  com.whatsapp \
  com.facebook.orca \
  com.facebook.katana \
  com.google.android.gm \
  org.telegram.messenger \
  org.signal.securesms \
  com.microsoft.office.outlook; do
  pm path "$pkg" >/dev/null 2>&1 || continue
  cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND default >/dev/null 2>&1
  cmd appops set "$pkg" RUN_IN_BACKGROUND default >/dev/null 2>&1
done
rm -f /data/adb/lightflow.log
