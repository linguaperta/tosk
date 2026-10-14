# Building releases

All commands run from `app/` with Flutter on PATH (`C:\Users\timo\dev\flutter\bin`).

| Target | Command | Output |
| --- | --- | --- |
| Android (phone, Boox) | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| Windows | `flutter build windows --release` | `build/windows/x64/runner/Release/` |
| Web | `flutter build web --release` | `build/web/` (serve over HTTP; the WASM SQLite needs it) |
| iOS / macOS | `flutter build ipa` / `flutter build macos` | needs a Mac with Xcode |
| Linux | `flutter build linux` | needs Linux |

Plugin requirements (since v0.3):

- **Windows:** nothing beyond the standard Flutter desktop toolchain (Visual Studio Build Tools with the C++ workload; ATL is **not** needed). The pub.dev `flutter_secure_storage_windows` builds a C++ plugin against ATL (`atlstr.h`), so `app/pubspec.yaml` replaces it via `dependency_overrides` with the local pure-Dart package `app/packages/secure_storage_windows_dart/` (same package name, `dartPluginClass` only). It stores the AI key in the Windows Credential Manager through FFI, and no C++ is compiled for it: `windows/flutter/generated_plugins.cmake` lists only `audioplayers_windows`. Check that after upgrading `flutter_secure_storage`. The package has its own tests (`cd app/packages/secure_storage_windows_dart && flutter test`); `flutter test integration_test/secure_storage_test.dart -d windows` round-trips a key through the real Credential Manager.
- **Linux:** `flutter_secure_storage_linux` needs `libsecret-1-dev`, and `audioplayers_linux` needs the GStreamer development packages (`libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev`).
- **Android** release builds declare `INTERNET` (for the optional AI calls), and the **macOS** entitlements include `com.apple.security.network.client`. On macOS, flutter_secure_storage may also need the Keychain Sharing capability; this is untested without a Mac.

## Android signing

- **Keystore:** release APKs are signed with the upload keystore at `C:\Users\timo\dev\keys\tosk-upload.jks`.
- **Credentials:** they are in `app/android/key.properties` (git-ignored; a backup copy sits next to the keystore). Keep both files safe, because updates must be signed with the same key.
- **Fallback:** if `key.properties` is missing, the release build falls back to the debug key.

## Installing on a device

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

`adb` is in `C:\Users\timo\dev\android\platform-tools`. On the Boox, enable USB debugging in developer options, or copy the APK over and open it.
