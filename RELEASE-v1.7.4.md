# LightFlow 1.7.4

Adds the user-selected Realme Weather background-location restriction on
RMX3741, using foreground-only fine/coarse location modes for user 0.
The policy targets Weather's UID because package-level modes were overridden
on this device. It skips shared UIDs and preserves stricter user restrictions.
Prior effective modes are saved and restored on uninstall; subsequent user
changes are preserved. Boot application uses no resident monitor.

Automatic local-weather and location-based widget updates may stop while the
service is in the background. Android may still permit location when the UID
is considered foreground, including eligible foreground services.

Verified on-device: UID-mode readback, repeated application, rollback to prior
allowed access, reapplication, and an inactive background location request.
No package data clearing or app killing was used. Shell syntax and ZIP checks
passed. Battery savings and full reboot persistence remain unmeasured.
