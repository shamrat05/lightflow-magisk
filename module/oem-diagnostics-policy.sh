#!/system/bin/sh

# Audited optional OStats collectors on RMX3741_15.0.0.1820(EX01).
# Their init .rc files expose these switches; no thermal control is stopped.
STATE=/data/adb/lightflow/oem-diagnostics
SERVICES='ostatsd ostats_tpd ostats_pullerd'
mode=${1:-apply}
case "$mode" in apply|restore|status) ;; *) exit 2 ;; esac
umask 077

if [ "$mode" = apply ]; then
  identity="$(getprop ro.product.model):$(getprop ro.build.version.sdk):$(getprop ro.build.version.incremental)"
  if [ "$identity" != 'RMX3741:35:T.R4T2.231124a_d5daf' ]; then
    echo 'OEM diagnostic collectors: firmware not audited; no changes'
    exit 0
  fi
fi

wait_service() {
  attempts=0
  while [ "$attempts" -lt 10 ]; do
    [ "$(getprop "init.svc.$1")" = "$2" ] && return 0
    attempts=$((attempts + 1))
    sleep 0.2
  done
  return 1
}

failed=0
for service in $SERVICES; do
  property=persist.sys.$service.enable
  saved=$STATE/$service
  current=$(getprop "$property") || { failed=1; continue; }
  case "$current" in 0|1) ;; *)
    echo "$service: unrecognized enable value; unchanged"
    failed=1
    continue
    ;;
  esac
  case "$mode" in
    status)
      printf '%s: enable=%s service=%s managed=%s\n' "$service" "$current" \
        "$(getprop "init.svc.$service")" "$([ -f "$saved" ] && echo yes || echo no)"
      ;;
    apply)
      if [ "$current" = 0 ]; then
        # Do not take ownership of a pre-existing user/OEM disabled setting.
        if [ -f "$saved" ]; then
          [ "$(cat "$saved")" = 1 ] && wait_service "$service" stopped || failed=1
        fi
        continue
      fi
      if [ "$(getprop "init.svc.$service")" != running ]; then
        echo "$service: not running; unchanged"
        continue
      fi
      mkdir -p "$STATE" || { failed=1; continue; }
      if [ -f "$saved" ]; then
        [ "$(cat "$saved")" = 1 ] || { failed=1; continue; }
      else
        temporary=$saved.tmp.$$
        if ! printf '1\n' > "$temporary" || ! mv "$temporary" "$saved"; then
          rm -f "$temporary"
          failed=1
          continue
        fi
      fi
      if setprop "$property" 0 && [ "$(getprop "$property")" = 0 ] && \
          wait_service "$service" stopped; then
        echo "$service: optional collection disabled and stopped"
      else
        # Keep the recovery receipt until both property and service recover.
        if setprop "$property" 1 && [ "$(getprop "$property")" = 1 ] && \
            wait_service "$service" running; then
          rm -f "$saved"
        fi
        echo "$service: disable not verified; restoration attempted"
        failed=1
      fi
      ;;
    restore)
      [ -f "$saved" ] || continue
      [ "$(cat "$saved")" = 1 ] || { failed=1; continue; }
      if [ "$current" = 0 ]; then
        if ! setprop "$property" 1 || [ "$(getprop "$property")" != 1 ] || \
            ! wait_service "$service" running; then
          failed=1
          continue
        fi
      fi
      # A later user/OEM decision to enable the collector is preserved.
      rm -f "$saved" || failed=1
      ;;
  esac
done
[ "$mode" != restore ] || rmdir "$STATE" 2>/dev/null || true
exit "$failed"
