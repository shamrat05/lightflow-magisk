#!/system/bin/sh

# Low-frequency memory watchdog. It only schedules Android's own cached-process
# cleanup; it never selects or kills arbitrary PIDs. Android therefore keeps the
# foreground app, persistent services, notification listeners, accessibility,
# dialer/SMS, and active VPN services under its normal LMKD policy.

MODDIR=${0%/*}
LOG=/data/adb/lightflow.log
PID_FILE=/data/adb/lightflow/memory/watchdog.pid
STATE_DIR=/data/adb/lightflow/memory
MIN_AVAILABLE_KB=1800000
HIGH_TARGET_KB=2200000
MAX_SWAP_PERCENT=65
IDLE_SECONDS=75
PANIC_SECONDS=12

MODEL=$(getprop ro.product.model 2>/dev/null)
SDK=$(getprop ro.build.version.sdk 2>/dev/null)
case "$MODEL:$SDK" in
  RMX3741:35) ;;
  *) exit 0 ;;
esac

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

read_metrics() {
  memory_available=$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
  swap_total=$(awk '/^SwapTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
  swap_free=$(awk '/^SwapFree:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
  case "$memory_available" in ''|*[!0-9]*) memory_available=0 ;; esac
  case "$swap_total" in ''|*[!0-9]*) swap_total=0 ;; esac
  case "$swap_free" in ''|*[!0-9]*) swap_free=0 ;; esac
  swap_percent=0
  if [ "$swap_total" -gt 0 ] && [ "$swap_total" -ge "$swap_free" ]; then
    swap_percent=$(((swap_total - swap_free) * 100 / swap_total))
  fi
}

is_pressure() {
  [ "$memory_available" -lt "$MIN_AVAILABLE_KB" ] || \
    [ "$swap_percent" -ge "$MAX_SWAP_PERCENT" ]
}

loop() {
  panic=0
  while :; do
    # Magisk writes this marker before disabling a module. Exit promptly so a
    # disabled module cannot keep applying memory policy until the next reboot.
    [ -f /data/adb/modules/lightflow/disable ] && exit 0
    [ -f /data/adb/modules/lightflow/disable_mnt ] && exit 0
    read_metrics
    if is_pressure; then
      panic=1
      LIGHTFLOW_SILENT=1 sh "$MODDIR/memory-pressure-policy.sh" apply
      sleep "$PANIC_SECONDS"
      continue
    fi

    # Stay in the faster state until the hysteresis target is reached. This
    # prevents rapid idle/panic switching around the low trigger.
    if [ "$panic" -eq 1 ] && [ "$memory_available" -le "$HIGH_TARGET_KB" ]; then
      sleep "$PANIC_SECONDS"
      continue
    fi
    panic=0
    sleep "$IDLE_SECONDS"
  done
}

case "${1:-start}" in
  start)
    old_pid=$(head -n 1 "$PID_FILE" 2>/dev/null)
    case "$old_pid" in
      ''|*[!0-9]*) ;;
      *) kill -0 "$old_pid" 2>/dev/null && exit 0 ;;
    esac
    (exec "$0" loop) >/dev/null 2>&1 &
    printf '%s\n' "$!" > "$PID_FILE"
    printf '%s LightFlow memory watchdog started (idle=%ss panic=%ss target=%s kB cooldown=300s)\n' \
      "$(date '+%F %T')" "$IDLE_SECONDS" "$PANIC_SECONDS" "$HIGH_TARGET_KB" >> "$LOG"
    ;;
  loop)
    loop
    ;;
  *)
    echo 'Usage: memory-watchdog.sh {start}' >&2
    exit 2
    ;;
esac
