# LightFlow Magisk Module

LightFlow is a device-specific Android performance project for rooted RMX3741
running Android 15. Results must be measured on the device; more free RAM alone
does not prove better performance or battery life.

## Latest release: 1.9.10

## Release candidate: 1.10.0-rc.6 system guard

RC6 removes the verified boot activation dependency on `pm path`. Interactive
preparation records a third receipt line containing the actual verified APK
path. New boot activation validates that path and hashes the file directly;
missing, redirected or changed files retain stock behavior. Legacy two-line
receipts still use the bounded PM fallback. This fixes the specific gate that
failed on the RC5 reboot even though both hooks and diagnostics loaded.

For a script-only update, preparation may retain its previous boot boundary
only when the installed APK is byte-identical and the actual loaded hooks and
policy diagnostic pass. GitHub Actions reuses the original signed RC5 guard
APK only for its exact unchanged source tree and pinned APK digest, with
signature verification. The helper APK remains version38; the module is
version39. This avoids a needless APK replacement and restart for this script
correction. A changed guard source tree still builds/signs a new APK normally.


RC5 retains RC4's corrected Vector deployment and fixes a second observed boot
regression: the prepared Codex helper was correct, but its app-owned boot marker
remained stale across two reboots, so new launches silently skipped scheduling.
The enabled module now publishes a volatile boot token before launcher setup;
the prepared helper reads it once per launch. It no longer requires updating
an app-owned file during every boot. Interactive installation prepares the
known helper before reboot, while existing hash/template checks preserve
unknown launchers. A failed property read refuses scheduling, explicit `0`
disables it, and an empty property permits the legacy marker for older modules.
Uninstall invalidates the token before doing other work. The original boot
write failure remains unidentified; this removes that dependency.


RC4 corrects Vector 2.2 build 3080's actual system-server scope: the daemon
requires the literal `system/0` entry. `android/0` is not an automatic alias,
and replacing the scope with only `android/0` prevented the guard from loading.
Preparation now records both entries, and activation requires `system/0`.
CLI deadlines also cover the device's observed cold-start latency, with bounded
retries for transient boot-time package reads. These changes are covered by
regressions whose scope fixture no longer invents aliases.

RC3 fixes the verified guard deployment failure. The Magisk installer prepares
and verifies the APK and Vector scope before reboot. Boot activation never
installs an APK: it requires a previous-boot preparation receipt, matching
installed bytes, owner-user registration, correct scope, both loaded hooks,
and a passing read-only policy self-check before enabling the guard. PM/Vector
calls have fixed deadlines. This corrects activation of the existing guard;
it does not establish a scrolling or battery-life improvement. See the RC3
release notes for the observed boot failure and deployment limits.

The tested Codex route is `codex-wrapper → codex-core → Node → native Codex`.
An npm update replaced the separate `codex` entry with a symlink. The old
installer rejected it before refreshing its boot marker, so the running Codex
kept nice -10 and access to all eight CPUs. RC2 supports the verified
`codex-core` wrapper, keeps a separate original backup and refreshes the launch
gate. The once-per-launch helper uses nice 5 and the available efficiency CPUs.
Helper failures preserve CLI startup. This lets helper work yield to app UI;
local commands may take longer. It does not promise faster app rendering.

RC2 also adds persistent bootstrap/failure logs and root/shell-only
`dumpsys activity athena lightflow` diagnostics with installed hook bits,
real request counters, last observation/error and an isolated policy self-check.
The check never invokes cleanup. Existing pressure decisions are unchanged;
the new diagnostic needs the updated APK loaded after reboot.

Controlled pre-fix scrolling showed Settings at 3/898 janky frames (0.33%)
and Termux at 15/392 (3.83%). Native profiles attributed substantial Termux
CPU time to text layout/drawing. These are separate from the shared CPU
contention; no blanket display, scheduler or thermal overrides were applied.
After the verified live scheduling correction, the same swipe sequence recorded
Settings 3/928 (0.32%) and Termux 3/446 (0.67%). Termux tail frame times were
worse (p95/p99 23/25 ms versus 16/21 ms), so this is a mixed result rather than
proof of universally smoother rendering. See the RC2 release notes.

