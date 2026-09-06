#!/system/bin/sh

target=/data/data/com.termux/files/usr/bin/agy
state=/data/adb/lightflow
original=$state/agy-launcher.original
managed=$state/agy-launcher.managed

if [ "$1" = uninstall ]; then
  if [ -f "$original" ] && [ -f "$managed" ] && cmp -s "$target" "$managed"; then
    cp -p "$original" "$target" || exit 1
  fi
  exit 0
fi

[ -f "$target" ] && [ ! -L "$target" ] || exit 0
if [ -f "$managed" ] && cmp -s "$target" "$managed"; then
  exit 0
fi

# Only patch the launcher inspected and tested for this integration. Never
# replace an unknown launcher or overwrite a user's subsequent edits.
digest=$(sha256sum "$target")
case "$digest" in
  885f6c27f58b19ce4ece663fb5d0dcb4073d1f3085302cc302e54cfe54fc9c7d\ *) ;;
  *) echo 'LightFlow: agy launcher differs; integration skipped.'; exit 0 ;;
esac
mkdir -p "$state" || exit 1
cp -p "$target" "$original" || exit 1
sed '/^run_agy "\$@"$/i\
# LightFlow: apply only while the module is enabled.\
if [ -f /data/adb/modules/lightflow/agy-policy.sh ] && [ ! -e /data/adb/modules/lightflow/disable ] && [ ! -e /data/adb/modules/lightflow/remove ]; then\
    /system/bin/sh /data/adb/modules/lightflow/agy-policy.sh "$$"\
fi\
' "$original" > "$managed" || exit 1
/data/data/com.termux/files/usr/bin/bash -n "$managed" || exit 1
cp "$managed" "$target"
