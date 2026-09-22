# LightFlow 1.7.1

LightFlow's read-only status report now checks module startup and policy application:

- Confirms `service.sh` is executable and the module is enabled.
- Records the Linux boot ID after activation, then checks that LightFlow ran during the current boot.
- Reports the latest activation log entry.
- Compares cached-app freezer, adaptive power, Wi-Fi scanning, and refresh preferences with LightFlow's requested values.
- Reports whether Android's adaptive power saver is active.

This release improves visibility when a boot script is skipped or a setting does not stick. It makes no new CPU, LMKD, ZRAM, thermal, or background-process tuning changes and does not claim a measured performance or battery-life gain.

The package retains the existing Android-managed freezer, adaptive power, refresh-rate range, and idle/charging ART optimization policy.
