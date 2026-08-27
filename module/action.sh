#!/system/bin/sh

LOG=/data/adb/lightflow.log
PKG=com.facebook.katana

if ! pm path "$PKG" >/dev/null 2>&1; then
  echo "Facebook is not installed; nothing to compile."
  exit 0
fi

echo "Compiling only Facebook with its existing speed profile..."
if cmd package compile -m speed-profile -f "$PKG" >/dev/null 2>&1; then
  printf '%s Facebook speed-profile compilation completed\n' "$(date '+%F %T')" >> "$LOG"
  echo "Done. This is a one-time targeted compile, not an all-app compile loop."
  exit 0
fi

echo "Facebook profile compilation was not accepted by this ROM; no system settings were changed."
