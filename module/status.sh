#!/system/bin/sh

MODDIR=${0%/*}
cat "$MODDIR/module.prop"
echo "Boot completed: $(getprop sys.boot_completed)"
echo "LightFlow startup and policy checks:"
if [ -x "$MODDIR/service.sh" ]; then
  echo "service.sh: executable"
else
  echo "service.sh: NOT executable (Magisk may skip startup)"
fi
if [ -e "$MODDIR/disable" ] || [ -e "$MODDIR/remove" ]; then
  echo "module: disabled"
else
  echo "module: enabled"
fi
current_boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
last_boot_id=$(cat /data/adb/lightflow/last_boot_id 2>/dev/null)
if [ -n "$current_boot_id" ] && [ "$current_boot_id" = "$last_boot_id" ]; then
  echo "service: ran this boot"
else
  echo "service: NOT verified for this boot"
fi
if [ -f /data/adb/lightflow.log ]; then
  echo "last active log: $(grep 'LightFlow active ' /data/adb/lightflow.log | tail -n 1)"
else
  echo "last active log: MISSING"
fi
for pair in \
  'global cached_apps_freezer enabled' \
  'global app_standby_enabled 1' \
  'global dynamic_power_savings_enabled 1' \
  'global automatic_power_save_mode 1' \
  'global wifi_scan_always_enabled 0' \
  'system min_refresh_rate 60' \
  'system peak_refresh_rate 120.0' \
  'system user_refresh_rate 90'; do
  set -- $pair
  namespace=$1
  key=$2
  expected=$3
  actual=$(settings get "$namespace" "$key" 2>/dev/null)
  if [ "$actual" = "$expected" ] || { [ "$expected" = 120.0 ] && [ "$actual" = 120 ]; }; then
    printf 'OK %s/%s=%s\n' "$namespace" "$key" "$actual"
  else
    printf 'MISMATCH %s/%s expected=%s actual=%s\n' "$namespace" "$key" "$expected" "$actual"
  fi
done
if dumpsys power 2>/dev/null | grep -q 'adaptive=true'; then
  echo "OK adaptive power saver enabled"
else
  echo "MISMATCH adaptive power saver is not enabled"
fi
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
