#!/system/bin/sh
# Diagnostics-only compatibility entry. LMKD owns emergency reclaim.
case "${1:-status}" in
  status|apply)
    echo 'Memory policy: event-driven OEM guard; no shell cleanup or kill timer.'
    grep -E '^MemAvailable:|^SwapTotal:|^SwapFree:' /proc/meminfo
    cat /proc/pressure/memory 2>/dev/null
    ;;
  *) echo 'Usage: memory-pressure-policy.sh {status|apply}' >&2; exit 2 ;;
esac
