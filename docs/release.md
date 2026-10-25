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
- **Windows, text-to-speech (v0.5):** `flutter_tts` is not federated, and its Windows part needs ATL (`atlstr.h`) and `nuget.exe` (it downloads C++/WinRT at configure time). `app/pubspec.yaml` overrides it with `app/packages/flutter_tts_no_windows/`: the same 4.2.5 package (MIT) without the `windows:` platform and folder, so nothing is compiled for it and Windows simply has no voice (no listening exercises or pronounce buttons there). Check it after upgrading `flutter_tts`: copy the new version's `lib/`, `android/`, `ios/`, `macos/`, keep the pubspec without `windows:`, and re-apply the web patch (`flutter_tts_web.dart`: one utterance per `speak`, the previous one cancelled at once; see docs/ui.md, "Listening") and the Android patches (`4.2.5+tosk.3`, each marked "tosk patch" in `FlutterTtsPlugin.kt` and `lib/flutter_tts.dart`): `setAudioAttributes` (speech on the media stream, kept and re-applied when the plugin reconnects); the progress listener and attributes set before the calls queued during init run; a failed utterance completes the awaited `speak()` with the engine's error code (upstream never completed it); a `speak` the engine refuses (connection lost) reconnects once and then returns `ERROR` (upstream parked it until an init that never came, so every later `speak` was silent). `google_mlkit_digital_ink_recognition` has no Windows, web or desktop part (handwriting is Android and iOS only). The web build compiles both (`flutter_tts` speaks through the Web Speech API); its wasm dry run warns about JS-interop casts inside `flutter_tts_web.dart`, which don't affect the JS build.
- **Linux:** `flutter_secure_storage_linux` needs `libsecret-1-dev`, and `audioplayers_linux` needs the GStreamer development packages (`libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev`).
- **Android** release builds declare `INTERNET` (for the optional AI calls and the one-time handwriting model download), and the **macOS** entitlements include `com.apple.security.network.client`. On macOS, flutter_secure_storage may also need the Keychain Sharing capability; this is untested without a Mac.

## Android: v0.5 native parts

- **ML Kit Digital Ink** (`google_mlkit_digital_ink_recognition` 0.16.1, `com.google.mlkit:digital-ink-recognition:19.0.0`): adds `libdigitalink.so` per ABI (about 2.9 MB compressed on arm64) and pulls `ACCESS_NETWORK_STATE`/`WAKE_LOCK` (model download). The model itself (about 20 MB per language) is downloaded in the app, not shipped.
- **Text-to-speech** (`flutter_tts` 4.2.5, patched copy): the manifest's `<queries>` declares `android.intent.action.TTS_SERVICE` (Android 11+ hides TTS engines otherwise). Speech and sound effects play on the media stream (`USAGE_MEDIA`); `MainActivity` sets `volumeControlStream` to the music stream and opens the text-to-speech settings (`com.android.settings.TTS_SETTINGS`) for the "install a voice" notice.
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

## Update notice (after v0.7.6)

Sideloaded builds (Android, Windows, macOS, Linux) tell the learner about a new version; the web app tells them a new deploy is live. The app never downloads or installs anything itself. UI and tests: `docs/ui.md`, "Release features".

**Sideloaded: GitHub Releases of `linguaperta/tosk`.** At most once a day on start (and from Settings → About → Check for updates) the app asks `https://api.github.com/repos/linguaperta/tosk/releases?per_page=15` (unauthenticated, 60 requests an hour per address, 10 s timeout; offline it fails silently and the cached answer stays). It offers the newest release that is not a draft and whose version is newer than `kAppVersion`. Pre-releases count, so every preview reaches testers. What a release needs for that:

- **Tag** `preview-X.Y.Z` (previews, published as pre-releases) or `vX.Y.Z` (the release workflow's tags); a semver pre-release suffix sorts before its release (`v0.8.0-rc.1` < `v0.8.0`). Other tags (`packs-…`) are ignored. Bump the version (`pubspec.yaml` and `app_version.dart`) before tagging, or nobody is offered it.
- **Title and notes**: the notice shows the release title ("Preview 7.7 (0.7.7)") and the first three lines of the notes, so lead with what matters.
- **Assets**: Download opens the APK whose name carries the device's ABI as a separate word (`-arm64.`, `arm64-v8a`, `armeabi-v7a`/`armv7`, `x86_64`; the preview name `tosk-preview-7.7-arm64.apk` and Flutter's `app-arm64-v8a-release.apk` both work), else an APK without an ABI in its name (a universal APK), else the release page. Windows takes a `.zip`/`.msix`/`.exe` with `windows`/`win64` in the name, macOS a `.dmg`/`.zip` with `macos`, Linux a `.tar.gz`/`.AppImage`/`.deb` with `linux`. Only https links on github.com are opened.
- "Later" hides a version for a week; "Don't show again for this version" until a newer one appears. A release is also offered to installs it can't update in place: a preview signed with another key than the installed app fails to install over it (Android says the package conflicts), so keep signing previews with the upload key.

