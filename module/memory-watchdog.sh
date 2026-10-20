#!/system/bin/sh
# Compatibility stop entry for upgrades. Never start another cleanup timer.
# Validate exact argv before signalling; a stored PID can be reused after boot.
ps -A -o PID,ARGS | while read -r pid interpreter path mode rest; do
  case "$pid" in ''|*[!0-9]*) continue ;; esac
  case "$interpreter:$path:$mode:$rest" in
    'sh:/data/adb/modules/lightflow/memory-watchdog.sh:loop:'|\
    '/system/bin/sh:/data/adb/modules/lightflow/memory-watchdog.sh:loop:'|\
    'sh:/data/adb/modules_update/lightflow/memory-watchdog.sh:loop:'|\
    '/system/bin/sh:/data/adb/modules_update/lightflow/memory-watchdog.sh:loop:') ;;
    *) continue ;;
  esac
  args=$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
  case "$args" in
    "$interpreter $path loop ") kill -9 "$pid" 2>/dev/null || true ;;
  esac
done
rm -f /data/adb/lightflow/memory/watchdog.pid
echo 'LightFlow: periodic cached-app eviction retired; no watchdog started.'
