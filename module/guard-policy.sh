#!/system/bin/sh
MODDIR=${0%/*}
PKG=dev.lightflow.guard
CLI=/data/adb/lspd/cli
TIMEOUT=/system/bin/timeout
STATE=/data/adb/lightflow/guard-deployment
RECEIPT=$STATE/prepared
BOOT_FILE=/proc/sys/kernel/random/boot_id
temporary=
umask 077

cleanup() { [ -z "$temporary" ] || rm -rf "$temporary"; }
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
bounded() { "$TIMEOUT" -k 2 "$@"; }
fail() { echo "LightFlow guard: $*" >&2; return 1; }
valid_hash() {
  case "$1" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" = 64 ]
}
file_hash() (
  hash_output=$(sha256sum "$1") || exit 1
  hash_value=${hash_output%% *}
  valid_hash "$hash_value" || exit 1
  printf '%s\n' "$hash_value"
)
installed_apk_path() (
  path_output=$(bounded 15 pm path "$PKG") || exit 1
  installed_path=$(printf '%s\n' "$path_output" | sed -n 's/^package://p' | head -1)
  [ -n "$installed_path" ] || exit 1
  printf '%s\n' "$installed_path"
)
installed_hash() (
  installed_path=$(installed_apk_path) || exit 1
  file_hash "$installed_path"
)
valid_prepared_path() {
  case "$1" in
    *'/../'*|*'/./'*) return 1 ;;
    /data/app/*/dev.lightflow.guard-*/base.apk) [ ! -L "$1" ] ;;
    *) return 1 ;;
  esac
}
json_success() { grep -q '"success"[[:space:]]*:[[:space:]]*true'; }
module_enabled() {
  module_output=$(bounded 20 "$CLI" modules ls --json) || return 1
  printf '%s\n' "$module_output" | json_success || return 1
  # Check one owner-user object; another user's module cannot stand in for it.
  printf '%s\n' "$module_output" | awk 'BEGIN { RS="}" }
    /"PACKAGE"[[:space:]]*:[[:space:]]*"dev[.]lightflow[.]guard"/ &&
    /"STATUS"[[:space:]]*:[[:space:]]*"enabled"/ &&
    /"UID"[[:space:]]*:[[:space:]]*[0-9][0-9]?[0-9]?[0-9]?[0-9]?([[:space:]]|,|$)/ { found=1 }
    END { exit !found }'
}
scope_ready() {
  scope_output=$(bounded 20 "$CLI" scope ls "$PKG" --json) || return 1
  printf '%s\n' "$scope_output" | json_success || return 1
  # Vector 3080 queries the literal "system" database row for system_server.
  # "android" is an ordinary package scope, not an alias for this row.
  # Match package and user within one object.
  printf '%s\n' "$scope_output" | awk 'BEGIN { RS="}" }
    /"APP_PACKAGE"[[:space:]]*:[[:space:]]*"system"/ &&
    /"USER_ID"[[:space:]]*:[[:space:]]*0([[:space:]]|,|$)/ { found=1 }
    END { exit !found }'
}
runtime_diagnostic() { bounded 12 dumpsys -t 10 activity athena lightflow; }
runtime_ready() {
  diagnostic=$(runtime_diagnostic) || return 1
  printf '%s\n' "$diagnostic" | grep -q '^LightFlow System Guard ' || return 1
  printf '%s\n' "$diagnostic" | grep -q '^installedTargets=3 expected=3 (Athena=1 Atomic=2) diagnostics=true$' || return 1
  printf '%s\n' "$diagnostic" | grep -q '^policySelfCheck=PASS ' || return 1
}
supported() {
  [ "$(getprop ro.product.model):$(getprop ro.build.version.sdk)" = RMX3741:35 ] || {
    fail 'unsupported device; stock policy retained'; return 1;
  }
  [ -x "$TIMEOUT" ] && [ -x "$CLI" ] && [ -r "$MODDIR/guard.apk" ] || {
    fail 'timeout, Vector CLI, or packaged APK missing'; return 1;
  }
}