**Web: a new service worker.** The Pages workflow computes a build id from what goes into the bundle (the git trees of `app/lib`, `app/web`, `app/assets` and `app/pubspec.lock`, so docs- or test-only commits and the daily rebuild keep it), compiles it in (`--dart-define=TOSK_BUILD=…`) and stamps it into `sw.js` (`const BUILD = '__TOSK_BUILD__'`), so every deploy that changes the app changes the worker. The browser checks `sw.js` on every navigation, and `index.html` also calls `registration.update()` hourly and when the tab comes back after ten minutes or more. The new worker installs and takes over (`skipWaiting`, `clients.claim`), `index.html` dispatches `tosk-update`, and the app compares `whats_new.json` with its own build: different → "tosk was updated" with Reload. `.github/scripts/whats-new.sh` writes `whats_new.json` next to `index.html`: `version` (from `pubspec.yaml`), `build`, and `title`, `notes`, `url` of the release tagged `preview-X.Y.Z` or `vX.Y.Z` (empty while there is none; the daily run fills them in). After the reload, a one-time "What's new in X.Y.Z" sheet shows those notes. Local builds keep the placeholder and no `whats_new.json`, so they never offer a reload.

Checked end to end on 25 October 2026: a release web build (`--dart-define=TOSK_BUILD=b1`, `sw.js` stamped, a `whats_new.json`) served at `/tosk/` like Pages, in headless Edge driven over the DevTools protocol. An update check with an unchanged `sw.js` changed nothing; after rewriting `sw.js` and `whats_new.json` with a new build, `registration.update()` installed the new worker, `tosk-update` fired, the app logged `[update] build b2 (0.7.6) is live: offering a reload` and showed the notice (`docs/screenshots/release-features/10-web-edge-reload-dark.png`).

## Reminders on Android 13+ (audit, after v0.7.6)

How the daily reminder (`reminders/reminder_backend.dart`, flutter_local_notifications 22.3.2) behaves on current Android, checked against the plugin's source:

| Area | Behaviour |
| --- | --- |
| `POST_NOTIFICATIONS` (Android 13+) | Declared in the manifest; requested only when the reminder is switched on (or its time set while notifications are off), after a one-line explanation in the app. Refused: the reminder stays on with "Notifications are off for tosk — Open settings" (the app's notification settings, `Settings.ACTION_APP_NOTIFICATION_SETTINGS`, through the `tosk/device` channel). Checked again on every resume (`areNotificationsEnabled`), so a change in the system settings shows at once. After two refusals Android no longer shows its dialog; the request then returns false at once and the settings link is the way. Android 12 and older: allowed unless turned off in the settings, which the same check sees. |
| Exact alarms (`SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`) | Not used and not declared. Reminders are inexact (`AndroidScheduleMode.inexactAllowWhileIdle` = `AlarmManager.setAndAllowWhileIdle`): no permission on Android 12–14 (where `SCHEDULE_EXACT_ALARM` is denied by default from 14, and `USE_EXACT_ALARM` is for alarm-clock and calendar apps under Play policy). The delivery window is the system's (usually minutes, longer on some vendors' battery savers), which suits "practice today". |
| Doze | `setAndAllowWhileIdle` fires during Doze (at most about once per 9 minutes per app, which one daily reminder never hits). App standby buckets can delay it further for an app not opened for days; the plan only covers 7 days anyway. |
| Channel | `daily_reminder` ("Daily reminder", default importance), created at plugin init, so it is listed in the system settings before the first reminder. Category `reminder`. The small icon is the monochrome launcher drawable (`@drawable/ic_launcher_monochrome`, kept from resource shrinking by `res/raw/keep.xml`); the colour launcher icon used before showed as a filled blob. |
| Reboot and app update | The plugin's `ScheduledNotificationBootReceiver` (manifest; `RECEIVE_BOOT_COMPLETED`) re-schedules the stored reminders on `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED` and the quick-boot actions. |
| Time zone and clock changes | Reminders are absolute UTC instants computed from the local wall clock, so after a time-zone change they still fire at the old instant until the app is opened: every resume re-plans (`reminderResumeProvider`), and a changed plan replaces the scheduled ones. The plugin does not listen for `TIMEZONE_CHANGED`. |
| Web, iOS home-screen app | Not offered (a browser can't reliably wake a page at a set time); Settings shows a short note on the web. Windows and Linux: no notifications plugin, nothing shown, as before. |

Device check: no Android device was connected when this was written (2026-10-25), so the flow is covered by the widget tests with a fake backend and a debug build was only compiled. To try it on a phone that has the release app installed, don't install a debug build over it (other signing key: the install fails, and uninstalling would lose the release app's data); use a second device or an emulator, or a release-signed build.

