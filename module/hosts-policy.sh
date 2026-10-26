#!/system/bin/sh

# Compact only zero-address block entries. No DNS daemon, network probe or loop.
mode=${1:-apply}
state=${LIGHTFLOW_HOSTS_STATE:-/data/adb/lightflow/hosts}
target=${LIGHTFLOW_HOSTS_TARGET:-/system/etc/hosts}
source=${LIGHTFLOW_HOSTS_SOURCE:-/data/adb/modules/root-hosts-blocker/system/etc/hosts}

compact() {
  awk '
    function flush() { if (count) print "0.0.0.0 " names; count=0; names="" }
    $1 == "0.0.0.0" && NF >= 2 && !index($0,"#") {
      for (i=2;i<=NF;i++) {
        if (count && (count>=16 || length(names)+length($i)+9>900)) flush()
        names=names (count ? " " : "") $i; count++
      }
      next
    }
    { flush(); print }
    END { flush() }
  ' "$1" > "$2"
}

# A stable ordered digest catches dropped aliases, changed addresses and order.
mapping_digest() {
  map_tmp="$state/mapping.tmp.$$"
  awk '{ sub(/#.*/, ""); for (i=2;i<=NF;i++) print $1 "\t" $i }' "$1" > "$map_tmp" || return 1
  digest "$map_tmp"
  result=$?
  rm -f "$map_tmp"
  return "$result"
}

digest() {
  sum=$(sha256sum "$1") || return 1
  sum=${sum%% *}
  [ "${#sum}" -eq 64 ] || return 1
  case "$sum" in *[!0-9a-f]*) return 1 ;; esac
  printf '%s\n' "$sum"
}
identity() { stat -c '%d:%i' "$1" 2>/dev/null; }
remove_owned_mount() {
  [ -f "$state/compact" ] || return 0
  if [ "$(identity "$target")" = "$(identity "$state/compact")" ]; then
    umount "$target" || return 1
  fi
}

if [ "$mode" = format ]; then
  [ "$#" -eq 3 ] || exit 2
  compact "$2" "$3"
  exit $?
fi

case "$mode" in apply|restore|status) ;; *) exit 2 ;; esac
if [ "$mode" = status ]; then
  if [ -f "$state/compact" ] && [ "$(identity "$target")" = "$(identity "$state/compact")" ]; then
    printf 'Hosts formatting: compact overlay active (%s bytes)\n' "$(stat -c %s "$target")"
  else
    echo 'Hosts formatting: no verified LightFlow overlay'
  fi
  exit 0
fi

# Preserve another owner's replacement mount. Only remove our exact inode.
if [ "$mode" = restore ]; then
  [ -f "$state/compact" ] || exit 0
  remove_owned_mount || exit 1
  rm -f "$state/compact" "$state/source.sha256" "$state/mapping.sha256"
  rmdir "$state" 2>/dev/null || true
  exit 0
fi

case "$(getprop ro.product.model):$(getprop ro.build.version.sdk)" in
  RMX3741:35) ;;
  *) exit 0 ;;
esac
[ -f "$source" ] && [ ! -L "$source" ] && [ -f "$target" ] || exit 0

# An active overlay is immutable until removal/reboot. Never rewrite a mounted
# file or add a resident updater that races the original blocklist owner.
if [ -f "$state/compact" ] && [ "$(identity "$target")" = "$(identity "$state/compact")" ]; then
  echo 'Hosts formatting: existing overlay retained until next boot'
  exit 0
fi

# Do not mask a different live list, a stale deleted mount or an updater race.
live_identity=$(identity "$target") || exit 1
[ "$(stat -c %h "$target")" -gt 0 ] || {
  echo 'Hosts formatting: stale deleted mount needs repair; left unchanged' >&2
  exit 1
}
source_hash=$(digest "$source") || exit 1
[ "$source_hash" = "$(digest "$target")" ] || {
  echo 'Hosts formatting: source and active list differ; left unchanged' >&2
  exit 1
}
size=$(stat -c %s "$source") || exit 1
[ "$size" -ge 1048576 ] || exit 0

umask 077
mkdir -p "$state" || exit 1
tmp="$state/compact.tmp.$$"
trap 'rm -f "$tmp" "$state/mapping.tmp.$$"' EXIT HUP INT TERM
compact "$source" "$tmp" || exit 1
before=$(mapping_digest "$source") || exit 1
after=$(mapping_digest "$tmp") || exit 1
[ -n "$before" ] && [ "$before" = "$after" ] || exit 1
new_size=$(stat -c %s "$tmp") || exit 1
[ "$new_size" -lt "$size" ] || exit 0
[ "$source_hash" = "$(digest "$source")" ] &&
  [ "$source_hash" = "$(digest "$target")" ] &&
  [ "$live_identity" = "$(identity "$target")" ] || exit 1

# Mount helpers can fail/crash while consulting filtered /proc/mounts. The
# Actions-built helper uses direct syscalls and verifies inode + read-only state.
MODDIR=${0%/*}
binder=${LIGHTFLOW_HOSTS_BINDER:-$MODDIR/bin/hosts-bind}
[ -x "$binder" ] || exit 1
chmod 0644 "$tmp" && chown 0:0 "$tmp" &&
  chcon u:object_r:system_file:s0 "$tmp" || exit 1
mv "$tmp" "$state/compact" || exit 1
if ! "$binder" "$state/compact" "$target"; then
  remove_owned_mount || echo 'Hosts formatting: owned mount rollback failed; retry restore' >&2
  exit 1
fi
if [ "$(identity "$target")" != "$(identity "$state/compact")" ] ||
   [ "$(digest "$target")" != "$(digest "$state/compact")" ]; then
  remove_owned_mount || echo 'Hosts formatting: owned mount rollback failed; retry restore' >&2
  exit 1
fi
printf '%s\n' "$source_hash" > "$state/source.sha256"
printf '%s\n' "$before" > "$state/mapping.sha256"
printf 'Hosts formatting: %s -> %s bytes; every ordered address mapping retained\n' "$size" "$new_size"
