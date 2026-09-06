#!/system/bin/sh

LOG=/data/adb/lightflow.log
failed=0
compile_help=$(cmd package help 2>/dev/null)

# ART's default command-line priority is interactive. Use its background
# resource policy where supported, and let it skip up-to-date artifacts.
set -- -m speed-profile
case "$compile_help" in
  *PRIORITY_BACKGROUND*) set -- "$@" -p PRIORITY_BACKGROUND -v ;;
esac

for pkg in \
  com.google.android.youtube \
  com.facebook.katana \
  com.whatsapp \
  com.whatsapp.w4b \
  com.linkedin.android \
  com.reddit.frontpage; do
  pm path "$pkg" >/dev/null 2>&1 || continue
  temperature=$(dumpsys battery | awk '/^[[:space:]]*temperature:/ {print $2; exit}')
  case "$temperature" in
    ''|*[!0-9]*) echo "Cannot read battery temperature; retry later."; exit 1 ;;
  esac
  if [ "$temperature" -ge 400 ]; then
    echo "Battery is at least 40 C; let the phone cool before retrying."
    exit 1
  fi
  echo "Compiling only $pkg with its existing speed profile..."
  if result=$(cmd package compile "$@" "$pkg" 2>&1); then
    echo "Request accepted: $pkg (without a usable profile, ART may only verify)."
  else
    echo "Not completed: $pkg; see the result below."
    failed=1
  fi
  printf '%s\n' "$result"
  printf '%s %s: %s\n' "$(date '+%F %T')" "$pkg" "$result" >> "$LOG"
done

if [ "$failed" -eq 0 ]; then
  echo "Targeted requests accepted. This does not measure app speed."
fi
exit "$failed"
