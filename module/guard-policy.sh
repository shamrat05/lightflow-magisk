#!/system/bin/sh
MODDIR=${0%/*}
PKG=dev.lightflow.guard
CLI=/data/adb/lspd/cli

case "${1:-status}" in
  stop) setprop sys.lightflow.guard 0; exit $? ;;
  status)
    echo "System guard enabled: $(getprop sys.lightflow.guard)"
    pm path "$PKG" 2>/dev/null || true
    [ -x "$CLI" ] && "$CLI" scope ls "$PKG" --json
    echo 'Registered scope does not prove hooks executed; check LightFlowGuard boot logs.'
    exit 0 ;;
  start) ;;
  *) echo 'Usage: guard-policy.sh {start|stop|status}' >&2; exit 2 ;;
esac

setprop sys.lightflow.guard 0 || exit 1
[ "$(getprop ro.product.model)" = RMX3741 ] || exit 1
[ "$(getprop ro.build.version.sdk)" = 35 ] || exit 1
sh "$MODDIR/memory-watchdog.sh" stop || exit 1
[ -x "$CLI" ] && [ -r "$MODDIR/guard.apk" ] || {
  echo 'LightFlow guard not enabled: Vector CLI or packaged APK missing.'; exit 1;
}
packaged=$(sha256sum "$MODDIR/guard.apk" | cut -d ' ' -f 1)
installed_path=$(pm path "$PKG" 2>/dev/null | sed -n 's/^package://p' | head -1)
installed=
[ -n "$installed_path" ] && installed=$(sha256sum "$installed_path" 2>/dev/null | cut -d ' ' -f 1)
if [ "$packaged" != "$installed" ]; then
  cp "$MODDIR/guard.apk" /data/local/tmp/lightflow-guard.apk || exit 1
  chmod 0644 /data/local/tmp/lightflow-guard.apk || exit 1
  pm install -r /data/local/tmp/lightflow-guard.apk || exit 1
fi
attempt=0
until "$CLI" modules enable "$PKG" --json | grep -q '"success": true'; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 3 ] || exit 1
  sleep 1
done
"$CLI" scope set "$PKG" android/0 --json | grep -q '"success": true' || exit 1
setprop sys.lightflow.guard 1 || exit 1
echo 'LightFlow system guard enabled; hook installation requires system_server restart/reboot after first install.'
