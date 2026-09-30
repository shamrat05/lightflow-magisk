#!/system/bin/sh

# User-selected RMX3741 policy: Weather may locate only while in foreground.
# Use UID modes: this Realme build overrides package-level location modes.
PACKAGE=com.coloros.weather.service
STATE=/data/adb/lightflow/weather
[ "$(getprop ro.product.model)" = RMX3741 ] || exit 0
packages=$(pm list packages --user 0 -U) || exit 1
uid=$(printf '%s\n' "$packages" | awk -v p="package:$PACKAGE" '$1 == p {sub(/^uid:/, "", $2); print $2; exit}')
case "$uid" in ''|*[!0-9]*) exit 0 ;; esac
# Never restrict another package sharing Weather's UID.
count=$(printf '%s\n' "$packages" | awk -v u="uid:$uid" '$2 == u {n++} END {print n+0}')
[ "$count" = 1 ] || exit 0

uid_mode() {
  result=$(cmd appops get "$uid" "$1" 2>/dev/null) || return 1
  mode=$(printf '%s\n' "$result" | sed -n "s/^Uid mode: $1: \([^; ]*\).*/\1/p")
  if [ -z "$mode" ]; then
    case "$result" in
      *'No operations.'*) mode=$(printf '%s\n' "$result" | sed -n 's/^Default mode: \([^; ]*\).*/\1/p') ;;
      *) return 1 ;;
    esac
  fi
  case "$mode" in allow|foreground|ignore|deny|default) printf '%s\n' "$mode" ;; *) return 1 ;; esac
}

failed=0
for op in FINE_LOCATION COARSE_LOCATION; do
  current=$(uid_mode "$op") || { failed=1; continue; }
  saved=$STATE/$op
  case "${1:-apply}" in
    status)
      printf 'Weather UID %s %s: %s\n' "$uid" "$op" "$current"
      ;;
    apply)
      # Preserve an existing, stricter user restriction.
      case "$current" in ignore|deny) continue ;; esac
      mkdir -p "$STATE" || exit 1
      if [ ! -f "$saved" ]; then
        printf '%s\n' "$current" > "$saved" || exit 1
      fi
      cmd appops set --user 0 --uid "$PACKAGE" "$op" foreground || { failed=1; continue; }
      [ "$(uid_mode "$op")" = foreground ] || failed=1
      ;;
    restore)
      [ -f "$saved" ] || continue
      original=$(cat "$saved")
      case "$original" in default) original=allow ;; allow|foreground|ignore|deny) ;; *) failed=1; continue ;; esac
      if [ "$current" = foreground ]; then
        cmd appops set --user 0 --uid "$PACKAGE" "$op" "$original" || { failed=1; continue; }
        [ "$(uid_mode "$op")" = "$original" ] || { failed=1; continue; }
      fi
      rm -f "$saved"
      ;;
    *) exit 2 ;;
  esac
done
[ "${1:-apply}" != restore ] || rmdir "$STATE" 2>/dev/null
exit "$failed"
