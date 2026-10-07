#!/system/bin/sh

MODDIR=${0%/*}
if [ "$(id -u)" = 0 ]; then
  PATH=/system/bin:/system/xbin:/debug_ramdisk:/sbin
  export PATH
fi
target=${LIGHTFLOW_CODEX_TARGET:-/data/data/com.termux/files/usr/bin/codex}
state=${LIGHTFLOW_ROOT_STATE:-/data/adb/lightflow}
user_state=${LIGHTFLOW_CODEX_STATE:-/data/data/com.termux/files/home/.lightflow}
boot_file=${LIGHTFLOW_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}
original=$state/codex-launcher.original
managed=$state/codex-launcher.managed
helper=$user_state/codex-policy.sh
helper_managed=$state/codex-policy.managed
[ ! -L "$state" ] && [ ! -L "$original" ] && [ ! -L "$managed" ] && [ ! -L "$helper_managed" ] && [ ! -L "$target" ] && [ ! -L "$user_state" ] && [ ! -L "$helper" ] || exit 1
[ -f "$target" ] || exit 0
action=${1:-install}
if [ "$action" = uninstall ]; then
  [ -f "$original" ] && [ -f "$managed" ] || exit 0
elif [ -f "$managed" ] && cmp -s "$target" "$managed"; then
  :
else
  digest=$(sha256sum "$target")
  case "$digest" in
    5d196fa3898c12cbcccf10337c08f0219ad41197f4af49d13127893c0cfa1216\ *) ;;
    *) echo 'LightFlow: Codex launcher differs; integration skipped.'; exit 0 ;;
  esac
fi
if [ "$action" != uninstall ] && [ -e "$helper" ] && { [ ! -f "$helper_managed" ] || ! cmp -s "$helper" "$helper_managed"; } && ! cmp -s "$helper" "$MODDIR/codex-policy.sh"; then
  echo 'LightFlow: preserved edited Codex policy helper.'
  exit 0
fi
owner_uid=$(stat -c %u "$target") || exit 1
app_uid=$(stat -c %u /data/data/com.termux/files/home) || exit 1
[ "$owner_uid" -ge 10000 ] && [ "$owner_uid" = "$app_uid" ] || exit 1
owner_gid=$(stat -c %g "$target") || exit 1
mode=$(stat -c %a "$target") || exit 1
label=$(ls -Zd "$target") || exit 1
context=${label%% *}
case "$context" in u:*:*:*) ;; *) exit 1 ;; esac
mkdir -p "$state" || exit 1
if [ "$(id -u)" = 0 ]; then
  # /data/adb remains private. This root-owned directory is traversable by the
  # capability-dropped child; /data/local/tmp is not writable by the app UID.
  payload=$(mktemp -d /data/local/tmp/lightflow-codex.XXXXXX) || exit 1
else
  payload=$(mktemp -d "$state/codex-install.XXXXXX") || exit 1
fi
trap 'rm -rf "$payload"' EXIT
trap 'exit 1' HUP INT TERM
if [ ! -f "$original" ]; then
  cp -p "$target" "$payload/original-backup" || exit 1
  if [ "$(id -u)" = 0 ]; then
    chown 0:0 "$payload/original-backup" || exit 1
    chmod 600 "$payload/original-backup" || exit 1
  fi
  mv -f "$payload/original-backup" "$original" || exit 1
fi
if [ ! -f "$managed" ]; then
  awk '/^exec "\$PREFIX\/bin\/node" / {
    print "# LightFlow: user-space scheduling, only for an enabled-module boot."
    print "if [ -r /data/data/com.termux/files/home/.lightflow/codex-policy.sh ]; then"
    print "  \"$PREFIX/bin/sh\" /data/data/com.termux/files/home/.lightflow/codex-policy.sh \"$$\""
    print "fi"
  } { print }' "$original" > "$payload/managed-backup" || exit 1
  /system/bin/sh -n "$payload/managed-backup" || exit 1
  mv -f "$payload/managed-backup" "$managed" || exit 1
fi
cp "$original" "$payload/original" || exit 1
cp "$managed" "$payload/managed" || exit 1
cp "$MODDIR/codex-policy.sh" "$payload/helper" || exit 1
cp "$MODDIR/codex-user-install.sh" "$payload/installer" || exit 1
if cmp -s "$helper" "$MODDIR/codex-policy.sh"; then
  cp "$MODDIR/codex-policy.sh" "$payload/previous-helper" || exit 1
elif [ -f "$helper_managed" ]; then
  cp "$helper_managed" "$payload/previous-helper" || exit 1
fi
read -r boot_id < "$boot_file" || exit 1
[ -n "$boot_id" ] || exit 1
printf '%s\n' "$boot_id" > "$payload/boot" || exit 1
chmod 755 "$payload" || exit 1
chmod 644 "$payload"/* || exit 1
# Root stages only inside its protected state directory. App-path operations
# execute as the app UID with every Linux capability dropped.
quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
if [ "$(id -u)" = 0 ]; then
  PATH=/system/bin:/system/xbin:/debug_ramdisk:/sbin
  export PATH
  su_bin=
  for candidate in /debug_ramdisk/su /sbin/su; do
    [ ! -x "$candidate" ] || { su_bin=$candidate; break; }
  done
  [ -n "$su_bin" ] || exit 1
  command="/system/bin/sh $(quote "$payload/installer") $(quote "$action") $(quote "$payload") $(quote "$target") $(quote "$user_state") $(quote "$mode") $(quote "$context") $(quote "$owner_uid")"
  "$su_bin" -d -g "$owner_gid" -s /system/bin/sh "$owner_uid" -c "$command" || exit 1
else
  /system/bin/sh "$payload/installer" "$action" "$payload" "$target" "$user_state" "$mode" "$context" "$owner_uid" || exit 1
fi
if [ "$action" != uninstall ]; then
  cp "$MODDIR/codex-policy.sh" "$payload/helper-backup" || exit 1
  mv -f "$payload/helper-backup" "$helper_managed" || exit 1
  echo 'LightFlow: Codex launch scheduling ready (nice 5, available efficiency CPUs).'
fi
