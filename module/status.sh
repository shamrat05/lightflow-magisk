#!/system/bin/sh

MODDIR=${0%/*}
cat "$MODDIR/module.prop"
echo "Boot completed: $(getprop sys.boot_completed)"
echo "Refresh preferences (not measured FPS):"
for key in min_refresh_rate peak_refresh_rate user_refresh_rate; do
  echo "$key=$(settings get system "$key")"
done
dumpsys display | grep -E 'mDesiredDisplayModeSpecs=|PRIORITY_APP_REQUEST_RENDER_FRAME_RATE_RANGE'
echo "Memory availability and pressure:"
grep -E 'MemAvailable:|SwapTotal:|SwapFree:' /proc/meminfo
cat /proc/pressure/memory /proc/pressure/cpu
echo "Battery:"
dumpsys battery | grep -E 'powered:|level:|temperature:'
echo "Thermal status and live sensor readings (not cached temperatures):"
dumpsys thermalservice | sed -n '/^Thermal Status:/p; /Current temperatures from HAL:/,/Current cooling devices from HAL:/p'
echo "Target app compilation (verify is not compiled speed-profile code):"
for pkg in com.instagram.android com.linkedin.android com.google.android.youtube com.facebook.katana com.reddit.frontpage; do
  dumpsys package "$pkg" | sed -n '/Dexopt state:/,/Compiler stats:/p'
done
