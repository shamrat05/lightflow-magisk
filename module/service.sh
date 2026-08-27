#!/system/bin/sh

# LightFlow deliberately uses only reversible framework settings and app-ops.
# It does not change thermal limits, CPU governors, ZRAM, SELinux, or vendor props.

MODDIR=${0%/*}
LOG=/data/adb/lightflow.log
MARKER=/data/adb/lightflow

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

# These apps may use normal background execution so FCM/app notifications are not
# intentionally blocked. Do not add them to the Doze whitelist: that costs battery.
for pkg in \
  com.whatsapp \
  com.facebook.orca \
  com.facebook.katana \
  com.google.android.gm \
  org.telegram.messenger \
  org.signal.securesms \
  com.microsoft.office.outlook; do
  pm path "$pkg" >/dev/null 2>&1 || continue
  cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
  cmd appops set "$pkg" RUN_IN_BACKGROUND allow >/dev/null 2>&1
done

printf '%s LightFlow active: adaptive refresh, 0.5x animation, notification-safe appops\n' "$(date '+%F %T')" >> "$LOG"
