#!/usr/bin/env bash
# Release-build smoke test: install the APK on the running emulator, launch it,
# and fail if it crashes on start or isn't running 25 seconds later.
# Usage: android-smoke.sh <apk> <application id>
set -u
apk="$1"; app="$2"
adb install -r "$apk"
adb logcat -c
adb shell monkey -p "$app" -c android.intent.category.LAUNCHER 1
sleep 25
adb logcat -d > logcat.txt || true
pid="$(adb shell pidof "$app" | tr -d '\r')"
if grep -E "FATAL EXCEPTION|Fatal signal|Process: $app" logcat.txt; then
  echo "::error::The release build crashed on start"; exit 1
fi
if [ -z "$pid" ]; then
  echo "::error::The app is not running 25 s after launch"; tail -200 logcat.txt; exit 1
fi
echo "Running as pid $pid; no crash in logcat."
