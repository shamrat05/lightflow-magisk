# LightFlow 1.9.8

- Keeps PSI in diagnostics but removes it as a cached-process kill trigger.
- Cleanup now occurs only below 1.8 GB available RAM or at least 65% ZRAM use.
- Prevents foreground workload PSI spikes from causing unnecessary app reloads.
- Adds regression coverage for healthy RAM with high PSI.

This aligns the runtime behavior with the dual-rate watchdog thresholds.
