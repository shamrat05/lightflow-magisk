#!/system/bin/sh

# Called by the root agy launcher before it starts the agent. Children inherit
# affinity and nice; no process scanning or resident monitor is needed.
pid=$1
case "$pid" in ''|*[!0-9]*) exit 1 ;; esac
[ -d "/proc/$pid" ] || exit 1

minimum=0
maximum=0
mask=0
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
  [ -r "$cpu/cpu_capacity" ] || continue
  read -r capacity < "$cpu/cpu_capacity"
  case "$capacity" in ''|*[!0-9]*) continue ;; esac
  [ "$capacity" -gt 0 ] || continue
  if [ "$minimum" -eq 0 ] || [ "$capacity" -lt "$minimum" ]; then
    minimum=$capacity
    mask=0
  fi
  [ "$capacity" -le "$maximum" ] || maximum=$capacity
  index=${cpu##*cpu}
  # Android phones fit this mask; skip affinity on larger/unknown topologies.
  [ "$index" -lt 32 ] || exit 0
  if [ "$capacity" -eq "$minimum" ]; then
    mask=$((mask | (1 << index)))
  fi
done
if [ "$minimum" -gt 0 ] && [ "$minimum" -lt "$maximum" ]; then
  /system/bin/taskset -ap "$(printf '%x' "$mask")" "$pid" >/dev/null 2>&1
fi

for task in /proc/"$pid"/task/*; do
  tid=${task##*/}
  priority=$(/system/bin/ps -p "$tid" -o NI 2>/dev/null | awk 'NR == 2 {print $1}')
  case "$priority" in ''|*[!0-9-]*) continue ;; esac
  if [ "$priority" -lt 5 ]; then
    # Android toybox renice takes an increment, not an absolute nice value.
    /system/bin/renice -n "$((5 - priority))" -p "$tid" >/dev/null 2>&1
  fi
done
