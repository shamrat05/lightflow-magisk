#!/system/bin/sh

LOG=/data/adb/ahead_of_modern_time.log
found=0

for pkg in com.oplus.camera com.android.camera com.google.android.GoogleCamera; do
  pm path "$pkg" >/dev/null 2>&1 || continue
  found=1
  echo "Compiling only $pkg with its existing speed profile..."
  if cmd package compile -m speed-profile -f "$pkg" >/dev/null 2>&1; then
    printf '%s %s speed-profile compilation completed\n' "$(date '+%F %T')" "$pkg" >> "$LOG"
    echo "Done: $pkg"
  else
    echo "Skipped: $pkg profile compilation was not accepted by this ROM."
  fi
done

[ "$found" -eq 1 ] || echo "No supported camera package was found."
