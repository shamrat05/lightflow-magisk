# LightFlow Magisk Module

LightFlow is a conservative Android performance profile for rooted devices. It keeps the phone responsive without the usual battery and thermal damage caused by permanent turbo modes, fake thermal readings, forced refresh rates, ZRAM loops, or compiling every installed app.

## What it does

- Applies 60–120 Hz adaptive refresh with a 90 Hz preference after boot.
- Uses 0.5× Android animation scales for a quicker-feeling interface.
- Allows normal background execution for common notification apps, including WhatsApp and WhatsApp Business.
- Leaves Doze, thermal limits, CPU governors, SELinux, ZRAM, and vendor performance properties alone.
- Provides an optional Magisk action that compiles only Facebook and WhatsApp with their existing speed profiles.

The notification policy is intentionally a compromise: normal background delivery is allowed, but notification apps are not placed on the permanent Doze whitelist. This protects battery better than keeping every app awake. Android, the network, and the app’s own servers can still delay notifications, so no module can guarantee delivery under every condition.

## Install

1. Download the newest `LightFlow-*.zip` from the Releases page.
2. In Magisk, open **Modules** → **Install from storage**.
3. Select the ZIP and reboot.
4. Verify that the module is enabled.

The ZIP is a Magisk-module flashable package. It is not intended for flashing from a custom recovery.

## Optional Facebook and WhatsApp optimization

After installation, use the module’s Magisk action button once while the device is cool or charging. It runs targeted `speed-profile` compilation for Facebook and WhatsApp only. It does not compile all apps and does not run a resident optimizer loop.

## LSPosed guidance

LightFlow does not modify LSPosed. Hooks cannot be made free of CPU or battery cost without removing their work. Keep each module scoped only to the apps that need it; avoid hooking SystemUI, the launcher, the camera, or every app globally. For WhatsApp, test `com.wmods.wppenhacer` separately if startup, scrolling, heat, or battery worsens. This preserves normal module behavior while giving a clean A/B test.

## Uninstall / rollback

Disable or remove the module in Magisk and reboot. Its uninstall script restores the app-ops it touched. Refresh-rate and animation settings are left at the values currently selected by the user.

## Build locally

```sh
./build.sh
```

The resulting ZIPs are written to `dist/` and contain only their Magisk module payloads. `AheadOfModernTime-v*.zip` is the companion camera module; see [AHEAD_OF_MODERN_TIME.md](AHEAD_OF_MODERN_TIME.md) for capture presets and its safety boundaries.
