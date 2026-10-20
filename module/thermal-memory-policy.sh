#!/system/bin/sh

# Bounded memory and thermal relief. No resident monitor, frequency lock,
# thermal override, ZRAM resize, cache wipe, or user-app force-stop.

MODDIR=${0%/*}
MARKER=/data/adb/lightflow
STATE="$MARKER/memory"
SWAPPINESS_STATE="$STATE/swappiness"
TARGET_SWAPPINESS=60
THERMAL_CPU_MILLI=65000
THERMAL_SKIN_MILLI=50000
THERMAL_BATTERY_MILLI=42000
LOG=/data/adb/lightflow.log

mkdir -p "$STATE" || exit 1

uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  return 0
}

read_value() {
  file=$1
  [ -r "$file" ] || return 1
  value=$(cat "$file" 2>/dev/null) || return 1
  uint "$value" || return 1
  printf '%s\n' "$value"
}

cpu_milli=0
skin_milli=0
for type_file in /sys/class/thermal/thermal_zone*/type; do
  [ -r "$type_file" ] || continue
  type=$(cat "$type_file" 2>/dev/null)
  temp_file=${type_file%/type}/temp
  temp=$(read_value "$temp_file") || continue
  case "$type" in
    mtktscpu|mtktsAP|mtktsAP_NTC|cpu-therm|cpu_therm) [ "$temp" -gt "$cpu_milli" ] && cpu_milli=$temp ;;
    shell_skin|skin-therm|skin_therm) [ "$temp" -gt "$skin_milli" ] && skin_milli=$temp ;;
  esac
done

battery_milli=0
battery_raw=$(dumpsys battery 2>/dev/null) || battery_raw=
battery_temp=$(printf '%s\n' "$battery_raw" | awk '/^[[:space:]]*temperature:/ {print $2; exit}')
if uint "$battery_temp"; then
  battery_milli=$((battery_temp * 100))
fi

thermal_status=$(dumpsys thermalservice 2>/dev/null | awk '/^Thermal Status:/ {print $3; exit}')
case "$thermal_status" in 2|3|4|5|6) thermal_hot=1 ;; *) thermal_hot=0 ;; esac
[ "$cpu_milli" -ge "$THERMAL_CPU_MILLI" ] && thermal_hot=1
[ "$skin_milli" -ge "$THERMAL_SKIN_MILLI" ] && thermal_hot=1
[ "$battery_milli" -ge "$THERMAL_BATTERY_MILLI" ] && thermal_hot=1

memory_available=$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
swap_total=$(awk '/^SwapTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
swap_free=$(awk '/^SwapFree:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
uint "$memory_available" || memory_available=0
uint "$swap_total" || swap_total=0
uint "$swap_free" || swap_free=0
swap_used=0
swap_percent=0
if [ "$swap_total" -gt 0 ] && [ "$swap_total" -ge "$swap_free" ]; then
  swap_used=$((swap_total - swap_free))
  swap_percent=$((swap_used * 100 / swap_total))
fi

current_swappiness=$(read_value /proc/sys/vm/swappiness 2>/dev/null) || current_swappiness=

apply_swappiness() {
  [ -n "$current_swappiness" ] || return 0
  [ "$current_swappiness" -gt "$TARGET_SWAPPINESS" ] || return 0
  if [ ! -f "$SWAPPINESS_STATE" ]; then
    printf '%s\n' "$current_swappiness" > "$SWAPPINESS_STATE" || return 1
  fi
  [ -w /proc/sys/vm/swappiness ] || return 0
  printf '%s\n' "$TARGET_SWAPPINESS" > /proc/sys/vm/swappiness || return 1
  [ "$(cat /proc/sys/vm/swappiness 2>/dev/null)" = "$TARGET_SWAPPINESS" ] || return 1
  current_swappiness=$TARGET_SWAPPINESS
}

set_cool_display() {
  settings put system min_refresh_rate 60 >/dev/null 2>&1 || return 1
  settings put system peak_refresh_rate 60 >/dev/null 2>&1 || return 1
  settings put system user_refresh_rate 60 >/dev/null 2>&1 || return 1
  return 0
}

set_normal_display() {
  settings put system min_refresh_rate 60 >/dev/null 2>&1 || return 1
  settings put system peak_refresh_rate 120 >/dev/null 2>&1 || return 1
  settings put system user_refresh_rate 90 >/dev/null 2>&1 || return 1
  return 0
}

restore_swappiness() {
  [ -f "$SWAPPINESS_STATE" ] || return 0
  saved=$(cat "$SWAPPINESS_STATE" 2>/dev/null) || return 1
  uint "$saved" || return 1
  current=$(read_value /proc/sys/vm/swappiness 2>/dev/null) || return 1
  # Preserve a later user or vendor change.
  [ "$current" = "$TARGET_SWAPPINESS" ] || return 0
  [ -w /proc/sys/vm/swappiness ] || return 1
  printf '%s\n' "$saved" > /proc/sys/vm/swappiness || return 1
  [ "$(cat /proc/sys/vm/swappiness 2>/dev/null)" = "$saved" ] || return 1
  rm -f "$SWAPPINESS_STATE"
}

status() {
  printf 'Memory available: %s kB\n' "$memory_available"
  printf 'Swap used: %s%% (%s/%s kB)\n' "$swap_percent" "$swap_used" "$swap_total"
  printf 'Swappiness: %s (target %s)\n' "${current_swappiness:-unknown}" "$TARGET_SWAPPINESS"
  printf 'Thermal status: %s; CPU=%s mC skin=%s mC battery=%s mC\n' "${thermal_status:-unknown}" "$cpu_milli" "$skin_milli" "$battery_milli"
}

case "${1:-apply}" in
  status)
    status
    ;;
  apply)
    apply_swappiness || exit 1
    printf '%s LightFlow memory policy: available=%s kB swap=%s%% swappiness=%s thermal=%s\n' "$(date '+%F %T')" "$memory_available" "$swap_percent" "${current_swappiness:-unknown}" "${thermal_status:-unknown}" >> "$LOG"
    ;;
  cool)
    apply_swappiness || exit 1
    # Manual Magisk action relief. Android only kills cached processes here;
    # foreground apps and notification services are not force-stopped.
    if [ "$thermal_hot" -eq 1 ] || [ "$memory_available" -lt 1200000 ] || [ "$swap_percent" -ge 75 ]; then
      set_cool_display || exit 1
      printf '%s LightFlow manual display relief: 60 Hz applied; no apps killed\n' "$(date '+%F %T')" >> "$LOG"
      echo '60 Hz thermal mode applied; no apps killed.'
    else
      set_normal_display || exit 1
      echo 'No heat or memory-pressure threshold reached; no processes stopped.'
    fi
    status
    ;;
  restore)
    restore_swappiness
    ;;
  *)
    echo 'Usage: thermal-memory-policy.sh {status|apply|cool|restore}' >&2
    exit 2
    ;;
esac
