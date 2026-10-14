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

- **Windows:** `flutter_secure_storage_windows` (the AI key) compiles against ATL. Install **C++ ATL for latest build tools (x86 & x64)** in the Visual Studio Installer (Individual components); without it the build fails with `atlstr.h` not found.
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
