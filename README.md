# LightFlow Magisk Module

LightFlow is a conservative Android performance profile for rooted devices. It keeps the phone responsive without the usual battery and thermal damage caused by permanent turbo modes, fake thermal readings, forced refresh rates, ZRAM loops, or compiling every installed app.

## What it does

- Applies 60–120 Hz adaptive refresh with a 90 Hz preference after boot.
- Uses 0.5× Android animation scales for a quicker-feeling interface.
- Allows normal background execution for common notification apps: WhatsApp, Facebook, Messenger, Gmail, Telegram, Signal, and Outlook.
- Leaves Doze, thermal limits, CPU governors, SELinux, ZRAM, and vendor performance properties alone.
- Provides an optional Magisk action that compiles only Facebook with its existing speed profile.

The notification policy is intentionally a compromise: normal background delivery is allowed, but notification apps are not placed on the permanent Doze whitelist. This protects battery better than keeping every app awake. Android, the network, and the app’s own servers can still delay notifications, so no module can guarantee delivery under every condition.

## Install

1. Download `LightFlow-v1.0.0.zip` from the Releases page.
2. In Magisk, open **Modules** → **Install from storage**.
3. Select the ZIP and reboot.
4. Verify that the module is enabled.

The ZIP is a Magisk-module flashable package. It is not intended for flashing from a custom recovery.

## Optional Facebook optimization

After installation, use the module’s Magisk action button once while the device is cool or charging. It runs a targeted `speed-profile` compilation for Facebook only. It does not compile all apps and does not run a resident optimizer loop.

## Uninstall / rollback

Disable or remove the module in Magisk and reboot. Its uninstall script restores the app-ops it touched. Refresh-rate and animation settings are left at the values currently selected by the user.

## Build locally

```sh
./build.sh
```

The resulting ZIP is written to `dist/` and contains only the Magisk module payload.
