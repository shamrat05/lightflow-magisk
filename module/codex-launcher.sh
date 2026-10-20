#!/system/bin/sh

MODDIR=${0%/*}
if [ "$(id -u)" = 0 ]; then
  PATH=/system/bin:/system/xbin:/debug_ramdisk:/sbin
  export PATH
fi
bin_dir=${LIGHTFLOW_CODEX_BIN_DIR:-/data/data/com.termux/files/usr/bin}
target=${LIGHTFLOW_CODEX_TARGET:-$bin_dir/codex}
state=${LIGHTFLOW_ROOT_STATE:-/data/adb/lightflow}
user_state=${LIGHTFLOW_CODEX_STATE:-/data/data/com.termux/files/home/.lightflow}
boot_file=${LIGHTFLOW_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}
action=${1:-install}
namespace=codex-launcher
[ ! -L "$state" ] || exit 1
# The active Termux wrapper executes codex-core. npm may replace codex with a
# symlink to another CLI; never follow or rewrite that separate launcher.
core=$bin_dir/codex-core
if [ -z "${LIGHTFLOW_CODEX_TARGET:-}" ]; then
  if [ -e "$state/codex-core-launcher.original" ] || [ -L "$state/codex-core-launcher.original" ] || \
     [ -e "$state/codex-core-launcher.managed" ] || [ -L "$state/codex-core-launcher.managed" ]; then
    target=$core
  elif [ ! -L "$core" ] && [ -f "$core" ]; then
    core_digest=$(sha256sum "$core") || exit 1
    case "$core_digest" in
      ecacc9dee620711203c461b926f2cb3bfda63114bf08076752ca9fcb39707217\ *) target=$core ;;
    esac
  fi
fi
[ "$target" != "$core" ] || namespace=codex-core-launcher
# Backups from the former codex target must never become codex-core's source.
original=$state/$namespace.original
managed=$state/$namespace.managed
helper=$user_state/codex-policy.sh
helper_managed=$state/codex-policy.managed
[ ! -L "$state" ] && [ ! -L "$original" ] && [ ! -L "$managed" ] && [ ! -L "$helper_managed" ] && [ ! -L "$target" ] && [ ! -L "$user_state" ] && [ ! -L "$helper" ] || exit 1
[ -f "$target" ] || exit 0
known_launcher() {
  digest=$(sha256sum "$1") || return 1
  case "$namespace:$digest" in
    codex-launcher:5d196fa3898c12cbcccf10337c08f0219ad41197f4af49d13127893c0cfa1216\ *|\
    codex-core-launcher:ecacc9dee620711203c461b926f2cb3bfda63114bf08076752ca9fcb39707217\ *) return 0 ;;
  esac
  return 1
}
render_managed() {
  awk -v suffix="$1" '/^exec "\$PREFIX\/bin\/node" / {
    print "# LightFlow: user-space scheduling, only for an enabled-module boot."
    print "if [ -r /data/data/com.termux/files/home/.lightflow/codex-policy.sh ]; then"
    print "  \"$PREFIX/bin/sh\" /data/data/com.termux/files/home/.lightflow/codex-policy.sh \"$$\"" suffix
    print "fi"
  } { print }' "$original"
}
matches_template() {
  [ -f "$original" ] || return 1
  # Both verified originals and rendered templates have one trailing newline.
  rendered=$(render_managed "$2") || return 1
  expected_digest=$(printf '%s\n' "$rendered" | sha256sum) || return 1
  actual_digest=$(sha256sum "$1") || return 1
  [ "${expected_digest%% *}" = "${actual_digest%% *}" ]
}
[ ! -f "$original" ] || known_launcher "$original" || exit 1
if [ "$action" = uninstall ]; then
  [ -f "$original" ] && [ -f "$managed" ] || exit 0
elif [ -f "$managed" ] && cmp -s "$target" "$managed"; then
  :
elif known_launcher "$target" || matches_template "$target" ' || :' || matches_template "$target" ''; then
  :
else
  echo 'LightFlow: Codex launcher differs; integration skipped.'
  exit 0
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
render_managed ' || :' > "$payload/managed-backup" || exit 1
render_managed '' > "$payload/previous-managed" || exit 1
/system/bin/sh -n "$payload/managed-backup" || exit 1
if [ -f "$managed" ]; then
  if ! cmp -s "$managed" "$payload/managed-backup"; then
    # Accept only our exact earlier template, reconstructed from the verified
    # same-target original. Never accept arbitrary edited managed snapshots.
    cmp -s "$managed" "$payload/previous-managed" || exit 1
  fi
else
  cp "$payload/managed-backup" "$managed" || exit 1
fi
cp "$original" "$payload/original" || exit 1
if [ "$action" = uninstall ]; then
  if cmp -s "$target" "$payload/managed-backup"; then
    cp "$payload/managed-backup" "$payload/managed" || exit 1
  elif cmp -s "$target" "$payload/previous-managed"; then
    cp "$payload/previous-managed" "$payload/managed" || exit 1
  else
    cp "$managed" "$payload/managed" || exit 1
  fi
else
  # The capability-dropped installer must recognize an existing old wrapper
  # before atomically replacing it with the new fail-open template.
  if cmp -s "$target" "$payload/managed-backup"; then
    cp "$payload/managed-backup" "$payload/original" || exit 1
  elif cmp -s "$target" "$payload/previous-managed"; then
    cp "$payload/previous-managed" "$payload/original" || exit 1
  fi
  cp "$payload/managed-backup" "$payload/managed" || exit 1
fi
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
  mv -f "$payload/managed-backup" "$managed" || exit 1
  cp "$MODDIR/codex-policy.sh" "$payload/helper-backup" || exit 1
  mv -f "$payload/helper-backup" "$helper_managed" || exit 1
  echo 'LightFlow: Codex launch scheduling ready (nice 5, available efficiency CPUs).'
fi
