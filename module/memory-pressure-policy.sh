#!/system/bin/sh

# Android 15 replacement for the upstream A1 native cleanup engine.
# This is one bounded action, not a resident memory daemon. It asks
# ActivityManager to remove only processes Android already considers safe to
# kill, and only when memory pressure is high. Foreground apps, services,
# notifications, LMKD, and vendor thermal policy stay under Android control.

MODEL=$(getprop ro.product.model 2>/dev/null)
SDK=$(getprop ro.build.version.sdk 2>/dev/null)
LOG=/data/adb/lightflow.log
STATE_DIR=/data/adb/lightflow/memory
LAST_CLEANUP_FILE="$STATE_DIR/last_cleanup_epoch"
MIN_AVAILABLE_KB=1800000
MAX_SWAP_PERCENT=65
MAX_MEMORY_FULL_AVG10=1
COOLDOWN_SECONDS=300

case "$MODEL" in
  RMX3741) ;;
  *)
    [ "${1:-status}" = status ] || printf '%s LightFlow memory policy skipped: unsupported model %s\n' "$(date '+%F %T')" "$MODEL" >> "$LOG"
    exit 0
    ;;
esac
case "$SDK" in
  35) ;;
  *)
    [ "${1:-status}" = status ] || printf '%s LightFlow memory policy skipped: supported only on Android 15 (SDK 35), found %s\n' "$(date '+%F %T')" "$SDK" >> "$LOG"
    exit 0
    ;;
esac

uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  return 0
}

memory_available=$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
swap_total=$(awk '/^SwapTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
swap_free=$(awk '/^SwapFree:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
uint "$memory_available" || memory_available=0
uint "$swap_total" || swap_total=0
uint "$swap_free" || swap_free=0

swap_percent=0
if [ "$swap_total" -gt 0 ] && [ "$swap_total" -ge "$swap_free" ]; then
  swap_percent=$(((swap_total - swap_free) * 100 / swap_total))
fi

memory_full_avg10=0
psi_value=$(awk '/^full / {for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) {sub("avg10=", "", $i); print $i; exit}}' /proc/pressure/memory 2>/dev/null)
case "$psi_value" in
  ''|*[!0-9.]* ) ;;
  *) memory_full_avg10=${psi_value%.*} ;;
esac

status() {
  printf 'Memory pressure: available=%s kB swap=%s%% full.avg10=%s%% (thresholds %s kB/%s%%/%s%%)\n' \
    "$memory_available" "$swap_percent" "$psi_value" "$MIN_AVAILABLE_KB" "$MAX_SWAP_PERCENT" "$MAX_MEMORY_FULL_AVG10"
}

case "${1:-apply}" in
  status)
    status
    ;;
  apply)
    if [ "$memory_available" -lt "$MIN_AVAILABLE_KB" ] || \
       [ "$swap_percent" -ge "$MAX_SWAP_PERCENT" ] || \
       [ "$memory_full_avg10" -ge "$MAX_MEMORY_FULL_AVG10" ]; then
      mkdir -p "$STATE_DIR" 2>/dev/null
      now=$(date +%s 2>/dev/null)
      last=0
      if [ -r "$LAST_CLEANUP_FILE" ]; then
        last=$(head -n 1 "$LAST_CLEANUP_FILE")
      fi
      uint "$now" || now=0
      uint "$last" || last=0
      if [ "$now" -gt 0 ] && [ "$last" -gt 0 ] && [ "$now" -ge "$last" ] && \
         [ $((now - last)) -lt "$COOLDOWN_SECONDS" ]; then
        if [ "${LIGHTFLOW_SILENT:-0}" != 1 ]; then
          printf '%s LightFlow memory relief: cooldown active (%ss remaining; available=%s kB swap=%s%% full.avg10=%s%%)\n' \
            "$(date '+%F %T')" "$((COOLDOWN_SECONDS - now + last))" "$memory_available" "$swap_percent" "$psi_value" >> "$LOG"
        fi
        exit 0
      fi
      if /system/bin/am kill-all >/dev/null 2>&1; then
        [ "$now" -gt 0 ] && printf '%s\n' "$now" > "$LAST_CLEANUP_FILE"
        printf '%s LightFlow memory relief: Android cached-process kill requested (available=%s kB swap=%s%% full.avg10=%s%%)\n' \
          "$(date '+%F %T')" "$memory_available" "$swap_percent" "$psi_value" >> "$LOG"
      else
        printf '%s LightFlow memory relief: Android cached-process request failed (available=%s kB swap=%s%% full.avg10=%s%%)\n' \
          "$(date '+%F %T')" "$memory_available" "$swap_percent" "$psi_value" >> "$LOG"
      fi
    else
      if [ "${LIGHTFLOW_SILENT:-0}" != 1 ]; then
        printf '%s LightFlow memory policy: no cached-process relief needed (available=%s kB swap=%s%% full.avg10=%s%%)\n' \
          "$(date '+%F %T')" "$memory_available" "$swap_percent" "$psi_value" >> "$LOG"
      fi
    fi
    ;;
  *)
    echo 'Usage: memory-pressure-policy.sh {status|apply}' >&2
    exit 2
    ;;
esac
