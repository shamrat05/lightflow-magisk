#!/system/bin/sh

LOG=/data/adb/lightflow.log
failed=0

for pkg in \
  com.facebook.katana \
  com.whatsapp \
  com.whatsapp.w4b \
  com.linkedin.android \
  com.reddit.frontpage; do
  pm path "$pkg" >/dev/null 2>&1 || continue
  echo "Compiling only $pkg with its existing speed profile..."
  if cmd package compile -m speed-profile -f "$pkg" >/dev/null 2>&1; then
    printf '%s %s speed-profile compilation completed\n' "$(date '+%F %T')" "$pkg" >> "$LOG"
    echo "Done: $pkg"
  else
    echo "Skipped: $pkg profile compilation was not accepted by this ROM."
    failed=1
  fi
done

if [ "$failed" -eq 0 ]; then
  echo "Targeted profiles completed; no all-app compile loop was run."
fi
