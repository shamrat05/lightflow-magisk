# LightFlow Magisk Module

LightFlow is a conservative Android performance profile for rooted devices. It keeps the phone responsive without the usual battery and thermal damage caused by permanent turbo modes, fake thermal readings, forced refresh rates, ZRAM loops, or compiling every installed app.

## What it does

- Requests a 60–120 Hz range with a 90 Hz preference after boot. Apps and vendor display policy still decide the actual frame rate.
- Uses 0.5× Android animation scales for a quicker-feeling interface.
- Allows normal background execution for common notification apps, including WhatsApp and WhatsApp Business.
- Keeps established Wi-Fi available during sleep, while disabling Wi-Fi scanning when Wi-Fi is off.
- Waits for boot completion before applying framework settings, with a bounded readiness check.
- Disables only optional Meta updater, installer, analytics, and Ads Manager companion packages; Facebook, Messenger, and Facebook Lite remain untouched.
- On 6–12 GB devices, keeps MGLRU reclaim and zero ZRAM read-ahead enabled for efficient multitasking.
- Leaves Doze, thermal limits, CPU governors, SELinux, ZRAM, and vendor performance properties alone.
- Provides an optional Magisk action for YouTube, Facebook, WhatsApp, LinkedIn, and Reddit using their existing speed profiles.

The notification policy is intentionally a compromise: normal background delivery is allowed, but notification apps are not placed on the permanent Doze whitelist. This protects battery better than keeping every app awake. Wi-Fi-off scanning is also disabled because it does not help an active connection or FCM delivery, but can wake the radio for network discovery and location. Android, the network, and the app’s own servers can still delay notifications, so no module can guarantee delivery under every condition.

The Meta companion policy is likewise narrow. Its list includes only `com.facebook.appmanager`, `com.facebook.services`, `com.facebook.system`, `com.facebook.stella`, and `com.facebook.adsmanager`. It does not disable Facebook, Messenger, Facebook Lite, WhatsApp, Google Play services, or any other app that may be needed for notifications or normal use. The original state of each listed package is recorded, so uninstall re-enables only packages that LightFlow disabled itself.

## Memory policy

The RMX3741 has 8 GB RAM, 5.5 GB of LZ4 ZRAM, and MGLRU support. LightFlow preserves the vendor's multitasking-oriented low-memory-killer and swappiness policy, keeps MGLRU fully enabled, and keeps ZRAM read-ahead at zero. It does not enable NAND swap, increase ZRAM, pin processes, raise cached-process limits, clear caches, or run a memory daemon. Those common “RAM booster” changes either consume more CPU/storage power or make Android kill useful apps sooner.

## Install

1. Download the newest `LightFlow-*.zip` from the Releases page.
2. In Magisk, open **Modules** → **Install from storage**.
3. Select the ZIP and reboot.
4. Verify that the module is enabled.

The ZIP is a Magisk-module flashable package. It is not intended for flashing from a custom recovery.

## Optional app optimization

After installation, use the module’s Magisk action button once while the device is cool, preferably charging and idle. It requests targeted `speed-profile` compilation for YouTube, Facebook, WhatsApp, LinkedIn, and Reddit. On ART versions that support it, it uses `PRIORITY_BACKGROUND` and prints detailed results. It does not force recompilation of current artifacts. It checks battery temperature before each app and stops at 40 °C; an already running compilation is not interrupted. It does not compile all apps or run a resident optimizer loop.

An accepted command does not prove that compiled code was generated: without a usable profile, ART can fall back to `verify`. Use the apps normally to collect profiles, then let Android optimize during idle charging. See [ART Service configuration](https://source.android.com/docs/core/runtime/configure/art-service).

## Check responsiveness

Run `su -c 'sh /data/adb/modules/lightflow/status.sh'` for a read-only report of actual display policy, memory pressure, battery temperature, and target app compilation state. The script runs only when requested.

During the 1.6.1 investigation on RMX3741, 1.6.0 was active with about 2.5 GB available RAM. Facebook and Reddit reported `verify`; YouTube reported `run-from-apk`. A separate terminal agent repeatedly consumed about one CPU core. The foreground display policy requested a 60 Hz render ceiling despite the stored refresh preferences; this was not a measurement of those three apps while scrolling. LightFlow cannot fix another process's workload or promise a particular frame rate by writing refresh settings. Android combines app requests with system policy ([display documentation](https://source.android.com/docs/core/graphics/multiple-refresh-rate)).

Version 1.6.1 repairs the missing YouTube optimization target, reduces repeat compilation work, exposes results, and waits for boot readiness. It does not establish a measured FPS or battery-life improvement. Compare the same app interaction at similar temperature and brightness with background terminal work idle before drawing that conclusion.

## LSPosed guidance

LightFlow does not modify LSPosed. Hooks cannot be made free of CPU or battery cost without removing their work. Keep each module scoped only to the apps that need it; avoid hooking SystemUI, the launcher, the camera, or every app globally. For WhatsApp, test `com.wmods.wppenhacer` separately if startup, scrolling, heat, or battery worsens. This preserves normal module behavior while giving a clean A/B test.

## Network behavior

LightFlow keeps Android/Oplus Wi-Fi validation and roaming in control. It does not hard-code MTU, DNS servers, TCP congestion control, or firewall rules. The tested device previously had an `mtu-fix` module that forced Wi-Fi MTU 1400; that module was removed because the interface and router negotiate 1500 correctly. A module that claims universal internet-speed gains through MTU or DNS forcing is usually network-dependent and can reduce speed or break VPNs.

## Uninstall / rollback

Disable or remove the module in Magisk and reboot. Its uninstall script restores the app-ops, optional Meta companion package states, and Wi-Fi-off scan setting it touched. Refresh-rate, animation, and Wi-Fi sleep settings are left at the values currently selected by the user.

## Build locally

```sh
./build.sh
```

The resulting ZIPs are written to `dist/` and contain only their Magisk module payloads. `AheadOfModernTime-v*.zip` is the companion camera module; see [AHEAD_OF_MODERN_TIME.md](AHEAD_OF_MODERN_TIME.md) for capture presets and its safety boundaries.
