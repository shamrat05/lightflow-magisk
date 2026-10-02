# LightFlow 1.7.5

Reduces kernel diagnostic work on RMX3741 by disabling verbose per-device
suspend/resume timing prints after boot. The firmware enables these through
`initcall_debug=1`; the new helper changes only `/sys/power/pm_print_times`.

The helper skips unsupported devices or unavailable nodes, saves the prior
value before writing, verifies the result, and supports restoration on
uninstall. It preserves a later user/vendor decision to re-enable logging.
The status report exposes the live setting. No tracing daemon is installed.

Verified on-device: live setting readback, saved-state restoration, repeated
application, and preservation of a later enabled value. Shell syntax,
existing policy tests, and ZIP payload checks passed.

Battery-life improvement and full reboot persistence remain unmeasured.
Install `LightFlow-v1.7.5.zip` through Magisk Modules. The ZIP is a Magisk
module package, not a custom-recovery installer.
