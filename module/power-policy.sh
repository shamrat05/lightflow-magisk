#!/system/bin/sh

# Never change a setting unless its original state was read successfully.
state=${LIGHTFLOW_POWER_STATE:-/data/adb/lightflow/power}
if [ "$1" = restore-legacy-trigger ]; then
  legacy=$state/automatic_power_save_mode
  [ -f "$legacy" ] || exit 0
  read -r saved < "$legacy" || exit 1
  case "$saved" in 0|1|null) ;; *) exit 1 ;; esac
  actual=$(settings get global automatic_power_save_mode 2>/dev/null) || exit 1
  case "$actual" in
    1)
      if [ "$saved" = null ]; then
        settings delete global automatic_power_save_mode >/dev/null 2>&1 || exit 1
      else
        settings put global automatic_power_save_mode "$saved" >/dev/null 2>&1 || exit 1
      fi
      ;;
    0|null) ;; # Preserve a later user/vendor choice.
    *) exit 1 ;;
  esac
  rm -f "$legacy"
  exit 0
fi
mkdir -p "$state" || exit 1

valid_value() {
  case "$1:$2" in
    cached_apps_freezer:enabled|cached_apps_freezer:disabled|cached_apps_freezer:null) return 0 ;;
    app_standby_enabled:0|app_standby_enabled:1|app_standby_enabled:null) return 0 ;;
    dynamic_power_savings_enabled:0|dynamic_power_savings_enabled:1|dynamic_power_savings_enabled:null) return 0 ;;
    adaptive_power_saver:true|adaptive_power_saver:false) return 0 ;;
    *) return 1 ;;
  esac
}
if [ "$1" = restore ]; then
  restore_failed=0
  for key in cached_apps_freezer app_standby_enabled dynamic_power_savings_enabled adaptive_power_saver; do
    file=$state/$key
    [ -f "$file" ] || continue
    if ! read -r value < "$file" || ! valid_value "$key" "$value"; then
      restore_failed=1
      continue
    fi
    if [ "$key" = adaptive_power_saver ]; then
      cmd power set-adaptive-power-saver-enabled "$value" >/dev/null 2>&1
    elif [ "$value" = null ]; then
      settings delete global "$key" >/dev/null 2>&1
    else
      settings put global "$key" "$value" >/dev/null 2>&1
    fi
    if [ $? -eq 0 ]; then
      rm -f "$file"
    else
      restore_failed=1
    fi
  done
  exit "$restore_failed"
fi
save_setting() {
  key=$1
  if [ -f "$state/$key" ]; then
    read -r value < "$state/$key" || return 1
  else
    value=$(settings get global "$key" 2>/dev/null) || return 1
  fi
  valid_value "$key" "$value" || return 1
  [ -f "$state/$key" ] || printf '%s\n' "$value" > "$state/$key" || return 1
}

activity_settings=$(dumpsys activity settings 2>/dev/null)
if [ $? -eq 0 ] && printf '%s\n' "$activity_settings" | grep -q 'use_freezer=true'; then
  if save_setting cached_apps_freezer; then
    settings put global cached_apps_freezer enabled >/dev/null 2>&1
  else
    echo 'LightFlow: freezer state could not be backed up; left unchanged.'
  fi
fi
for key in app_standby_enabled dynamic_power_savings_enabled; do
  if save_setting "$key"; then
    settings put global "$key" 1 >/dev/null 2>&1
  else
    echo "LightFlow: $key state could not be backed up; left unchanged."
  fi
done

adaptive_file=$state/adaptive_power_saver
if [ -f "$adaptive_file" ]; then
  read -r adaptive < "$adaptive_file" || adaptive=unknown
else
  power=$(dumpsys power 2>/dev/null)
  if [ $? -ne 0 ]; then
    adaptive=unknown
  elif printf '%s\n' "$power" | grep -q 'adaptive=true'; then
    adaptive=true
  elif printf '%s\n' "$power" | grep -q 'adaptive=false'; then
    adaptive=false
  else
    adaptive=unknown
  fi
fi
if valid_value adaptive_power_saver "$adaptive"; then
  if [ -f "$adaptive_file" ] || printf '%s\n' "$adaptive" > "$adaptive_file"; then
    cmd power set-adaptive-power-saver-enabled true >/dev/null 2>&1
  fi
else
  echo 'LightFlow: adaptive saver state could not be backed up; left unchanged.'
fi
# automatic_power_save_mode belongs to the user's/vendor's trigger selection.
# Adaptive power can operate without overwriting that selection.