Replaces the cached-app kill timer with two event-driven hooks in system_server,
using the already installed Zygisk Next + Vector. LightFlow remains one Magisk
module and bundles its permission-free hook APK. No second native injection
engine, package keep-alive list, monitor thread or timed `am kill-all` is added.

The tested firmware has two premature cleanup entry paths:
`OplusAthenaAmManager.releaseMemory(Bundle)` (`type=smart-force`, reason4010)
and `OplusOsenseKillAction.execute(Bundle)` (`type=cached`). On October20 the
OEM history showed CachedClean evictions with 2174 MB available. The guard defers
these routine requests when memory has headroom, independent of app name.
Old LightFlow's swap65% OR RAM1.8GB gate repeatedly evicted cached apps;
the RC retires that design and makes its action button diagnostics-only.

The starting pressure policy uses the firmware's observed 880 MiB critical RAM
threshold. Critical RAM or PSI full.avg10>=10% preserves stock recovery
immediately. Moderate low RAM (<1320 MiB) combined with stalls (>=2%) or nearly
exhausted swap (<=10% free) needs three observed samples over 10 seconds;
sparse pressure observations fail open. Recovery remains latched until RAM is
at least 1760 MiB and PSI<0.5%. These initial bounds require runtime evaluation.
Unknown measurements/types, CPU-hog targets, explicit-free requests, BgLimit,
quick-boot/special mode and verified camera/big-app scenes stay stock.

Native LMKD, thermal controls, app CPU/orphan controls, notification delivery,
FCM, jobs, alarms and active service roles remain enabled. The guard neither
changes OOM scores nor pins social apps awake. It cannot promise every app will
stay resident or every notification will arrive instantly. Keeping more cached
apps can increase RAM use; battery and smoothness gains are unverified.

Builds and signing run in GitHub Actions. The installer rejects missing core
files and prepares the bundled APK through Vector's CLI before reboot.
RC1 boot/scope and live system_server callback activity were observed on the
device. RC2 reports actual counters so registration can be distinguished from
execution. Notification delivery and long-term battery gains cannot be proven
by the build or a synthetic policy check.
Set `su -c 'setprop sys.lightflow.guard 0'` for an immediate return to stock
OEM decisions without rebooting. Removing LightFlow disables the guard APK.

## Version 1.9.10: protect Bitwarden accessibility/autofill

Adds Bitwarden (`com.x8bit.bitwarden`) to the existing background app-ops
allowlist. This keeps its enabled AccessibilityService and AutofillService
eligible while the app is backgrounded on ColorOS, without disabling modules,
changing vault data, or adding a resident process.

## Version 1.9.9: protect active camera and QR scans

Version 1.9.9 skips LightFlow's bounded cached-process cleanup while a native
ColorOS/ML Kit QR scanner or camera client is active. This prevents a concurrent
`am kill-all` from evicting cached camera support during preview startup or
stream teardown. The module remains enabled and Android still decides which
cached processes are safe to remove outside an active camera session.

## Version 1.9.8: avoid PSI-only cleanup

Version 1.9.8 keeps PSI in diagnostics but does not kill cached apps from PSI
alone. Busy foreground work can raise PSI while RAM and ZRAM are healthy, so
cleanup now follows the explicit RAM/ZRAM limits.

## Version 1.9.7: low-frequency watchdog

Version 1.9.7 adds a low-frequency memory watchdog for the tested RMX3741. It
checks every 75 seconds while memory is healthy and every 12 seconds during
pressure, then returns to the slower rate only after available memory exceeds
2.2 GB. Cleanup has a five-minute cooldown and delegates to Android's
`am kill-all`, which selects cached processes; the module does not kill PIDs,
foreground apps, active services, notification listeners, accessibility, dialer,
SMS, or active VPN services itself. This reduces swap thrash while limiting
reload and battery costs.

