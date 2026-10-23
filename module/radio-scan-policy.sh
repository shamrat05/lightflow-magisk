#!/system/bin/sh

# These switches permit discovery while the corresponding radio is off.
# They do not disable Wi-Fi, Bluetooth, established links or app notifications.
# Apply once at boot. Do not fight a later user/vendor change with a poller.
state=${LIGHTFLOW_RADIO_STATE:-/data/adb/lightflow}
mode=${1:-apply}
keys='wifi_scan_always_enabled ble_scan_always_enabled'

valid() {
  case "$1" in 0|1|null) return 0 ;; *) return 1 ;; esac
}

read_setting() {
  actual=$(timeout -k 1 5 settings get global "$key" 2>/dev/null) || return 1
  valid "$actual"
}

write_setting() {
  timeout -k 1 5 settings "$@" >/dev/null 2>&1
}

case "$mode" in
  apply) mkdir -p "$state" || exit 1 ;;
  restore|status) ;;
  *) echo 'Usage: radio-scan-policy.sh apply|restore|status' >&2; exit 2 ;;
esac

failed=0
for key in $keys; do
  file=$state/$key
  if [ "$mode" = status ]; then
    if read_setting; then
      printf '%s=%s (scanning while radio off)\n' "$key" "$actual"
    else
      printf '%s=unavailable\n' "$key"
      failed=1
    fi
    continue
  fi
  if [ -e "$file" ] && [ ! -f "$file" ]; then
    echo "LightFlow: $key backup path is not a file; left unchanged." >&2
    failed=1
    continue
  fi
  [ "$mode" != restore ] || [ -f "$file" ] || continue
  if ! read_setting; then
    echo "LightFlow: $key read failed; left unchanged." >&2
    failed=1
    continue
  fi
  if [ -f "$file" ]; then
    if ! read -r saved < "$file" || ! valid "$saved"; then
      echo "LightFlow: $key backup invalid; preserved for review." >&2
      failed=1
      continue
    fi
  else
    saved=$actual
    if ! (umask 077; printf '%s\n' "$saved" > "$file.tmp.$$") ||
       ! mv "$file.tmp.$$" "$file"; then
      rm -f "$file.tmp.$$"
      echo "LightFlow: $key backup failed; left unchanged." >&2
      failed=1
      continue
    fi
  fi
  if [ "$mode" = apply ]; then
    if [ "$actual" != 0 ] && ! write_setting put global "$key" 0; then
      failed=1
      continue
    fi
    if ! read_setting || [ "$actual" != 0 ]; then
      echo "LightFlow: $key disable not verified; backup retained." >&2
      failed=1
    fi
  else
    # A different current value belongs to a later user/vendor choice.
    # Keep it and relinquish ownership instead of overwriting that choice.
    if [ "$actual" != 0 ]; then
      rm -f "$file" || failed=1
      continue
    fi
    if [ "$saved" = null ]; then
      write_setting delete global "$key" || { failed=1; continue; }
    elif [ "$actual" != "$saved" ]; then
      write_setting put global "$key" "$saved" || { failed=1; continue; }
    fi
    if read_setting && [ "$actual" = "$saved" ]; then
      rm -f "$file" || failed=1
    else
      failed=1
    fi
  fi
done
exit "$failed"
