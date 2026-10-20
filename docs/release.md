# Building releases

All commands run from `app/` with Flutter on PATH (`C:\Users\timo\dev\flutter\bin`).

| Target | Command | Output |
| --- | --- | --- |
| Android (phone, Boox) | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| Windows | `flutter build windows --release` | `build/windows/x64/runner/Release/` |
| Web | `flutter build web --release --base-href /<repo>/ --no-web-resources-cdn` | `build/web/` (serve over HTTP; the WASM SQLite needs it). CI deploys it to GitHub Pages, see "Web app and pack mirror" |
| iOS / macOS | `flutter build ipa` / `flutter build macos` | needs a Mac with Xcode; CI builds an unsigned IPA, see "CI" |
| Linux | `flutter build linux` | needs Linux |

**Cloud sync (v0.7)** is compiled in only with the Firebase configuration: add `--dart-define-from-file=firebase-config.json` to any build or run command above (`app/firebase-config.json` is git-ignored; set it up with `docs/firebase-setup.md`). Without it the build has no account UI and is fully offline. No Firebase SDK or `google-services.json` is involved (REST API), so every platform builds the same either way; sign-in works on Android, the web and iOS (with an iOS client id), not on Windows.

Launcher icons and splash screens (v0.6) are generated from the brand kit (`app/assets/brand/icon/`): after the kit changes, run `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create` from `app/` and commit the results (see docs/ui.md, "Brand and mascot").

Plugin requirements (since v0.3):

- **Windows:** nothing beyond the standard Flutter desktop toolchain (Visual Studio Build Tools with the C++ workload; ATL is **not** needed). The pub.dev `flutter_secure_storage_windows` builds a C++ plugin against ATL (`atlstr.h`), so `app/pubspec.yaml` replaces it via `dependency_overrides` with the local pure-Dart package `app/packages/secure_storage_windows_dart/` (same package name, `dartPluginClass` only). It stores the AI key in the Windows Credential Manager through FFI, and no C++ is compiled for it: `windows/flutter/generated_plugins.cmake` lists only `audioplayers_windows`. Check that after upgrading `flutter_secure_storage`. The package has its own tests (`cd app/packages/secure_storage_windows_dart && flutter test`); `flutter test integration_test/secure_storage_test.dart -d windows` round-trips a key through the real Credential Manager.
- **Windows, text-to-speech (v0.5):** `flutter_tts` is not federated, and its Windows part needs ATL (`atlstr.h`) and `nuget.exe` (it downloads C++/WinRT at configure time). `app/pubspec.yaml` overrides it with `app/packages/flutter_tts_no_windows/`: the same 4.2.5 package (MIT) without the `windows:` platform and folder, so nothing is compiled for it and Windows simply has no voice (no listening exercises or pronounce buttons there). Check it after upgrading `flutter_tts`: copy the new version's `lib/`, `android/`, `ios/`, `macos/` and keep the pubspec without `windows:`. `google_mlkit_digital_ink_recognition` has no Windows, web or desktop part (handwriting is Android and iOS only). The web build compiles both (`flutter_tts` speaks through the Web Speech API); its wasm dry run warns about JS-interop casts inside `flutter_tts_web.dart`, which don't affect the JS build.
- **Linux:** `flutter_secure_storage_linux` needs `libsecret-1-dev`, and `audioplayers_linux` needs the GStreamer development packages (`libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev`).
- **Android** release builds declare `INTERNET` (for the optional AI calls and the one-time handwriting model download), and the **macOS** entitlements include `com.apple.security.network.client`. On macOS, flutter_secure_storage may also need the Keychain Sharing capability; this is untested without a Mac.

## Android: v0.5 native parts

- **ML Kit Digital Ink** (`google_mlkit_digital_ink_recognition` 0.16.1, `com.google.mlkit:digital-ink-recognition:19.0.0`): adds `libdigitalink.so` per ABI (about 2.9 MB compressed on arm64) and pulls `ACCESS_NETWORK_STATE`/`WAKE_LOCK` (model download). The model itself (about 20 MB per language) is downloaded in the app, not shipped.
- **Text-to-speech** (`flutter_tts` 4.2.5): the manifest's `<queries>` declares `android.intent.action.TTS_SERVICE` (Android 11+ hides TTS engines otherwise).
- **Onyx (Boox) SDK** (`com.onyx.android.sdk:onyxsdk-pen:1.5.8`, `onyxsdk-device:1.3.6`, plus `org.lsposed.hiddenapibypass:hiddenapibypass:6.1`), used only on ONYX devices (`OnyxBridge.kt`, behind a `Build.MANUFACTURER` check; every call is guarded and falls back to Flutter drawing):
  - Repository: `https://repo.boox.com/repository/maven-public/` in `android/build.gradle.kts`, limited to the groups `com.onyx.android.sdk` and `com.tencent` (the SDK's `mmkv` 1.0.19 was only ever on JCenter; Onyx mirrors it). Versions checked on 14 Oct 2026 (pen 1.5.8 and device 1.3.6 are the latest). The build needs that repository reachable on the first build (Gradle caches it after).
  - Excluded transitive dependencies: `pub.devrel:easypermissions` 0.2.1 (JCenter-only) and the old `com.android.support` libraries it drags in (they clash with AndroidX). The pen and EPD code paths don't use them.
  - `packaging.jniLibs.pickFirsts += "**/libc++_shared.so"` (the pen SDK ships its own copy). Its native libraries are arm64-v8a only (`libonyx_pen_touch_reader.so`); on other ABIs the SDK fails to open and the pad draws with Flutter.
  - `proguard-rules.pro` keeps `com.onyx.**` (it reflects into the e-reader framework) and silences four optional classes R8 reports missing (fastjson 1.x, joda-convert).
  - **Permissions:** the SDK's manifests ask for Wi-Fi state, Bluetooth, `DUMP`, `SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE` and external storage; the app's manifest removes them all (`tools:node="remove"`), and `tools:replace="android:label"` keeps the app's label. The merged manifest has `INTERNET`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `VIBRATE` (the `DUMP` that remains is WorkManager's diagnostics receiver *protection*, not a requested permission).
  - On Android 9+ the bridge calls `HiddenApiBypass.addHiddenApiExemptions("")` before using the SDK, as Onyx's sample apps do (only on ONYX devices).