## Version 1.9.6

Version 1.9.6 triggers Android's cached-process cleanup earlier, at less than
1.8 GB available or 65% ZRAM use. A clean-device sample reached 1.74 GB and
69% ZRAM use; one bounded `am kill-all` then freed about 600 MB and reduced
CPU/SOC temperature by about 23 C. Android still chooses which cached apps to
remove; foreground apps and active services are preserved.

## Version 1.9.5: unused crash source

Version 1.9.5 disables `com.arena.banglalinkmela.app` by default. The installed
12.12.0 build was last used about 50 days ago and crashed during locked boot
because it accessed credential-encrypted preferences too early. Re-enable it
with `su -c 'pm enable --user 0 com.arena.banglalinkmela.app'` if you use the
Banglalink Mela/Quran app; LightFlow records and restores its prior state on
uninstall.

## Version 1.9.4: Facebook background policy

Version 1.9.4 removes Facebook's unrestricted background app-ops. The primary
Facebook process can now be frozen when cached, while Messenger stays in the
notification-safe list. On this RMX3741 test, resetting the old exemption freed
about 500 MB and reduced CPU/SOC temperature by about 14 C after Facebook was
stopped. Facebook notifications may arrive later when the app is cached.

The module performs that reset once for devices upgraded from 1.9.3, then keeps
the migration marker so a later boot does not overwrite a user change.

## Legacy core profile (before 1.10.0)

Adds a bounded memory and thermal relief policy for the tested RMX3741. It
lowers excessive ZRAM reclaim pressure by moving `vm.swappiness` from the
observed `160` to `60`, saves the prior value, and restores it only when no
later user or vendor change replaced the setting. The Magisk action button
also requests Android's cached-process cleanup and selects 60 Hz only when
current thermal or memory-pressure thresholds are reached. It does not stop
foreground apps, resize ZRAM, clear caches, change thermal limits, lock CPU
frequencies, or run an unrestricted process killer. Use the status action to see current
memory, swap, swappiness, and sensor values.

The device diagnostic's broken-bash finding was rechecked: Termux bash starts
successfully and reports `bash 5.3.9`; that report was stale. The live device
did show high swap use and thermal throttling. After cached-process relief,
available memory rose above 2 GB, ZRAM use fell from about 4.2 GB to about
2.6 GB, and the current CPU reading fell from about 77 C to about 55 C.

## Version 1.9.3: consumer bloat limits

The single LightFlow module now also disables a reviewed list of optional
consumer/OEM extras at boot: stores, game center, lock-screen content,
engineering diagnostics, telemetry, optional Microsoft cross-device helpers and
unused AOSP utilities. Every package is checked before disabling, its prior
state is recorded under `/data/adb/lightflow/disabled-packages`, and uninstall
restores that state. Core telephony, SystemUI, Play services, Athena/battery,
network-assist, messaging and notification packages are deliberately excluded.
The disabled features are listed in `module/disabled-background-packages.conf`;
remove any package from that file if you use it.

The installer also restores executable permissions for Magisk boot scripts. On
this RMX3741 build the extracted files were otherwise shown as `0644`, even
though the service had run; the status report now reflects the repaired mode.

## Version 1.9.0: Android 15 memory integration

Replaces the separate A1Memory Magisk module with a LightFlow-native,
RMX3741/Android 15 pressure gate. The upstream `HC_memory` executable was
stripped, had no source in the fork, and logged `This Android version does not
support automatic configuration`; it is not packaged or started.

At boot, `memory-pressure-policy.sh` performs one bounded check. It requests
Android's own `am kill-all` only when available memory is below 1.2 GB, ZRAM is
at least 75% used, or memory PSI full pressure reaches 1%. Android decides
which cached processes are safe to remove. Foreground apps, services,
notifications, LMKD, and thermal policy remain under Android control. Healthy
conditions produce only a log entry and no process action. The script exits on
any model other than RMX3741 or SDK other than 35.

