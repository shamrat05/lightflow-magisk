# LightFlow v1.10.0-rc.3

## Fixed: injected guard deployment

Device evidence established that RC2 could update its helper APK after Vector had already loaded older code into system_server. A boot-time Package Manager failure then left the runtime switch disabled. Registering a module scope did not prove active protection.

The Magisk installer now prepares the signed APK and Vector scope before reboot. APK installation uses bounded retries and verifies the installed bytes. Boot activation never replaces an APK: it verifies a preparation receipt from a previous boot, the actual installed hash, owner-user registration, android/0 scope, both loaded hooks, and the isolated policy self-check before enabling the guard. An incomplete setup retains stock memory policy with a specific error.

Install from the running Magisk app after Android and Vector are ready. Recovery installation cannot prepare the injected guard and is rejected. A preparation failure may leave a verified helper APK installed; no app data is removed and no rollback is claimed.

## Expected outcome and limits

- The existing system-level OEM cleanup guard can activate reliably after one prepared update and reboot.
- No cached-app kill timer, additional worker, thermal bypass, permanent refresh lock, or new per-app list is added.
- Less unnecessary OEM app eviction is the intended effect of the guard. This deployment correction does not establish a universal scrolling, battery-life, or temperature improvement.
- Preparation, loaded runtime hooks, and observed cleanup callbacks remain distinct checks. A build alone proves none of the device runtime outcomes.

Build and signing run in GitHub Actions with the existing signing identity.
