# LightFlow v1.10.0-rc.6.8

The retired memory watchdog's status command now leaves the PID file and processes alone. The legacy cleanup runs only when explicitly asked to stop during an upgrade or uninstall.

Magisk's Action now displays Android's cumulative LMKD kill counts alongside LightFlow's guard counters. This lets you distinguish native low-memory exits from OEM cleanup requests deferred by LightFlow.

On the Realme RMX3741, all three existing guard hooks loaded and Root Call SMS Manager kept its foreground process during testing. Native LMKD still evicted cached processes. This release changes diagnostics and leaves memory thresholds, scheduling, and thermal policy unchanged.
