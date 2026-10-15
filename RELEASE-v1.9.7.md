# LightFlow 1.9.7

- Adds a resident low-frequency memory watchdog for RMX3741 / Android 15.
- Checks every 75 seconds when available memory is above the healthy range.
- Checks every 12 seconds during pressure below 1.8 GB available or 65% ZRAM.
- Uses 2.2 GB hysteresis before returning to the idle interval.
- Enforces a five-minute cooldown between cached-process cleanup requests.
- Delegates process selection to Android `am kill-all`; no arbitrary PID killing.
- Stops cleanly when the module is disabled or uninstalled.
- Adds regression coverage for the cleanup cooldown.

This is designed to reduce swap thrash and heat with limited app reload cost.
It cannot guarantee zero reloads because Android may remove cached processes when
the device is under pressure.