case "${1:-status}" in
  stop) setprop sys.lightflow.guard 0; exit $? ;;
  status)
    echo "System guard enabled: $(getprop sys.lightflow.guard)"
    bounded 15 pm path "$PKG" 2>/dev/null || true
    [ ! -x "$CLI" ] || bounded 20 "$CLI" scope ls "$PKG" --json
    if runtime_ready; then printf '%s\n' "$diagnostic"; else
      echo 'Runtime diagnostic unavailable or incomplete; registration does not prove hook execution.'
    fi
    exit 0 ;;
  prepare)
    supported || exit 1
    # Prepare during interactive installation, before system_server's next boot.
    bounded 15 pm list packages --user 0 "$PKG" >/dev/null || {
      fail 'Android package service unavailable; install from Magisk after Android starts'; exit 1;
    }
    preflight=$(bounded 20 "$CLI" modules ls --json) || {
      fail 'Vector unavailable; finish its setup before installing LightFlow'; exit 1;
    }
    printf '%s\n' "$preflight" | json_success || {
      fail 'Vector module inventory failed; preparation stopped'; exit 1;
    }
    packaged=$(file_hash "$MODDIR/guard.apk") || {
      fail 'cannot verify packaged APK'; exit 1;
    }
    boot_id=$(cat "$BOOT_FILE") || exit 1
    [ -n "$boot_id" ] || exit 1
    temporary=$(mktemp -d /data/local/tmp/lightflow-guard.XXXXXX) || exit 1
    chmod 0755 "$temporary" || exit 1
    cp "$MODDIR/guard.apk" "$temporary/guard.apk" || exit 1
    chmod 0644 "$temporary/guard.apk" || exit 1
    [ "$(file_hash "$temporary/guard.apk")" = "$packaged" ] || exit 1
    attempt=0
    unchanged_install=0
    while :; do
      installed=$(installed_hash) || installed=
      if [ "$installed" = "$packaged" ]; then
        [ "$attempt" -ne 0 ] || unchanged_install=1
        break
      fi
      attempt=$((attempt + 1))
      if [ "$attempt" -gt 3 ]; then
        fail 'APK preparation failed after 3 bounded attempts; no activation prepared'; exit 1
      fi
      if bounded 15 pm install -r "$temporary/guard.apk"; then
        installed=$(installed_hash) || installed=
        [ "$installed" != "$packaged" ] || break
        echo 'LightFlow guard: install reported success but installed bytes differ' >&2
      else
        install_status=$?
        echo "LightFlow guard: APK install attempt $attempt failed (status $install_status)" >&2
      fi
      [ "$attempt" -ge 3 ] || sleep 2
    done
    attempt=0
    while :; do
      attempt=$((attempt + 1))
      if enable_output=$(bounded 20 "$CLI" modules enable "$PKG" --json) &&
          printf '%s\n' "$enable_output" | json_success && module_enabled; then break; fi
      printf '%s\n' "$enable_output" >&2
      if [ "$attempt" -ge 3 ]; then
        fail 'APK verified, but Vector enable failed; rerun installation before reboot'; exit 1
      fi
      sleep 2
    done
    scope_result=$(bounded 20 "$CLI" scope set "$PKG" android/0 system/0 --json) || {
      fail 'APK verified, but Vector scope setup failed; rerun installation'; exit 1;
    }
    if ! printf '%s\n' "$scope_result" | json_success || ! scope_ready; then
      printf '%s\n' "$scope_result" >&2
      fail 'APK verified, but system/0 scope readback failed; no activation prepared'; exit 1
    fi
    # Save the verified immutable install path while PM is available. Boot
    # activation can hash that file without a package-service transaction.
    verified_path=$(installed_apk_path) || exit 1
    if ! valid_prepared_path "$verified_path" ||
        [ "$(file_hash "$verified_path")" != "$packaged" ]; then
      fail 'installed APK path or final hash changed; no activation prepared'; exit 1
    fi
    activation_boot=$boot_id
    previous_boot=$(sed -n '1p' "$RECEIPT" 2>/dev/null)
    previous_hash=$(sed -n '2p' "$RECEIPT" 2>/dev/null)
    # A script-only update may retain its proven boot boundary. Require the
    # exact same APK and the actual loaded hooks, never registration alone.
    if [ "$unchanged_install" = 1 ] && [ -n "$previous_boot" ] && [ "$previous_boot" != "$boot_id" ] &&
        [ "$previous_hash" = "$packaged" ] && runtime_ready; then
      activation_boot=$previous_boot
    fi
    mkdir -p "$STATE" || exit 1
    chmod 0700 "$STATE" || exit 1
    printf '%s\n%s\n%s\n' "$activation_boot" "$packaged" "$verified_path" > "$STATE/.prepared.$$" || exit 1
    chmod 0600 "$STATE/.prepared.$$" || exit 1
    mv "$STATE/.prepared.$$" "$RECEIPT" || exit 1
    if [ "$activation_boot" = "$boot_id" ]; then
      echo 'LightFlow guard APK and Vector scope verified before reboot; runtime activation pending.'
    else
      echo 'LightFlow unchanged APK and loaded hooks verified; previous boot preparation retained.'
    fi
    ;;
  start)
    setprop sys.lightflow.guard 0 || exit 1
    supported || exit 1
    sh "$MODDIR/memory-watchdog.sh" stop || exit 1
    packaged=$(file_hash "$MODDIR/guard.apk") || exit 1
    prepared_boot=$(sed -n '1p' "$RECEIPT" 2>/dev/null)
    prepared_hash=$(sed -n '2p' "$RECEIPT" 2>/dev/null)
    prepared_path=$(sed -n '3p' "$RECEIPT" 2>/dev/null)
    if [ -n "$prepared_path" ]; then
      valid_prepared_path "$prepared_path" || {
        fail 'invalid prepared APK path; stock policy retained'; exit 1;
      }
      installed=$(file_hash "$prepared_path") || {
        fail 'prepared APK file unavailable; stock policy retained'; exit 1;
      }
    else
      # Compatibility for a two-line receipt from older installers only.
      # New preparations never depend on PM responding during boot.
      attempt=0
      installed=
      while [ -z "$installed" ]; do
        installed=$(installed_hash) || installed=
        [ -z "$installed" ] || break
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 3 ]; then
          fail 'legacy package readback unavailable after 3 bounded attempts; stock policy retained'; exit 1
        fi
        sleep 2
      done
    fi
    boot_id=$(cat "$BOOT_FILE") || exit 1
    [ -n "$boot_id" ] || { fail 'boot identity unavailable; stock policy retained'; exit 1; }
    if ! valid_hash "$prepared_hash" || [ "$prepared_hash" != "$packaged" ] ||
        [ "$installed" != "$packaged" ] || [ -z "$prepared_boot" ]; then
      fail 'APK not prepared; reinstall LightFlow from Magisk before reboot. Stock policy retained.'; exit 1
    fi
    if [ "$boot_id" = "$prepared_boot" ]; then
      fail 'prepared this boot; reboot to load the verified APK. Stock policy retained.'; exit 1
    fi
    attempt=0
    while :; do
      if module_enabled && scope_ready && runtime_ready; then break; fi
      attempt=$((attempt + 1))
      if [ "$attempt" -ge 3 ]; then
        fail 'runtime hooks or Vector registration incomplete after 3 bounded attempts; stock policy retained'; exit 1
      fi
      sleep 2
    done
    setprop sys.lightflow.guard 1 || exit 1
    if [ "$(getprop sys.lightflow.guard)" != 1 ]; then
      setprop sys.lightflow.guard 0
      fail 'enable readback failed; stock policy retained'; exit 1
    fi
    echo 'LightFlow system guard enabled: verified loaded hooks; no shell cleanup timer.'
    ;;
  *) echo 'Usage: guard-policy.sh {prepare|start|stop|status}' >&2; exit 2 ;;
esac
