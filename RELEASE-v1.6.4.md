# LightFlow 1.6.4

Verify Android's automatic background optimization job at boot and attempt to re-enable it if absent on supported ART versions. An existing job is preserved. The status report now exposes its constraints, so users can see why optimization is waiting.

Routine optimization needs no action-button press. Android schedules the work and selects apps, subject to charging, idle, battery, and ROM temperature constraints. LightFlow does not add a second optimizer, polling daemon, or force-run command. Uninstall leaves normal Android optimization enabled.

On RMX3741 the job was already scheduled and waiting on constraints before this release. Verified that the boot helper detects it and returns without starting compilation. Android shell syntax and ZIP integrity checks passed. A future charging/idle run was not observed during validation.
