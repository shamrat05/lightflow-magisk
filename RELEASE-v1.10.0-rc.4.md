# LightFlow v1.10.0-rc.4

## Fixed: Vector system-server scope and cold-start deadlines

The RC3 device reboot exposed a registration error: its helper replaced the guard scope with android/0, removing the system/0 row that Vector requires to load a module into system_server. The corrected installer explicitly retains both entries; runtime activation requires system/0. The recommended APK scope also includes system.

This is verified against the installed framework's exact 3080 source revision: [system-server database query](https://github.com/JingMatrix/Vector/blob/88f8e1fa/daemon/src/main/kotlin/org/matrix/vector/daemon/data/ModuleDatabase.kt#L147). The [legacy callback](https://github.com/JingMatrix/Vector/blob/88f8e1fa/legacy/src/main/java/org/matrix/vector/legacy/LegacyDelegateImpl.java#L53) still supplies packageName android, matching the existing Java entry point.

The device's module inventory can exceed five seconds during startup. PM read deadlines are now 15 seconds, CLI deadlines 20 seconds, and runtime diagnostic 12 seconds with an internal 10-second timeout. Early package reads and runtime readiness checks retry up to three times. All retries remain bounded; no polling worker or boot-time APK installation is added.

Regression fixtures now preserve only the exact requested scope, reject android-only registration, accept system/0, reject cross-user combinations, and cover a simulated cold CLI response. Preparation still verifies installed bytes before reboot; activation still requires both loaded hooks and the read-only policy self-check.

## Expected outcome

- Correct loading and activation of the existing shared system memory guard.
- Fewer needless OEM cached-app evictions is the intended effect; real callback counters establish whether the guard has acted.
- No thermal bypass, permanent high-refresh lock, app-data removal, per-app keepalive list, or new resident monitor.
- This fixes deployment. Universal scrolling and battery gains are not established by the build or synthetic tests.

Build and signing run in GitHub Actions with the existing signing identity.
