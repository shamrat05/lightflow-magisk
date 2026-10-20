#!/system/bin/sh

# Magisk's generic module extraction can leave files at 0644 on this ROM even
# when the ZIP contains Unix executable bits. Restore the modes required by
# the boot scripts during installation; this is reversible with the module.
if [ "${BOOTMODE:-false}" != true ]; then
  abort 'Install LightFlow from Magisk after Android and Vector are running; recovery cannot prepare the injected guard.'
fi
for required in service.sh action.sh uninstall.sh guard-policy.sh guard.apk memory-pressure-policy.sh memory-watchdog.sh; do
  if [ ! -s "$MODPATH/$required" ]; then
    abort "LightFlow archive incomplete: missing $required"
  fi
done
if command -v set_perm >/dev/null 2>&1; then
  for script in "$MODPATH"/*.sh; do
    [ -f "$script" ] || continue
    set_perm "$script" 0 0 0755
  done
  set_perm "$MODPATH/module.prop" 0 0 0644
  for config in "$MODPATH"/*.conf; do
    [ -f "$config" ] || continue
    set_perm "$config" 0 0 0644
  done
else
  chmod 0755 "$MODPATH"/*.sh 2>/dev/null || true
  chmod 0644 "$MODPATH/module.prop" "$MODPATH"/*.conf 2>/dev/null || true
fi

# Prepare the APK before the reboot that loads it into system_server.
if ! sh "$MODPATH/guard-policy.sh" prepare; then
  abort 'Guard preparation failed. A verified helper APK may already be installed; Android data was preserved. Fix the reported PM/Vector error and retry.'
fi
