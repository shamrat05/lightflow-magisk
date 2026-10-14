#!/system/bin/sh

# Magisk's generic module extraction can leave files at 0644 on this ROM even
# when the ZIP contains Unix executable bits. Restore the modes required by
# the boot scripts during installation; this is reversible with the module.
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