This release is one Magisk module. It contains no A1 APK, LSPosed hook, lmkd
library, system property override, native memory daemon, downloader, or network
client. The standalone Hc_memory module should be removed before rebooting into
this release.

## Version 1.7.7

Adds the installed official bKash package (`com.bKash.customerapp`) to the
existing optional ART optimization action and compilation-state report. Native
Android background optimization already covers eligible apps; this does not add
a bKash timer or change its security, permissions or background execution.
On the tested phone it already has `speed-profile` artifacts, so there is no
reason to force a repeat compilation.

Adds a manual Wi-Fi diagnostic using trusted Android utilities. Status sends no
probe traffic. Probe mode sends at most twelve ICMP requests each to the current
IPv4 Wi-Fi gateway and Cloudflare, with a fifteen-second bound per destination.
There is no periodic test, Wi-Fi lock, forced low-latency mode or resident
monitor. SSID, MAC and private gateway addresses are not printed. Missing or
IPv6-only routes skip the IPv4 probes. Active VPN/app paths can differ from
these explicitly Wi-Fi-bound probes.

```sh
su -c 'sh /data/adb/modules/lightflow/wifi-diagnostics.sh status'
su -c 'sh /data/adb/modules/lightflow/wifi-diagnostics.sh probe'
```

The phone's scan throttling and radio power saving were already enabled, with
verbose logging disabled. Short public probes had no packet loss. One Facebook
request had a DNS timeout; repeat lookups were normal. These observations do
not justify disabling power saving or forcing a global DNS/MTU/TCP profile.
No network-speed or battery improvement is claimed. See the
[measurement report](WIFI-RESULTS-v1.7.7.md).

