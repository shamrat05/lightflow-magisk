# Wi-Fi measurements and LightFlow 1.7.7

Measured on RMX3741 using the connected Wi-Fi interface. These are short,
active-screen diagnostic samples, not a throughput, idle-power, battery or
controlled before/after benchmark. Raw logs stay local and ignored.

## Link and policy

- 5 GHz link, frequency 5805 MHz, signal approximately -59 dBm.
- Negotiated link speed 864 Mbps. This is a PHY rate, not internet throughput.
- Driver power saving on; framework scan throttling enabled; verbose logging off.
- Interface MTU 1500. Current resolver mode opportunistic.

## ICMP sample

| Destination | Transmitted/received | Median RTT | RTT range |
| --- | --- | --- | --- |
| Local router | 21/20 | 13.55 ms | 5.14–18.6 ms |
| Cloudflare 1.1.1.1 | 20/20 | 16.55 ms | 5.11–23.8 ms |
| Google DNS 8.8.8.8 | 20/20 | 39.45 ms | 30.7–54.1 ms |

The Android ping run sent 21 requests to the router before collecting 20
replies. Its rounded summary reported 4% loss. That single missing ICMP reply
could be loss or router response behavior; no public-probe loss was observed.
It does not establish defective Wi-Fi. Public-host ICMP delay includes ISP
routing and server response policy, and is not a DNS-query measurement.

## Browsing and DNS

Android cached DNS lookups for tested Google, Cloudflare and GitHub hosts took
roughly 3–7 ms. Direct, proxy-bypassed, Wi-Fi-bound HTTPS requests succeeded.
Google first response was about 250–290 ms, Cloudflare about 104–105 ms, and
GitHub about 187–196 ms. Server work and TLS contribute to these timings.

One initial Facebook request spent 3038 ms resolving its hostname, then
returned HTTP 200. The resolver report contained a single timeout and a
3000 ms base timeout. That is consistent with a DNS retry, but does not prove
the cause of the user's social-app delay. Repeat Facebook lookups took
approximately 3–38 ms; Instagram and Reddit requests also returned HTTP 200.
No continuing DNS failure or measured advantage from another resolver was
established. DNS, VPN, firewall, MTU and TCP settings were therefore preserved.

The official bKash app already had `speed-profile` code. It is now included in
the existing optional action and status output; no forced recompilation was
needed. Android's native job continues to select eligible apps at idle charging.

## What changed

- Added manual bounded Wi-Fi diagnostics and compilation reporting for bKash.
- Added bKash to the existing heat-guarded targeted ART action.
- Removed the unused modern Android Wi-Fi sleep-setting write.
- Added no background network probe, polling job, Wi-Fi lock or forced boost.

## Sources and limits

[Android Wi-Fi low-latency mode](https://source.android.com/docs/core/connect/wifi-low-latency)
explicitly disables radio power saving. Forcing it would contradict the battery
requirement. [Wi-Fi scan limits](https://developer.android.com/develop/connectivity/wifi/wifi-scan)
protect network performance and battery life; throttling was already enabled.
[WIFI_SLEEP_POLICY](https://developer.android.com/reference/android/provider/Settings.Global#WIFI_SLEEP_POLICY)
is unused by the platform from API 30.

These measurements do not prove a speed gain. Browser rendering, app work,
server delay, radio conditions and router/WAN queues can all affect perceived
speed. No full-speed saturation test, router configuration, screen-off test,
long loss study or battery comparison was performed.

## Release validation

The complete policy suite passed 33 tests. The final summary-format correction
then passed all seven Wi-Fi tests; shell syntax checks passed for every module
script. Source review found no remaining blockers. All 18 installed payload
files match local source and the release ZIP by content; ZIP CRC checks pass.

The installed manual probe returned 12/12 router replies and 12/12 Cloudflare
replies, with mean RTT 14.929 ms and 17.391 ms respectively. Status output hides
SSID, MAC and private gateway addresses and displays one value per metric.
Driver power saving remained on and bKash remained speed-profile. An installed
module backup and root-only rollback script were retained privately. Neither
full reboot persistence nor the full live rollback was exercised in this update.