- **Size:** the fat release APK is about 53 MB (53.4 MB on 14 Oct 2026). The new native libraries add about 10.8 MB of it (ML Kit's `libdigitalink.so` on three ABIs; the Onyx SDK's `libneopen_jni.so`, `libc++_shared.so`, `libmmkv.so` and pen reader), about 3.8 MB per arm64 device, plus some Java code in `classes.dex`.
- **Build memory:** `android/gradle.properties` asks for an 8 GB Gradle heap. When several builds run at once on this machine the daemon can fail to start ("insufficient memory for the Java Runtime Environment", `hs_err_pid*.log`); lower `-Xmx` locally (3 GB is enough) or build one at a time.

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

## Web app and pack mirror (GitHub Pages, v0.7)

The web app (an installable PWA) and a mirror of the course packs are served from GitHub Pages, on one origin, so the browser never meets the CORS problem of GitHub's release-asset redirects:

```
https://<owner>.github.io/<repo>/                  the app (base href /<repo>/, or the PAGES_BASE_HREF variable)
https://<owner>.github.io/<repo>/packs/index.json  the catalog, with web fields
https://<owner>.github.io/<repo>/packs/<id>.sqlite.gz
```

- **Workflow:** `.github/workflows/pages.yml` (on `main`, daily and by hand) builds the web app, runs `python -m pipeline mirror --out app/build/web/packs` (downloads the latest release's packs from `tosk-data`, checks their sha256, writes `gzip -9` copies, ~19 MB to ~5 MB each, and an `index.json` with the web fields) and deploys with `actions/upload-pages-artifact` + `actions/deploy-pages`. There is no `gh-pages` branch, so pack binaries never enter git history. It skips with a notice while Pages isn't enabled (Settings → Pages → Source: GitHub Actions). New pack releases reach the web app with the next daily run (or run the workflow by hand).
- **The app:** web builds read `packs/index.json` next to the page (`kWebPackIndexPath`, `--dart-define=TOSK_WEB_PACK_INDEX=...` to change; empty = the GitHub Releases index) and download `web_url`, checking `gz_size`/`gz_sha256`, then decompress (package:archive) and check `size`/`sha256` as for any download. Installed packs are kept in IndexedDB, so they survive reloads (memory if IndexedDB is refused, e.g. some private windows). Native apps keep downloading `url` from GitHub Releases.
- **Index fields** (optional, older apps ignore them; spec: `docs/pack-format.md`, section 14): `web_url` (the `.gz`, absolute or relative to the index URL), `gz_sha256`, `gz_size`. `sha256` and `size` stay those of the uncompressed `.sqlite`. Relative `url`s also resolve against the index URL from app 0.7. Written by `python -m pipeline mirror`, and by `publish --gz` / `pack publish --gz` / `pack index --gz` (which also write and upload `<id>.sqlite.gz`).
- **Offline:** `web/sw.js` is a network-first service worker: online you get the newest build, offline the last copy of everything the app loaded (including the bundled packs). `--no-web-resources-cdn` serves CanvasKit from the site so that works. Downloaded packs are in IndexedDB, not in the service worker cache.
- **iPhone / iPad for free:** open the web app in Safari → Share → **Add to Home Screen**. It starts full screen from the icon, works offline and can sign in and sync. Text-to-speech and handwriting depend on Safari; packs are stored per home-screen app.

## CI (GitHub Actions, v0.7)

| Workflow | When | What |
| --- | --- | --- |
| `ci.yml` | every push and pull request | `flutter analyze`, `flutter test` (app and `app/packages/*`), the pipeline's pytest, the Firestore rules against the emulator (`firebase/test/`) |
| `pages.yml` | push to `main`, daily, by hand | web app + pack mirror to GitHub Pages (above) |
| `release.yml` | tags `v*`, by hand | APKs per ABI (`--split-per-abi`), a **release smoke test** (the x86_64 release APK is installed and launched on an Android 14 emulator; the job fails if logcat shows a crash or the app isn't running 25 s later, `.github/scripts/android-smoke.sh`), Windows (zip of the Release folder), an **unsigned IPA** for AltStore/SideStore (`flutter build ios --no-codesign`, `Payload/Runner.app` zipped). All as workflow artifacts; nothing is published |

Secrets (all optional; `docs/firebase-setup.md`, step 7): `FIREBASE_CONFIG_JSON` (builds with sync), `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` (APKs signed with the upload key; without them the debug key, as locally without `key.properties`). The keystore is decoded into the runner's temp folder and `key.properties` is deleted after the build.

To release: bump the version in `app/pubspec.yaml` and `app/lib/app_version.dart`, commit, `git tag v0.7.0 && git push --tags`, then download the artifacts from the workflow run. AltStore/SideStore re-sign the IPA with a free Apple ID (7 days, then refresh).

