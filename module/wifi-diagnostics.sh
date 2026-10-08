#!/system/bin/sh

# Manual diagnostics only. Status sends no probes; probe is finite and opt-in.
if [ "$(id -u)" = 0 ]; then
  PATH=/system/bin:/system/xbin
  export PATH
fi
mode=${1:-status}
case "$mode" in status|probe) ;; *) echo 'Usage: wifi-diagnostics.sh [status|probe]' >&2; exit 2 ;; esac
status=$(cmd wifi status 2>/dev/null)
if [ $? -eq 0 ]; then
  printf '%s\n' "$status" | awk '
    function emit(key, text) { if (!seen[key]++) print text }
    /^Wifi is (enabled|disabled)$/ { emit("state", $0) }
    /^Wifi is connected to / { emit("connection", "Wi-Fi connected") }
    /RSSI: / {
      value=$0; sub(/.*RSSI: /,"",value); sub(/,.*/,"",value)
      if (value ~ /^-?[0-9]+$/) emit("signal", "Signal: " value " dBm")
    }
    /, Link speed: / {
      value=$0; sub(/.*, Link speed: /,"",value); sub(/,.*/,"",value)
      if (value ~ /^[0-9]+Mbps$/) { sub(/Mbps$/,"",value); emit("rate", "Negotiated link: " value " Mbps (not download throughput)") }
    }
    /Frequency: / {
      value=$0; sub(/.*Frequency: /,"",value); sub(/,.*/,"",value)
      if (value ~ /^[0-9]+MHz$/) { sub(/MHz$/,"",value); emit("frequency", "Frequency: " value " MHz") }
    }'

else
  echo 'Wi-Fi link status unavailable.'
fi
verbose=$(cmd wifi is-verbose-logging 2>/dev/null)
case "$verbose" in enabled|disabled) printf 'Wi-Fi verbose logging: %s\n' "$verbose" ;; *) echo 'Wi-Fi verbose logging: unavailable' ;; esac
[ "$mode" = probe ] || exit 0

routes=$(ip -4 route show table all 2>/dev/null) || {
  echo 'Cannot read Wi-Fi routes. Run this diagnostic through su.' >&2
  exit 1
}
route=$(printf '%s\n' "$routes" | awk '$1 == "default" && $2 == "via" && $4 == "dev" && $5 ~ /^wlan[0-9]+$/ {print $3, $5; exit}')
[ -n "$route" ] || {
  echo 'No IPv4 Wi-Fi gateway. Disconnected or IPv6-only links skip IPv4 probes.'
  exit 0
}
read -r gateway interface <<EOF
$route
EOF
case "$interface" in wlan[0-9]*) ;; *) exit 1 ;; esac
index=${interface#wlan}
case "$index" in ''|*[!0-9]*) exit 1 ;; esac
case "$gateway" in ''|*[!0-9.]*|.*|*.|*..*) exit 1 ;; esac
previous_ifs=$IFS
IFS=.
set -- $gateway
IFS=$previous_ifs
[ "$#" = 4 ] || exit 1
for octet do
  case "$octet" in ''|*[!0-9]*) exit 1 ;; esac
  [ "${#octet}" -le 3 ] && [ "$octet" -le 255 ] || exit 1
done

probe() {
  label=$1 target=$2
  printf '%s, interface %s, at most 15 seconds:\n' "$label" "$interface"
  # Capture before printing so SSID, MAC and private gateway are never exposed.
  output=$(timeout 15 ping -n -I "$interface" -c 12 -i 1 -W 2 "$target" 2>&1)
  result=$?
  summary=$(printf '%s\n' "$output" | sed -n '/^[0-9][0-9]* packets transmitted,/p; /^rtt /p; /^round-trip /p')
  if [ -n "$summary" ]; then
    printf '%s\n' "$summary"
  else
    echo 'No usable ping summary. The route may be unavailable or ICMP blocked.'
  fi
  return "$result"
}
failed=0
probe 'Router' "$gateway" || failed=1
probe 'Internet (Cloudflare 1.1.1.1)' 1.1.1.1 || failed=1
echo 'ICMP can be blocked or rate limited. These samples do not measure download speed or battery gains.'
exit "$failed"
