#!/system/bin/sh

MODDIR=${0%/*}
cat "$MODDIR/module.prop"
echo "Boot completed: $(getprop sys.boot_completed)"
echo "Automatic optimization job and constraints:"
dumpsys jobscheduler | awk '/^  JOB / {show = /android\/com.android.server.(art.BackgroundDexoptJobService|pm.BackgroundDexOptService)/} show {print}'
echo "Refresh preferences (not measured FPS):"
for key in min_refresh_rate peak_refresh_rate user_refresh_rate; do
  echo "$key=$(settings get system "$key")"
done
dumpsys display | grep -E 'mDesiredDisplayModeSpecs=|PRIORITY_APP_REQUEST_RENDER_FRAME_RATE_RANGE'
echo "Memory availability and pressure:"
grep -E 'MemAvailable:|SwapTotal:|SwapFree:' /proc/meminfo
cat /proc/pressure/memory /proc/pressure/cpu
echo "Global app/power policy:"
for key in cached_apps_freezer app_standby_enabled dynamic_power_savings_enabled automatic_power_save_mode; do
  echo "$key=$(settings get global "$key")"
done
dumpsys activity settings | grep -E 'use_freezer=|use_compaction=|max_cached_processes=' | head -3
dumpsys power | grep -E 'adaptive=|mSettingBatterySaverEnabled=|mDynamicPowerSavingsEnableBatterySaver=' | head -3
echo "Kernel CPU/reclaim policy:"
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  printf '%s governor=' "$p"
  cat "$p/scaling_governor" 2>/dev/null
  printf ' min='; cat "$p/scaling_min_freq" 2>/dev/null
  printf ' max='; cat "$p/scaling_max_freq" 2>/dev/null
done
for f in /sys/kernel/mm/lru_gen/enabled /proc/sys/vm/page-cluster /proc/sys/vm/swappiness; do
  [ -r "$f" ] && printf '%s=' "$f" && cat "$f"
done
echo "Battery:"
dumpsys battery | grep -E 'powered:|level:|temperature:'
echo "Thermal status and live sensor readings (not cached temperatures):"
dumpsys thermalservice | sed -n '/^Thermal Status:/p; /Current temperatures from HAL:/,/Current cooling devices from HAL:/p'
echo "Target app compilation (verify is not compiled speed-profile code):"
for pkg in com.instagram.android com.linkedin.android com.google.android.youtube com.facebook.katana com.facebook.orca com.reddit.frontpage; do
  dumpsys package "$pkg" | sed -n '/Dexopt state:/,/Compiler stats:/p'
done
