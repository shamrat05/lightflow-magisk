#!/system/bin/sh
# Diagnostics-only compatibility entry. LMKD owns emergency reclaim.
case "${1:-status}" in
  status|apply)
    echo 'Memory policy: event-driven OEM guard; no shell cleanup or kill timer.'
    grep -E '^MemAvailable:|^SwapTotal:|^SwapFree:' /proc/meminfo
    cat /proc/pressure/memory 2>/dev/null
    if [ "${1:-status}" = status ]; then
      if lmk=$(dumpsys -t 3 activity lmk 2>/dev/null) &&
         printf '%s\n' "$lmk" | grep -q 'Total number of kills:'; then
        echo 'Android LMKD kill counts since ActivityManager started:'
        printf '%s\n' "$lmk" | grep -E 'Total number of kills:|kills at or below oom_adj (900|200):'
      else
        echo 'Android LMKD kill counts: unavailable'
      fi
    fi
    ;;
  *) echo 'Usage: memory-pressure-policy.sh {status|apply}' >&2; exit 2 ;;
esac
