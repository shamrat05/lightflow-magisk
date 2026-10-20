#!/usr/bin/env bash
set -euo pipefail
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
sdk="${ANDROID_HOME:?Android SDK required}"
tools="$sdk/build-tools/35.0.0"
android="$sdk/platforms/android-35/android.jar"
work="$root/guard/build"
mkdir -p "$work/classes" "$work/dex" "$work/unsigned/assets"
api="$work/xposed-api-82.jar"
curl --fail --location --retry 2 --silent --show-error \
  https://api.xposed.info/de/robv/android/xposed/api/82/api-82.jar -o "$api"
printf '%s  %s\n' f48c635f1c7469fdec0e00ad2ea0b7a6b2f5b55065784a35b7ca3a84615e8e25 "$api" | sha256sum -c -
# The API is compile-only; it must never be included in the APK.
javac -source 8 -target 8 -cp "$android:$api" -d "$work/classes" \
  "$root"/guard/src/dev/lightflow/guard/*.java
jar cf "$work/classes.jar" -C "$work/classes" .
"$tools/d8" --lib "$android" --classpath "$api" --min-api 35 \
  --output "$work/dex" "$work/classes.jar"
"$tools/aapt2" compile --dir "$root/guard/res" -o "$work/resources.zip"
"$tools/aapt2" link -I "$android" --manifest "$root/guard/AndroidManifest.xml" \
  -o "$work/unsigned.apk" "$work/resources.zip"
cp "$root/guard/assets/xposed_init" "$work/unsigned/assets/xposed_init"
cp "$work/dex/classes.dex" "$work/unsigned/classes.dex"
(cd "$work/unsigned" && zip -q "$work/unsigned.apk" classes.dex assets/xposed_init)
"$tools/zipalign" -p -f 4 "$work/unsigned.apk" "$work/aligned.apk"
"$tools/apksigner" sign --ks "${LIGHTFLOW_GUARD_KEYSTORE:?Signing key required}" \
  --ks-key-alias lightflow --ks-pass env:LIGHTFLOW_GUARD_STORE_PASSWORD \
  --key-pass env:LIGHTFLOW_GUARD_STORE_PASSWORD --out "$root/module/guard.apk" "$work/aligned.apk"
"$tools/apksigner" verify --verbose "$root/module/guard.apk"
"$tools/aapt2" dump badging "$root/module/guard.apk" | head -5
