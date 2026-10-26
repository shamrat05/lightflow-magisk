# LightFlow v1.10.0-rc.6.4

Adds `com.eyecon.global` to this device's optional package policy after the
owner confirmed that Eyecon is unused. The package is disabled for user 0 at
boot using the existing policy. App data remains installed; Eyecon caller-ID
features are unavailable while disabled.

The device check verified `enabled=3` (disabled by user), no Eyecon process,
and no active Eyecon service. The default dialer is Google Phone. A package
that was already user-disabled remains disabled when LightFlow is removed.

The system guard source is unchanged and uses the previously verified,
signed RC5 APK. This release adds no monitoring loop or sensor hook.

The change removes future work from the unused app. It does not establish
a measured battery-life improvement or resolve every source of screen-off
drain. GitHub Actions runs the existing policy and deployment tests before
packaging and publishing the release.
