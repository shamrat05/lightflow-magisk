#!/system/bin/sh

# RMX3741 boots with initcall_debug=1, which enables per-device suspend/resume
# timing prints. Disable only those diagnostic messages, not power management.
NODE=/sys/power/pm_print_times
SAVED=/data/adb/lightflow/power/pm_print_times
mode=${1:-apply}
case "$mode" in apply|restore|status) ;; *) exit 2 ;; esac
[ "$(getprop ro.product.model)" = RMX3741 ] || exit 0
if [ ! -r "$NODE" ] || [ ! -w "$NODE" ]; then
  [ "$mode" != status ] || echo 'Kernel sleep timing logs: unavailable'
  exit 0
fi
current=$(cat "$NODE") || exit 1
case "$current" in 0|1) ;; *) exit 1 ;; esac

case "$mode" in
  status)
    printf 'Kernel sleep timing logs: %s (LightFlow target: 0/off)\n' "$current"
    ;;
  apply)
    # Already-disabled logging needs no change or ownership claim.
    [ "$current" = 1 ] || exit 0
    mkdir -p "${SAVED%/*}" || exit 1
    if [ -f "$SAVED" ]; then
      original=$(cat "$SAVED") || exit 1
      case "$original" in 0|1) ;; *) exit 1 ;; esac
    else
      printf '%s\n' "$current" > "$SAVED" || exit 1
    fi
    printf '0\n' > "$NODE" || exit 1
    [ "$(cat "$NODE")" = 0 ] || exit 1
    echo 'Kernel sleep timing logs verified: off'
    ;;
  restore)
    [ -f "$SAVED" ] || exit 0
    original=$(cat "$SAVED") || exit 1
    case "$original" in 0|1) ;; *) exit 1 ;; esac
    # Preserve a later user/vendor decision to turn logging back on.
    if [ "$current" = 0 ]; then
      printf '%s\n' "$original" > "$NODE" || exit 1
      [ "$(cat "$NODE")" = "$original" ] || exit 1
    fi
    rm -f "$SAVED" || exit 1
    ;;
esac