The boot service stops writing `wifi_sleep_policy` on Android 11/API 30 and
newer. Android documents that setting as unused by the platform; this is a
cleanup, not a latency improvement. Older firmware retains the prior behavior.
See [Android Settings.Global](https://developer.android.com/reference/android/provider/Settings.Global#WIFI_SLEEP_POLICY).

## Codex scheduling (1.7.6)

Extends launch-time scheduling to the inspected Termux Codex launcher. On
RMX3741, Codex previously inherited nice -10 and all eight CPUs. New launches
request nice 5 and CPUs 0–5, the lower-capacity cluster. Existing lower priority
is preserved. Child processes and new threads inherit the policy. This reduces
competition with foreground apps; agent CPU work can take longer. Termux's UI
and Android apps are not restricted by this hook.

The helper runs once, as the Termux user. It adds no root call at launch, polling
service, Zygisk hook, forced boost or additional wakeup schedule. A boot marker
limits it to boots where the enabled module installs/checks the integration.
Unknown or updated launchers are skipped. The original launcher is backed up;
installation and restoration use staged, atomic replacement with the original
permissions, owner and Android SELinux label. Later launcher/helper edits are
preserved. Directly launched native binaries bypass the hook.

Power-policy backups now require successfully read, recognized values.
Uninstall keeps invalid backups and failed restoration attempts for recovery.
The automatic battery-saver trigger mode is left to the user and firmware;
adaptive saving remains enabled independently. Legacy trigger restoration
preserves a newer user/vendor choice.

Shell syntax and policy tests cover installation, restoration, edits, failed
writes, unknown reads, boot-marker gating and real child scheduling. Full reboot
persistence and controlled FPS/battery measurements remain pending. See
[1.7.6 release notes](RELEASE-v1.7.6.md).

## Kernel sleep logging (1.7.5)

Disables verbose per-device kernel suspend/resume timing messages on RMX3741.
This firmware boots with `initcall_debug=1`, which enables those messages;
LightFlow sets `/sys/power/pm_print_times` to `0` after boot. The helper checks
support, saves the previous value before changing it, verifies writes, and
restores its change on uninstall while preserving a later decision to enable
logging. The status report shows the live value. This removes diagnostic
printing work; battery-life improvement remains unmeasured. No resident
tracing process is installed. Full reboot persistence remains unverified.
See the [kernel printing toggle](https://android.googlesource.com/kernel/common/+/c36f0371ff3d30f28368bbbc75092859714b17ab/kernel/power/main.c).

## Weather location policy (1.7.4)

Adds the user-selected RMX3741 Weather background-location restriction.
Fine and coarse location app-ops are set to `foreground` at UID level;
package-level modes were overridden on this device. The helper verifies the
UID belongs only to Weather, saves its prior modes, preserves stricter user
restrictions, and restores its changes on uninstall. Automatic local-weather
updates and location-based widgets may stop updating while Weather is in the
background. Android foreground-service rules may still permit requests when
its UID is considered foreground. No measured battery-life saving is claimed.

## Read-ahead boot ordering (1.7.3)

Fixes a boot-order race on RMX3741. The vendor starts `readahead_init` on
boot completion and applies 512 KiB to userdata after LightFlow's early
write. LightFlow now waits for ten seconds of stopped initializer state,
with a one-minute bound, before applying its 128 KiB cap. It does not keep
polling after startup. This addresses persistence, not a new measured
performance gain. End-to-end reboot verification remains pending.

Adds a reversible userdata read-ahead cap for RMX3741. The boot helper resolves the current `/data` mapping, checks that it is named `userdata`, and lowers values above 128 KiB to 128 KiB. The original setting is saved and writes are checked by reading them back. The status report shows the current value. Uninstall restores the original unless a user or vendor changed the setting after LightFlow applied it.

This limits speculative reads during mixed app workloads. It may reduce unnecessary storage reads and file-cache churn, but lower read-ahead can reduce sequential-read throughput. Smoothness, app retention, and battery improvement have not been established by a controlled workload test. CPU, thermal, ZRAM, and app-retention limits remain governed by the existing policy.

## What it does

- Requests a 60–120 Hz range with a 90 Hz preference after boot. Apps and vendor display policy still decide the actual frame rate.
- Uses 0.5× Android animation scales for a quicker-feeling interface.
- Allows normal background execution for common notification apps, including WhatsApp, WhatsApp Business, Messenger, and Root Call SMS Manager. Facebook is deliberately left under Android's cached-process policy to avoid its persistent keep-alive service consuming RAM and CPU.
- Disables Wi-Fi scanning when Wi-Fi is off; modern Android manages connected-radio power saving.
- Waits for boot completion before applying framework settings, with a bounded readiness check.
- Disables verbose kernel sleep-timing logs on RMX3741, with saved-state restoration on uninstall.
- Disables only optional Meta updater, installer, analytics, and Ads Manager companion packages; Facebook, Messenger, and Facebook Lite remain untouched.
- On 6–12 GB devices, keeps MGLRU reclaim and zero ZRAM read-ahead enabled for efficient multitasking.
- Uses one pressure-gated cached-process action on RMX3741 instead of a separate A1Memory daemon.
- Keeps the kernel's vendor CPU governor, thermal limits, core control, SELinux, and ZRAM size intact; it does not fight hardware policy.
- Explicitly enables Android's cached-app freezer, app standby, and adaptive power-saver policy when the framework reports support. These controls cover every app without a resident process.
- Provides an optional Magisk action for Instagram, YouTube, Facebook, Messenger, WhatsApp, LinkedIn, Reddit, and bKash using their existing speed profiles.

The notification policy is intentionally a compromise: normal background delivery is allowed for messaging apps, but notification apps are not placed on the permanent Doze whitelist. Facebook is excluded from that exemption because its keep-alive service was a measured source of CPU, heat and RAM pressure; its notifications may be delayed until Android or the user resumes it. This protects battery better than keeping every app awake. Wi-Fi-off scanning is also disabled because it does not help an active connection or FCM delivery, but can wake the radio for network discovery and location. Android, the network, and the app's own servers can still delay notifications, so no module can guarantee delivery under every condition.

The Meta companion policy is likewise narrow. Its list includes only `com.facebook.appmanager`, `com.facebook.services`, `com.facebook.system`, `com.facebook.stella`, and `com.facebook.adsmanager`. It does not disable Facebook, Messenger, Facebook Lite, WhatsApp, Google Play services, or any other app that may be needed for notifications or normal use. The original state of each listed package is recorded, so uninstall re-enables only packages that LightFlow disabled itself.

## Memory policy

The RMX3741 has 8 GB RAM, 5.5 GB of LZ4 ZRAM, and MGLRU support. LightFlow preserves the vendor's multitasking-oriented low-memory-killer and swappiness policy, keeps MGLRU fully enabled, and keeps ZRAM read-ahead at zero. It does not enable NAND swap, increase ZRAM, pin processes, raise cached-process limits, clear caches, or run a resident memory daemon. Its single pressure-gated action asks Android to remove cached processes only under pressure. Those common “RAM booster” changes either consume more CPU/storage power or make Android kill useful apps sooner.

## Root-level policy

LightFlow applies the lowest-level controls this device exposes safely: MGLRU reclaim, zero ZRAM read-ahead, Android's kernel-backed cached-process freezer, and the vendor CPU policy's existing governor and thermal limits. The status report exposes raw CPU governor/frequency, reclaim, pressure, freezer, thermal, and adaptive-power state. It does not force a governor, pin frequencies, change uclamp/core-control values, disable thermal protection, or run a polling daemon. Its single pressure check may request Android's cached-process cleanup under high pressure. Those writes can trade scrolling responsiveness, modem reliability, or battery life for a benchmark number on this MediaTek/Oplus firmware.

Adaptive power saving is framework-managed: it can reduce background work when Android's battery model calls for it while leaving the current interactive mode unchanged. Cached-app freezing and pressure relief apply only to processes Android already classifies as cached; foreground apps and notification-critical services remain managed by Android.

## Install

1. Download the newest `LightFlow-*.zip` from the Releases page.
2. In Magisk, open **Modules** → **Install from storage**.
3. Select the ZIP while Android and Vector are running. The installer verifies
   the helper APK and scope before reporting preparation complete; then reboot.
4. Run the module action/status and verify the loaded hook diagnostic, not only
   the module's enabled switch.

The ZIP is a Magisk-module flashable package. It is not intended for flashing from a custom recovery.

## Optional app optimization

Routine optimization is automatic through Android's existing ART background job. LightFlow 1.7.0 verifies that job at boot and attempts to enable it if missing on supported ART versions. It leaves an already scheduled job untouched. Android chooses eligible apps and waits for charging, sufficient battery, idle time, and this ROM's temperature constraint. It does not guarantee an immediate run whenever charging starts. The action button is an optional targeted request, not a required maintenance step.

No LightFlow polling service or extra wakeup schedule is installed. The status script shows the native job's satisfied and unsatisfied constraints. Uninstall leaves Android's normal optimizer enabled. On this phone the native job was already scheduled before 1.6.4; the change adds verification/recovery and makes that automatic behavior visible. See [ART Service](https://android.googlesource.com/platform/art/+/android16-qpr2-release/libartservice/service/README.md).

After installation, use the module’s Magisk action button once while the device is cool, preferably charging and idle. It requests targeted `speed-profile` compilation for Instagram, YouTube, Facebook, Messenger, WhatsApp, LinkedIn, Reddit, and bKash. On ART versions that support it, it uses `PRIORITY_BACKGROUND` and prints detailed results. It does not force recompilation of current artifacts. It checks battery temperature before each app and stops at 40 °C; an already running compilation is not interrupted. It does not compile all apps or run a resident optimizer loop.

An accepted command does not prove that compiled code was generated: without a usable profile, ART can fall back to `verify`. Use the apps normally to collect profiles, then let Android optimize during idle charging. See [ART Service configuration](https://source.android.com/docs/core/runtime/configure/art-service).

## Check responsiveness

Version 1.6.3 adds Instagram to the optimization action and checks Android's thermal status before each app. It defers work at moderate throttling or above, or when status is unavailable, even if battery temperature looks normal. This supplements the 40 °C battery check. It does not interrupt a compilation already underway or automatically retry; run the action when the phone is cool and idle. The status report now separates live thermal readings from cached events.

On-device investigation found Instagram UI-thread stalls despite mostly short GPU timings; Instagram remained at `verify`, while LinkedIn and Reddit already had `speed-profile` artifacts. The thermal service reported moderate throttling. These observations do not establish a single cause or a measured scrolling improvement. No global app CPU restrictions, fixed high-refresh mode, cache clearing, or thermal overrides were added.

Run `su -c 'sh /data/adb/modules/lightflow/status.sh'` for a read-only report of actual display policy, memory pressure, battery temperature, and target app compilation state. The script runs only when requested.

During the 1.6.1 investigation on RMX3741, 1.6.0 was active with about 2.5 GB available RAM. Facebook and Reddit reported `verify`; YouTube reported `run-from-apk`. A separate terminal agent repeatedly consumed about one CPU core. The foreground display policy requested a 60 Hz render ceiling despite the stored refresh preferences; this was not a measurement of those three apps while scrolling. LightFlow cannot fix another process's workload or promise a particular frame rate by writing refresh settings. Android combines app requests with system policy ([display documentation](https://source.android.com/docs/core/graphics/multiple-refresh-rate)).

Version 1.6.1 repairs the missing YouTube optimization target, reduces repeat compilation work, exposes results, and waits for boot readiness. It does not establish a measured FPS or battery-life improvement. Compare the same app interaction at similar temperature and brightness with background terminal work idle before drawing that conclusion.

## Agent scheduling (1.6.2)

On this Termux setup, LightFlow installs a backed-up hook in the known `agy` launcher after root elevation. Each new launch inherits nice level 5 (or keeps an already lower priority) and affinity to the lowest-capacity CPU cluster when the kernel exposes a heterogeneous CPU topology. On RMX3741 this selects CPUs 0–5. New threads and child commands inherit the policy; CPU-heavy agent work may take longer. Unknown topologies keep their original affinity.

There is no polling daemon. The hook runs only when `agy` starts; it does not manage other terminal tools, directly launched binaries, or already running agents. It checks the module's disable/remove markers before applying changes. Uninstall restores the original launcher only if it still matches the module-managed copy, preserving later user edits. Restart the agent after disabling/removing LightFlow to drop inherited scheduling settings.

The installer recognizes the SHA-256 of the tested launcher and skips unknown or updated launchers. Reboot persistence comes from the boot service installing/checking this hook. Lower power consumption is an intention, not a measured battery-life guarantee.

## LSPosed guidance

LightFlow does not modify LSPosed. Hooks cannot be made free of CPU or battery cost without removing their work. Keep each module scoped only to the apps that need it; avoid hooking SystemUI, the launcher, the camera, or every app globally. For WhatsApp, test `com.wmods.wppenhacer` separately if startup, scrolling, heat, or battery worsens. This preserves normal module behavior while giving a clean A/B test.

## Network behavior

LightFlow keeps Android/Oplus Wi-Fi validation and roaming in control. It does not hard-code MTU, DNS servers, TCP congestion control, or firewall rules. The tested device previously had an `mtu-fix` module that forced Wi-Fi MTU 1400; that module was removed because the interface and router negotiate 1500 correctly. A module that claims universal internet-speed gains through MTU or DNS forcing is usually network-dependent and can reduce speed or break VPNs.

## Uninstall / rollback

Disable or remove the module in Magisk and reboot. Its uninstall script restores the app-ops, optional Meta companion package states, Wi-Fi-off scan setting, and low-level power-policy values it touched. Refresh-rate, animation, and Wi-Fi sleep settings are left at the values currently selected by the user.

## Build locally

```sh
./build.sh
```

The resulting ZIPs are written to `dist/` and contain only their Magisk module payloads. `AheadOfModernTime-v*.zip` is the companion camera module; see [AHEAD_OF_MODERN_TIME.md](AHEAD_OF_MODERN_TIME.md) for capture presets and its safety boundaries.
