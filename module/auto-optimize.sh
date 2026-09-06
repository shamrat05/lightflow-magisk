#!/system/bin/sh

# Android owns scheduling, package selection, and cancellation when charging
# or idle constraints cease to hold. Never start bg-dexopt-job without flags:
# that requests immediate work instead of waiting for scheduler constraints.
LOG=/data/adb/lightflow.log
if dumpsys jobscheduler 2>/dev/null | grep -E '^  JOB .*android/com.android.server.(art.BackgroundDexoptJobService|pm.BackgroundDexOptService)' >/dev/null; then
  printf '%s Automatic optimization: Android job already scheduled\n' "$(date '+%F %T')" >> "$LOG"
  exit 0
fi
help=$(cmd package help 2>/dev/null)
case "$help" in
  *'bg-dexopt-job [--cancel | --disable | --enable]'*)
    if result=$(cmd package bg-dexopt-job --enable 2>&1); then
      if dumpsys jobscheduler 2>/dev/null | grep -E '^  JOB .*android/com.android.server.art.BackgroundDexoptJobService' >/dev/null; then
        printf '%s Automatic optimization: Android job scheduled\n' "$(date '+%F %T')" >> "$LOG"
        exit 0
      fi
    fi
    printf '%s Automatic optimization: could not verify scheduling: %s\n' "$(date '+%F %T')" "$result" >> "$LOG"
    exit 1
    ;;
  *)
    printf '%s Automatic optimization: no supported scheduler control found\n' "$(date '+%F %T')" >> "$LOG"
    exit 1
    ;;
esac