## Publishing course packs

Course packs ship to the app without an app update: they are GitHub Release assets of the public content repo [`linguaperta/tosk-data`](https://github.com/linguaperta/tosk-data) (CC BY-SA 4.0). The app reads the release index from a **stable URL**:

```
https://github.com/linguaperta/tosk-data/releases/latest/download/index.json
```

GitHub redirects `releases/latest/download/<asset>` to that asset of the newest release (not a draft, not a pre-release), so publishing a new release is all it takes. Each course in `index.json` points at its own asset, `https://github.com/linguaperta/tosk-data/releases/download/<tag>/<id>.sqlite`, so an older index keeps working.

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
- **Restricted courses (Sarnami, `hns`) are refused, always** (`RestrictedContentError`, exit code 2): they are all rights reserved and stay local (`pipeline/pipeline/restricted.py`). The release asset list is built from the course ids you pass, never from a glob over `dist/`.
- `--repo owner/name` publishes elsewhere (a fork, for testing); the app's index URL can be changed in the debug screen (Settings → Debug → cloud icon, setting `packs.index_url`).
- To withdraw a broken release, delete it (`gh release delete <tag> --repo linguaperta/tosk-data`); `latest` then points at the previous one. Apps that already installed the broken pack keep it until a newer version is published, so prefer publishing a fixed version with a higher `version`.

## Web app and pack mirror (GitHub Pages, v0.7)

The web app (an installable PWA) and a mirror of the course packs are served from GitHub Pages, on one origin, so the browser never meets the CORS problem of GitHub's release-asset redirects:

```
https://<owner>.github.io/<repo>/                  the app (base href /<repo>/, or the PAGES_BASE_HREF variable)
https://<owner>.github.io/<repo>/packs/index.json  the catalog, with web fields
https://<owner>.github.io/<repo>/packs/<id>.sqlite.gz
```

- **Workflow:** `.github/workflows/pages.yml` (on `main`, daily and by hand) builds the web app, runs `python -m pipeline mirror --out app/build/web/packs` (downloads the latest release's packs from `tosk-data`, checks their sha256, writes `gzip -9` copies, ~19 MB to ~5 MB each, and an `index.json` with the web fields) and deploys with `actions/upload-pages-artifact` + `actions/deploy-pages`. The bundled packs (`build/web/assets/assets/courses/`, ~57 MB) are deleted before the upload: the web app never reads them (below). There is no `gh-pages` branch, so pack binaries never enter git history. It skips with a notice while Pages isn't enabled (Settings → Pages → Source: GitHub Actions). New pack releases reach the web app with the next daily run (or run the workflow by hand).
- **The app:** web builds read `packs/index.json` next to the page (`kWebPackIndexPath`, `--dart-define=TOSK_WEB_PACK_INDEX=...` to change; empty = the GitHub Releases index) and download `web_url`, checking `gz_size`/`gz_sha256`, then decompress (package:archive) and check `size`/`sha256` as for any download. Installed packs are kept in IndexedDB, so they survive reloads (memory if IndexedDB is refused, e.g. some private windows). The web app has **no bundled packs** (`AppDataOptions.packsFromWebMirror`): a first visit loads ~10 MB (main.dart.js 4.4 MB, CanvasKit 5.3 MB, fonts; less gzipped by Pages) instead of ~66 MB, and the learner downloads only the courses they pick; with nothing installed it starts on the real progress database, so the picks survive the next reload (docs/data-layer.md). Native apps keep downloading `url` from GitHub Releases.
- **Index fields** (optional, older apps ignore them; spec: `docs/pack-format.md`, section 14): `web_url` (the `.gz`, absolute or relative to the index URL), `gz_sha256`, `gz_size`. `sha256` and `size` stay those of the uncompressed `.sqlite`. Relative `url`s also resolve against the index URL from app 0.7. Written by `python -m pipeline mirror`, and by `publish --gz` / `pack publish --gz` / `pack index --gz` (which also write and upload `<id>.sqlite.gz`).
- **Offline:** `web/sw.js` is a network-first service worker: online you get the newest build, offline the last copy of everything the app loaded. `--no-web-resources-cdn` serves CanvasKit from the site so that works. The first visit loads CanvasKit, fonts and the asset manifests before the worker controls the page, so `index.html` hands the worker the page's resource URLs once it is active (and again after 15 s) and it stores the ones it hasn't (`tosk-cache-urls`; from the HTTP cache, nothing is fetched twice); before this fix the shell did not start offline after a single visit. Range requests (the sound effects) are answered from the cached full file when offline. Downloaded packs are in IndexedDB, not in the service worker cache. Flutter's own `flutter_service_worker.js` is still emitted by the build but never registered (`web/flutter_bootstrap.js`).
- **iPhone / iPad for free:** open the web app in Safari → Share → **Add to Home Screen**. It starts full screen from the icon, works offline and can sign in and sync. Text-to-speech and handwriting depend on Safari; packs are stored per home-screen app.

## Web app QA

How the web app was checked on 20 October 2026 (build 0.7.2+15 plus these fixes), and how to repeat it. Screenshots: `docs/screenshots/web/`.

**Set-up, like production.** From `app/`: `flutter build web --release --base-href /tosk/ --no-web-resources-cdn --dart-define-from-file=firebase-config.json` (the config is git-ignored; never commit it). `python -m pipeline mirror --out <dir>/packs` (from `pipeline/`) fetches the current `linguaperta/tosk-data` release. Serve both on one origin, the app at `/tosk/` and the mirror at `/tosk/packs/`, on `http://localhost:8080` (that origin is authorized for Google sign-in). A ~40-line `http.server` handler that maps the two paths and sends `Cache-Control: max-age=600` like Pages is enough; it should not fall back to `index.html` for unknown paths, because Pages doesn't either. Browsers: Edge 155 headless (`--headless=new --remote-debugging-port=…`, driven over the DevTools protocol for clicks, keys, viewport sizes, dark mode, the console, the cache and downloads) and the Claude desktop browser pane. The pane can't run the service worker or drift's shared worker ("unknown error when fetching the script"), so drift falls back to `unsafeIndexedDb` there, which works. Use real Chrome or Edge for the PWA checks.

| Area | Result | How |
| --- | --- | --- |
| First visit | pass (fixed) | It used to download all three bundled packs (57 MB) to fill the picker. Now about 10 MB load, the picker lists the mirror ("Download (5.6 MB)"), and the demo course fills the map until a download. |
| Downloads (it, nl, es) | pass | All three downloaded from `packs/*.sqlite.gz`, checked, added, and the "Where do you want to start?" prompt appears. The map switches to the real course without a reload. |
| Persistence | pass | After a reload the courses, answers, settings and starred word are still there (IndexedDB `tosk-packs`, `progress`, `tosk-sync`). |
| Deep links and refresh | pass | Hash URLs (`/tosk/#/progress/stats`, `#/play/lesson/<skill>`, `#/play/lab?skills=…&types=…`) open directly and survive a refresh. Pushed screens keep the URL of the screen below them, as go_router does. |
| Browser back | pass | Back closes a lesson and returns to the skill sheet. With the quit dialog open, back goes back one screen. |
| Map | pass (see map notes) | Wheel scrolling, zoom − / +, recenter and the action bar (Review mistakes, What's fading) work at 1280 and 1920 wide, at 390 (phone emulation, bottom navigation), and in colour, dark and black & white. |
| Exercises | pass | Checked: flashcard, multiple choice, sentence choice, match pairs, sentence builder, listen and pick (including Slower), cloze, conjugation grid, mistakes and re-asks, the intros and (?) help, and Quit. Spot the error, transform and conjugation pick went through the same lab run; the engine tests cover them. |
| Keyboard | pass (fixed) | Number keys pick options, Enter checks and continues, Esc quits. In Type mode the field had no focus, so typed letters were lost. It now takes the focus on desktops, and type, Enter, Enter, type works without the mouse, the grid included (`test/ui/typed_focus_test.dart`). |
| Word popovers | pass | Underlined words in answers and sentences open a popover with the gloss, 🔊 and ☆, and "Open in reference". |
| Summary and medals | pass / partly | The summary shows XP, level up and skill steps. The medal promotion animation isn't triggered in a short run. The widget and golden tests cover it (`medal_celebration_test.dart`, `test/qa/v071_preview.dart`). |
| Non-stop, lab, stories, reference, progress, stats, starred | pass | Lookup search, word page, star, starred list, stats charts, activity calendar and a story preview all work. The lab is now centred on wide windows like the other practice tabs. Before, its chips and Start button spanned the whole width. |
| Settings | pass | Theme (light, dark, system), black & white, reduce motion, sound, daily goal, Tap / Type (Write is hidden on the web) and listening all work. The daily reminder is hidden on the web. |
| Backup | pass | Export saves `tosk-backup-YYYYMMDD.jsonl` as a browser download. Import of that file shows its counts and reports "0 new answers (26 already here)". |
| Listening (TTS) | pass (fixed) | Voices load asynchronously, so the lookup at start-up found none and hid every 🔊 button for the session. It now waits up to 3 s (`test/speech/tts_speaker_test.dart`). Speaking twice quickly used to drop the second utterance (vendored plugin patch). Edge offers only online voices for Italian ("Microsoft Elsa Online"), so speech there needs an internet connection. |
| Sounds | pass (fixed) | All six sound effects load. Offline they are now served from the cache for the browser's range requests. |
| AI explain and chat | UI only | The provider list, key field ("On the web the key is kept in this browser's storage"), model, language and Test connection all appear. No key was entered and nothing was sent. |
| Sync UI | pass (fixed) | The Google button renders. It is now in English, like the app (it used to follow the browser language, "Inloggen met Google"), and filled black in dark mode. No sign-in was completed. |
| Handwriting, Onyx pen | hidden | Not offered on the web. |
| PWA | pass (fixed) | The manifest parses with no errors (`Page.getAppManifest`). `sw.js` registers at the `/tosk/` scope. With the server stopped, a reload after a single visit starts the app, a lesson runs and the sounds play (fixed, see Offline above). The install prompt itself can't be shown headless, and the installability criteria are met: name, 192 and 512 icons, standalone, start_url, and a worker with a fetch handler. |
| Console | clean | Only Flutter's own debug lines and `[tts] it: ready, it-IT`. |

**Still open.** The service worker is network first with no timeout, so on a very slow connection the start waits for the network. Racing the network against the cache could start an old main.dart.js against a new index, because the file names carry no hashes. main.dart.js is 4.4 MB (about 1.2 MB gzipped). `flutter build web --wasm` is blocked by JS-interop casts in `flutter_tts_web.dart` (the wasm dry-run warnings).

## CI (GitHub Actions, v0.7)

| Workflow | When | What |
| --- | --- | --- |
| `ci.yml` | every push and pull request | `flutter analyze`, `flutter test` (app and `app/packages/*`), the pipeline's pytest, the Firestore rules against the emulator (`firebase/test/`) |
| `pages.yml` | push to `main`, daily, by hand | web app + pack mirror to GitHub Pages (above) |
| `release.yml` | tags `v*`, by hand | APKs per ABI (`--split-per-abi`), a **release smoke test** (the x86_64 release APK is installed and launched on an Android 14 emulator; the job fails if logcat shows a crash or the app isn't running 25 s later, `.github/scripts/android-smoke.sh`), Windows (zip of the Release folder), an **unsigned IPA** for AltStore/SideStore (`flutter build ios --no-codesign`, `Payload/Runner.app` zipped). All as workflow artifacts; nothing is published |

Secrets (all optional; `docs/firebase-setup.md`, step 7): `FIREBASE_CONFIG_JSON` (builds with sync), `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` (APKs signed with the upload key; without them the debug key, as locally without `key.properties`). The keystore is decoded into the runner's temp folder and `key.properties` is deleted after the build.

To release: bump the version in `app/pubspec.yaml` and `app/lib/app_version.dart`, commit, `git tag v0.7.0 && git push --tags`, then download the artifacts from the workflow run. Installed apps learn about a release from its GitHub Release (tag, title, notes, assets; see "Update notice"), so attach the APKs to a release named after the version. AltStore/SideStore re-sign the IPA with a free Apple ID (7 days, then refresh).

