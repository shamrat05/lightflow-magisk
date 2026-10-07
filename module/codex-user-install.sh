#!/system/bin/sh
# All app-directory writes run as Termux, with no Linux capabilities.
action=$1
payload=$2
target=$3
user_state=$4
mode=$5
context=$6
expected_uid=$7
[ "$expected_uid" -ge 10000 ] && [ "$(id -u)" = "$expected_uid" ] || exit 1
helper=$user_state/codex-policy.sh
marker=$user_state/codex-boot-id
[ ! -L "$target" ] && [ ! -L "$user_state" ] && [ ! -L "$helper" ] && [ ! -L "$marker" ] || exit 1
target_stage=
helper_stage=
marker_stage=
cleanup() {
  for staged in "$target_stage" "$helper_stage" "$marker_stage"; do
    [ -z "$staged" ] || rm -f "$staged"
  done
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
keep_context() {
  label=$(ls -Zd "$1") || return 1
  [ "${label%% *}" = "$context" ] || chcon "$context" "$1"
}
if [ "$action" = uninstall ]; then
  if cmp -s "$target" "$payload/managed"; then
    target_stage=$(mktemp "$target.lightflow.XXXXXX") || exit 1
    cat "$payload/original" > "$target_stage" || exit 1
    chmod "$mode" "$target_stage" || exit 1
    keep_context "$target_stage" || exit 1
    /system/bin/sh -n "$target_stage" || exit 1
    [ ! -L "$target" ] && cmp -s "$target" "$payload/managed" || exit 1
    mv -f "$target_stage" "$target" || exit 1
    target_stage=
  fi
  if [ -f "$payload/previous-helper" ] && cmp -s "$helper" "$payload/previous-helper"; then
    rm -f "$helper"
  fi
  rm -f "$marker"
  rmdir "$user_state" 2>/dev/null
  exit 0
fi
mkdir -p "$user_state" || exit 1
chmod 700 "$user_state" || exit 1
keep_context "$user_state" || exit 1
if [ -e "$helper" ] && ! cmp -s "$helper" "$payload/previous-helper"; then
  echo 'LightFlow: preserved edited Codex policy helper.'
  exit 1
fi
target_stage=$(mktemp "$target.lightflow.XXXXXX") || exit 1
helper_stage=$(mktemp "$user_state/policy.XXXXXX") || exit 1
marker_stage=$(mktemp "$user_state/boot.XXXXXX") || exit 1
cat "$payload/managed" > "$target_stage" || exit 1
cat "$payload/helper" > "$helper_stage" || exit 1
cat "$payload/boot" > "$marker_stage" || exit 1
chmod "$mode" "$target_stage" || exit 1
chmod 600 "$helper_stage" "$marker_stage" || exit 1
for staged in "$target_stage" "$helper_stage" "$marker_stage"; do
  keep_context "$staged" || exit 1
done
/system/bin/sh -n "$target_stage" || exit 1
[ ! -L "$target" ] && [ ! -L "$helper" ] && [ ! -L "$marker" ] || exit 1
cmp -s "$target" "$payload/original" || cmp -s "$target" "$payload/managed" || exit 1
if [ -e "$helper" ]; then
  cmp -s "$helper" "$payload/previous-helper" || exit 1
fi
mv -f "$helper_stage" "$helper" || exit 1
helper_stage=
mv -f "$marker_stage" "$marker" || exit 1
marker_stage=
mv -f "$target_stage" "$target" || exit 1
target_stage=
