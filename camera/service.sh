#!/system/bin/sh

# This module intentionally avoids private OEM camera preferences. Those vary by
# firmware and can break HDR, stabilization, or recording when changed blindly.

MODDIR=${0%/*}
LOG=/data/adb/ahead_of_modern_time.log
MARKER=/data/adb/ahead_of_modern_time
mkdir -p "$MARKER"
sleep 90

status=$(dumpsys battery 2>/dev/null | sed -n 's/^  status: //p' | head -n 1)
temperature=$(dumpsys battery 2>/dev/null | sed -n 's/^  temperature: //p' | head -n 1)

# Compile only the installed OEM camera while charging and below 42 C. This is
# one targeted build after an app update, not a boot-time all-app compile storm.
case "$status" in
  2|5) ;;
  *) exit 0 ;;
esac
case "$temperature" in
  ''|*[!0-9]*) exit 0 ;;
  *) [ "$temperature" -lt 420 ] || exit 0 ;;
esac

for pkg in com.oplus.camera com.android.camera com.google.android.GoogleCamera; do
  pm path "$pkg" >/dev/null 2>&1 || continue
  version=$(dumpsys package "$pkg" 2>/dev/null | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)
  [ -n "$version" ] || continue
  marker="$MARKER/$pkg.$version"
  [ -e "$marker" ] && continue
  if cmd package compile -m speed-profile -f "$pkg" >/dev/null 2>&1; then
    : > "$marker"
    printf '%s %s speed-profile compilation completed\n' "$(date '+%F %T')" "$pkg" >> "$LOG"
  fi
done
