#!/system/bin/sh

# Reduce speculative file reads on this device's userdata volume only.
# Resolve it each time: device-mapper numbers can change between boots.
STATE=/data/adb/lightflow/io
TARGET=128
[ "$(getprop ro.product.model)" = RMX3741 ] || exit 0
device=$(awk '$2 == "/data" {print $1; exit}' /proc/mounts)
block=${device##*/}
case "$block" in dm-[0-9]*) ;; *) exit 0 ;; esac
sys=/sys/class/block/$block
[ "$(cat "$sys/dm/name" 2>/dev/null)" = userdata ] || exit 0
node=$sys/queue/read_ahead_kb
[ -r "$node" ] && [ -w "$node" ] || exit 0
current=$(cat "$node")
case "$current" in ''|*[!0-9]*) exit 1 ;; esac
saved=$STATE/read_ahead_kb

case "${1:-apply}" in
  status)
    printf 'Userdata read-ahead: %s KiB (cap %s KiB)\n' "$current" "$TARGET"
    ;;
  apply)
    # Leave already-small vendor/user settings alone.
    [ "$current" -gt "$TARGET" ] || exit 0
    mkdir -p "$STATE" || exit 1
    if [ ! -f "$saved" ]; then
      printf '%s\n' "$current" > "$saved" || exit 1
    fi
    printf '%s\n' "$TARGET" > "$node" || exit 1
    [ "$(cat "$node")" = "$TARGET" ] || exit 1
    printf 'Userdata read-ahead verified: %s -> %s KiB\n' "$current" "$TARGET"
    ;;
  restore)
    [ -f "$saved" ] || exit 0
    original=$(cat "$saved")
    case "$original" in ''|*[!0-9]*) exit 1 ;; esac
    # Preserve subsequent user/vendor changes to this setting.
    if [ "$current" = "$TARGET" ]; then
      printf '%s\n' "$original" > "$node" || exit 1
      [ "$(cat "$node")" = "$original" ] || exit 1
    fi
    rm -f "$saved"
    rmdir "$STATE" 2>/dev/null
    ;;
  *) exit 2 ;;
esac
