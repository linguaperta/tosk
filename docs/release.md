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

## Publishing course packs

Course packs ship to the app without an app update: they are GitHub Release assets of the public content repo [`timoverlaan/tosk-data`](https://github.com/timoverlaan/tosk-data) (CC BY-SA 4.0). The app reads the release index from a **stable URL**:

```
https://github.com/timoverlaan/tosk-data/releases/latest/download/index.json
```

GitHub redirects `releases/latest/download/<asset>` to that asset of the newest release (not a draft, not a pre-release), so publishing a new release is all it takes. Each course in `index.json` points at its own asset, `https://github.com/timoverlaan/tosk-data/releases/download/<tag>/<id>.sqlite`, so an older index keeps working.

Once per machine, log the GitHub CLI in (the user does this; the pipeline never stores a token):

```bash
gh auth login        # GitHub.com, HTTPS, log in with a browser; needs write access to tosk-data
gh auth status
```

Then, from the repo root with the pipeline venv active:

```bash
python -m pipeline build it nl --install          # packs -> tosk-data/dist (and app/assets/courses)
python -m pipeline publish it nl --dry-run        # writes dist/index.json, prints the gh commands
python -m pipeline publish it nl                  # gh auth status + gh release create packs-YYYYMMDD ... --latest
cd ../tosk-data && git add dist && git commit -m "Packs packs-YYYYMMDD" && git push
```

- `publish` reads every pack's own `meta` (id, version, title, description, target and source languages, schema version, unverified), computes size and sha256, and writes `dist/index.json` with `index_version`, `generated_at`, `tag` and one entry per course. The default tag is `packs-YYYYMMDD` (UTC); pass `--tag packs-20261014-2` for a second release on one day (tags must be new).
- `min_app_version` defaults to `0.3.0`, the oldest app that understands today's packs. A pack that needs newer app code gets `--min-app-version X.Y.Z` (or a `min_app_version` key in its meta); older apps then show "needs a newer version of the app" instead of a download.
- A pack built with a new course-DB schema **major** version is never offered to older apps (they compare the major with `kCourseDbSchemaVersion`). Minor bumps (`1.1`) are additive and download fine.
- **Sarnami (`hns`) is refused, always** (`RestrictedContentError`, exit code 2): it is all rights reserved and stays local (docs/sarnami.md). The release asset list is built from the course ids you pass, never from a glob over `dist/`.
- `--repo owner/name` publishes elsewhere (a fork, for testing); the app's index URL can be changed in the debug screen (Settings → Debug → cloud icon, setting `packs.index_url`).
- To withdraw a broken release, delete it (`gh release delete <tag> --repo timoverlaan/tosk-data`); `latest` then points at the previous one. Apps that already installed the broken pack keep it until a newer version is published, so prefer publishing a fixed version with a higher `version`.
