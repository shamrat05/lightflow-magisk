#!/system/bin/sh

# Runs as Termux, once before exec. No root call, daemon or extra wakeup job.
# The marker belongs to the boot where the enabled module installed this helper.
state_dir=${LIGHTFLOW_CODEX_STATE:-/data/data/com.termux/files/home/.lightflow}
boot_file=${LIGHTFLOW_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}
read -r applied_boot 2>/dev/null < "$state_dir/codex-boot-id" || exit 0
read -r current_boot 2>/dev/null < "$boot_file" || exit 0
[ -n "$current_boot" ] && [ "$applied_boot" = "$current_boot" ] || exit 0

pid=$1
case "$pid" in ''|*[!0-9]*) exit 1 ;; esac
prefix=/data/data/com.termux/files/usr
proc_root=${LIGHTFLOW_PROC_ROOT:-/proc}
cpu_root=${LIGHTFLOW_CPU_ROOT:-/sys/devices/system/cpu}
[ -d "$proc_root/$pid" ] || exit 1
owner=$("$prefix/bin/stat" -c '%u' "$proc_root/$pid" 2>/dev/null) || exit 1
[ "$owner" = "$("$prefix/bin/id" -u)" ] || exit 1

priority=$("$prefix/bin/ps" -p "$pid" -o ni= 2>/dev/null)
case "$priority" in ''|*[!0-9\ -]*) exit 1 ;; esac
if [ "$priority" -lt 5 ]; then
  "$prefix/bin/renice" --priority 5 --pid "$pid" >/dev/null 2>&1 || exit 1
fi

minimum=0
maximum=0
mask=0
for cpu in "$cpu_root"/cpu[0-9]*; do
  [ -r "$cpu/cpu_capacity" ] || continue
  read -r capacity < "$cpu/cpu_capacity" || continue
  case "$capacity" in ''|*[!0-9]*) continue ;; esac
  [ "$capacity" -gt 0 ] || continue
  index=${cpu##*cpu}
  case "$index" in ''|*[!0-9]*) exit 0 ;; esac
  [ "$index" -lt 32 ] || exit 0
  if [ "$minimum" -eq 0 ] || [ "$capacity" -lt "$minimum" ]; then
    minimum=$capacity
    mask=0
  fi
  [ "$capacity" -le "$maximum" ] || maximum=$capacity
  if [ "$capacity" -eq "$minimum" ]; then
    mask=$((mask | (1 << index)))
  fi
done
# taskset respects the caller's cpuset. A rejected affinity leaves vendor policy.
if [ "$minimum" -gt 0 ] && [ "$minimum" -lt "$maximum" ]; then
  "$prefix/bin/taskset" -p "$(printf '%x' "$mask")" "$pid" >/dev/null 2>&1 || exit 0
fi
