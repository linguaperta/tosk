# Data layer (`app/lib/data/`)

The data layer opens course packs, records answers, schedules facets with FSRS, and computes skill statistics. Everything except the Flutter bootstrap is pure Dart, so engine and progression code, tests and `dart run` tools can use it directly.

## Overview

```
data/
  app_data.dart          AppData: the one object the UI gets (pure Dart)
  bootstrap.dart         openAppData(): Flutter wiring for the current platform
  course/                compiled course DB -> InMemoryCourseData / CourseRepo
  progress/              progress DB (drift), ProgressRepo, InMemoryProgressStore
  fsrs/                  FsrsScheduler (FSRS-6, port of py-fsrs 6.3.2, no fuzz)
  stats/                 SkillStats, SkillStatsService
  packs/                 LocalPackSource, PackFileStore, AssetBundlePacks, GitHubPackSource (downloads)
  platform/              conditional imports: native (ffi, isolates) vs web (WASM)
  sync/                  review-log JSON lines (codec), progress backup (export/import)
core/interfaces/packs.dart   PackSource, PackInfo, PackData (PackFile | PackBytes), PackHandle
core/interfaces/remote_packs.dart   RemotePackSource, RemoteIndex, RemotePack, CourseOffer, combineOffers
core/interfaces/sync.dart    SyncBackend (cloud sync contract), NullSyncBackend, SyncedEvent, EventBatch, SyncCursor
lib/sync/                    cloud sync (v0.7): engine, Firebase over REST, local bookkeeping, service, providers
ui/debug/debug_screen.dart   debug screen; run it with `flutter run -t lib/main_debug.dart`
```

Only these files import Flutter: `bootstrap.dart`, `packs/asset_bundle_packs.dart` and `progress/progress_connection_*.dart`.

### Using it from the UI

```dart
final app = await openAppData();                    // e.g. in a Riverpod FutureProvider
final packs = await app.availableCourses();         // List<PackInfo>
final course = await app.openCourse('it');          // CourseRepo implements CourseData (cached)
final stats = await app.stats.forCourse(course);    // Map<skillId, SkillStats>
await app.progress.record(event);                   // ProgressStore.record
```

Tests and other agents can use `InMemoryProgressStore` (pure Dart, same semantics as `ProgressRepo`) and the fixtures in `app/test/fixtures/`:

- `course_fixture.dart`: `fixtureCourse()`, `fixtureCourseRepo()`, `fixtureCourseBytes()`, `writeFixtureCourseFile()` and `openFixtureCourseDb()`. These build a small Italian course from `schema/course_db.sql`: greetings and food vocab, essere/avere and regular -are presente with full tables, an article skill, aligned sentences, and notes in English and Dutch.
- `sample_log.dart`: `sampleLog()`, a seeded random review log.
- `synthetic_course.dart`: a large pack for load-time tests.

`dart run tool/build_fixture_pack.dart out.sqlite` writes the fixture as a pack file, which you can add from the debug screen's + button.

## Course packs

- **Loading.** `loadCourseFromSqlite(CommonDatabase)` (`course/course_loader.dart`) reads every table with one `SELECT` and decodes the JSON columns. It returns an `InMemoryCourseData`; `loadCourseRepoFromSqlite` returns a `CourseRepo`, which adds raw meta, counts and load time. A 20 MB synthetic pack loads in about 0.3 s.
- **Native.** `loadCourseFile(path)` (`course/course_file.dart`) opens the file with `OpenMode.readOnly`. In the app, `platform.loadCoursePack` runs this on a background isolate.
- **Web and bytes.** `loadCourseRepoFromBytes(sqlite, bytes)` (`course/course_bytes.dart`) puts the bytes in an `InMemoryFileSystem` VFS and opens it read-only. On the web, `sqlite` is `WasmSqlite3` loaded from `web/sqlite3.wasm`. Natively it is the FFI `sqlite3`, which is how the web path is tested.
- **Topic trees** (schema minor 3). With the `topics` and `topic_units` tables present, the loader fills `CourseData.topics` (`Topic`: id, ord, title, short title, description, icon, anchor) and `Unit.topic` (null for the main tree; a `topic_units` row naming an unknown topic is ignored). Packs without the tables load with no topics. `CourseTrees.of(course)` (`core/trees.dart`, cached per course) splits `units` and `skills` into the main tree and each topic (`mainUnits`, `unitsOf(tree)`, `skillsOf(tree)`, `treeOf(skill)`, `byAnchor`, and for the "needs …" note of a locked topic skill `mainRequirements(skill)`, its main-tree prerequisites in course order, and `mainUnitNumber(skill)`); a topic without skills is left out. Progress, stats and progression stay per course: a topic is part of its course family.
- **Validation.** `meta` must contain `schema_version`, `course_id`, `version`, `title`, `target`, `persons` and `tenses`. The major version of `schema_version` must equal `kCourseDbSchemaVersion` in `course/course_schema.dart`, so `'1.1'` loads and `'2'` is refused. Errors throw `CourseFormatException`.
- **Course ids** name files and storage keys (`courses/{id}.sqlite`, the IndexedDB key), so every id that comes from outside (a pack's `meta.course_id`, an index entry, a `packs.json` key, a file in `courses/`) must pass `isValidCourseId` (`core/course_id.dart`): a lower-case ASCII letter, then up to 39 of `a-z 0-9 _ -`, optionally one expansion part after a single dot (`it.cucina`, docs/extensions.md); no separators, no `..`, no Windows device names. Every `PackFileStore` refuses other ids, and `NativePackFileStore` also checks that the path stays directly inside `courses/` before any write, stage or delete. Tests: `test/data/course_id_security_test.dart`.
- **Untrusted packs.** Packs can come from anyone (a file, a custom index), so every connection runs `PRAGMA trusted_schema = OFF` and `guardCourseDb` refuses a pack whose schema has anything but tables and indexes (no views, triggers or virtual tables), before any course table is read: a view posing as `skills` could otherwise run a query that never ends. Packs from outside the app (added from a file, copied into `courses/`, downloaded) also pass `PRAGMA quick_check` (`LocalPackSource.readUntrustedMeta`); bundled packs skip it to keep start-up fast. Packs over 500 MB (`kMaxPackBytes`) are refused. Tests: `test/data/malicious_pack_test.dart`.

### Pack sources

`LocalPackSource` implements `PackSource`:

- **Bundled packs.** These are `assets/courses/*.sqlite`, found through the AssetManifest. On first use they are copied into the installed-pack store. A pack is copied again when its bundled `meta.version` is a newer semver than the installed copy, for example after an app update. A bundled pack that fails validation is skipped with a warning. **Not on the web** (after 0.7.2): web builds with the pack mirror (`AppDataOptions.packsFromWebMirror`, `usesWebPackMirror`) use `NoBundledPacks`, so a first visit no longer downloads every bundled pack (~57 MB for it, nl and es, read again at every start just to list them); the learner downloads the gzipped copy of each course they pick (~5 MB). With nothing installed the web app still starts on the real progress database (the demo course fills the map, unseeded), so the courses picked and the first answers are kept at the next reload; natively, no packs still means the separate demo database. Packs installed from the bundle by an older web build stay in IndexedDB. Tests: `test/app/boot_test.dart`.
- **Installed-pack store.** Natively this is `{app support dir}/courses/{id}.sqlite` plus a `packs.json` manifest. It uses the app support folder rather than Documents, so it stays out of the user's Documents folder on desktop. You can override the folder with `AppDataOptions.dataDirectory`. On the web (v0.7) packs live in IndexedDB (`BlobPackFileStore` over `IdbBlobStore`, database `tosk-packs`), so downloads survive reloads; if IndexedDB fails (`FallbackBlobStore`) they live in memory for the session.
- **Packs copied in by hand.** A `{id}.sqlite` file placed in the store's `courses/` folder is found when the packs are first listed, validated and registered with origin `local` (a misnamed or invalid file is skipped with a warning). A replaced file is re-read on the next start and a deleted one disappears from the list. This is how the locally built Sarnami pack, which may never be bundled, gets onto a desktop machine (`python -m pipeline build hns --desktop`, docs/private-importers.md). On Windows the folder is `%APPDATA%\linguaperta\tosk\courses`.
- **`install(PackFile | PackBytes)`.** Used by the course picker's "Add course from file…" and the debug screen. It validates the pack, then replaces the installed pack with the same course id, with origin `local`.
- **`remove(id)`.** Deletes a `local` pack. A bundled pack for that course comes back the next time packs are listed, and bundled packs themselves can't be removed.

### Downloads: `GitHubPackSource` (`packs/github_pack_source.dart`, v0.4)

`GitHubPackSource` implements `PackSource` (delegating to its `LocalPackSource`, so `available()` is always what opens offline) and the core `RemotePackSource` (`core/interfaces/remote_packs.dart`). `openAppData` wires it when `AppDataOptions.appVersion` is set (`main.dart` passes `kAppVersion`); `AppData.remote` exposes it and `AppData.downloadPack` downloads and evicts the cached course.

- **Index.** `fetchIndex()` reads `index.json` from `kDefaultPackIndexUrl` = `https://github.com/linguaperta/tosk-data/releases/latest/download/index.json` (GitHub's redirect to the newest release's asset; see docs/release.md, "Publishing course packs"), or from a `url` (the debug setting `packs.index_url`). Redirects are followed by hand natively (`followRedirects: false`, up to 5 hops: `releases/latest` → `releases/download/<tag>` → object storage), and by the browser on the web. Format (`index_version` 1, written by `pipeline/pipeline/publish.py`):

  ```json
  {"index_version": 1, "generated_at": "2026-10-14T10:00:00Z", "tag": "packs-20261014",
   "courses": [{"id": "it", "version": "1.1.0", "title": {"en": "Italian", "nl": "Italiaans"},
     "description": {"en": "..."}, "target": "it", "sources": ["en", "nl"], "unverified": false,
     "schema_version": "1", "min_app_version": "0.3.0", "sha256": "…", "size": 17199104,
     "url": "https://github.com/linguaperta/tosk-data/releases/download/packs-20261014/it.sqlite"}]}
  ```

  A higher `index_version` is refused ("needs a newer app"); unknown fields are ignored.
- **Offers.** `combineOffers(installed, index, appVersion, schemaMajor)` gives one `CourseOffer` per course: `installed`, `updateAvailable` (installed, the index has a newer semver the app can use), `downloadable`, or `needsAppUpdate` (the schema major differs from `kCourseDbSchemaVersion`, or `min_app_version` is newer than the app). An installed course whose newer version needs a newer app just stays `installed`.
- **Download.** `download(pack, onProgress:, cancel:)` refuses incompatible packs before any request, then streams the asset into `PackFileStore.stage(id)` (natively `courses/{id}.sqlite.download`; memory on the web), hashing as it goes. It checks the size (a body larger than announced is cut off at once; a short one is "incomplete"), the sha256, and then `LocalPackSource.installStaged` validates the file's meta (course id, version, schema major) and swaps it in: `{id}.sqlite` → `{id}.sqlite.bak`, staged → `{id}.sqlite` (two renames; Windows can't rename over a file), opens the new file with `verify` (the app loads it fully, `platform.loadCoursePack`), and only then drops the backup and writes `packs.json` with origin `remote`. If opening fails, the backup is renamed back (rollback). A crash at any step is repaired on the next start (`NativePackFileStore` restores a leftover `.bak` and deletes `.download` files once per store), and since `packs.json` is written last, folder and manifest always agree.
- **Transport and sizes.** Indexes and packs are fetched over `https` only, checked again on every redirect hop; plain `http` is accepted only for loopback (development) and, on the web, the page's own origin (`isAllowedPackUrl`, `core/net_policy.dart`). `index.json` is read up to 1 MB (`kMaxIndexBytes`), an index entry with a `size` or `gz_size` above 500 MB is refused, a download stops as soon as it passes the announced size, and the web `.gz` is decompressed with a cap at the pack's `size` (a small `.gz` can't expand to gigabytes). Tests: `test/data/pack_transport_security_test.dart`.
- **Errors** are `PackDownloadException(kind, message)` with kinds `network` (no connection, timeouts of 30 s per connect/idle, a dropped connection), `http` (404, 5xx), `corrupt` (size, checksum, wrong course/version, unreadable or newer-schema file, failed open), `incompatible` and `cancelled` (`DownloadCancel.cancel()`, which also aborts the request through `http.AbortableRequest`). Messages are short and polite; installed packs are never touched by a failure.
- **Progress is never touched.** Item ids are permanent, so a newer pack keeps every id; facets of items a pack drops stay in the log and states but are no longer scheduled. Every session builder, the stats, mistakes and progression iterate the course's own facets, so orphaned states are ignored (`test/engine/removed_items_test.dart`).
- **Bundled packs stay the fallback.** A downloaded pack wins while its version is at least the bundled one; after an app update with a newer bundled pack, the bundled pack is installed again. Removing a downloaded course (`remove`) falls back to the bundled pack.
- **Web (v0.7).** The web build reads the catalog from the same-origin GitHub Pages mirror (`packs/index.json` next to the page) and downloads each course's gzipped copy (`web_url`, checked against `gz_size`/`gz_sha256`, decompressed with package:archive, then checked against `size`/`sha256`). Packs persist in IndexedDB. Relative `url`/`web_url`s resolve against the index URL (`RemoteIndex.resolvedAgainst`). See docs/release.md, "Web app and pack mirror". Tests: `test/data/web_packs_test.dart`.

Tests: `test/data/github_pack_source_test.dart` (a fake GitHub with the release URLs and redirects via `MockClient`, plus a real local `HttpServer` with a dropped connection: index, offers, update with progress, 404, corrupted checksum, truncated, oversized, newer schema/app, wrong course/version in the file, network loss, cancel, rollback when the new pack fails to open, crash recovery, the in-memory store, `AppData.downloadPack` keeping the review log).

## Progress database

The progress database is drift, defined in `progress/progress_db.dart` with generated code in `progress_db.g.dart`. Times are stored as INTEGER UTC epoch milliseconds, so stored states round-trip exactly.

**Android backup is off** (`android:allowBackup="false"`, with `res/xml/data_extraction_rules.xml` and `backup_rules.xml` excluding every domain), so neither Google's cloud backup nor device-to-device transfer copies the progress database, the AI key or the sync session. Progress moves between devices through cloud sync or a backup file (below).

| Table | Contents |
| --- | --- |
| `review_log` | Append-only and the source of truth. Columns: id (UUID PK), facet_id, at, rating, exercise_type, input_mode, response_ms, correct, answer, session_id, mode. Indexes: (facet_id, at) and (at). |
| `facet_state` | Derived from the log. Columns: facet_id PK, stability, difficulty, due (indexed), last_review, reps, lapses, phase, step. |
| `mistakes` | The `MistakeRecord` fields. Indexes: at and facet_id. |
| `settings` | Key/value pairs. |
| `ai_explanations` | Schema v2. Cached AI explanations. Columns: fingerprint, given and lang (together the primary key), body, facet_id, provider, model, created_at. |
| `flags` | Schema v2. Flagged exercises: a full exercise snapshot (JSON), the answers, the reasons, the comment, the AI verdict, and the app and pack versions. Index on created_at. The format and the export are in `docs/feedback.md`. |
| `bookmarks` | Schema v3 (v0.4). Starred words, sentences and exercises: course_id, kind (`word` / `sentence` / `exercise`) and ref_id (item id, sentence id or exercise hash) as the primary key; at (last change, UTC ms), removed (a tombstone of an unstarred bookmark), label, detail, facet_id, exercise_json (the exercise snapshot). Index on (course_id, at). Merge rules: `docs/progression.md`, "Bookmarks". |

`DriftFeedbackStore` (`progress/feedback_store.dart`, exposed as `AppData.feedback`) implements the core `ExplanationCache` and `FlagStore` over these two tables. `InMemoryFeedbackStore` has the same semantics, for tests and the defaults. `DriftBookmarkRepo` (`progress/bookmarks.dart`, `AppData.bookmarks`) implements the core `BookmarkRepo` over `bookmarks`; `InMemoryBookmarkRepo` is its in-memory twin.

`ProgressRepo` (`progress/progress_repo.dart`) implements both `ProgressStore` and `EventImporter`:

- **`record(event)`.** In one transaction it normalizes `at` to UTC milliseconds, appends the event, and updates the facet's state with the `Scheduler`. Recording an event id that is already in the log does nothing. If the event is older than the facet's latest event, which happens with sync merges or imports, that facet is replayed from its log instead.
- **Ordering rule.** Events are always applied in `(at, id)` order (`progress/replay.dart`). Incremental updates therefore always equal a full replay.
- **`rebuildStates()`.** Replays the whole log and rewrites `facet_state`. A test checks that this reproduces the stored states exactly (`==`) after out-of-order insertion of 600 events.
- **`importEvents(events)`.** Merges events by id and replays only the facets those events touch. Sync is built on it.
- **Extras.** `dueStates(now:, courseId:, limit:)` and `logCount()`.
- **Course filter.** `allStates(courseId: 'it')` filters with an index-friendly range, `facet_id >= 'it:' AND facet_id < 'it;'`.

The connection comes from `progress/progress_connection.dart`:

- **Native.** Uses `drift_flutter` with `{support dir}/progress.sqlite`.
- **Web.** Uses drift WASM with `web/sqlite3.wasm` and `web/drift_worker.js`. It tries the best storage the browser offers first (OPFS, then shared IndexedDB, then IndexedDB in a dedicated worker). If that storage fails to open, it falls back to the next one, ending with an in-memory database and a warning in the console. Some embedded webviews can't fetch from shared workers, which is why the fallback exists.

### Adding a migration

1. Change the tables in `progress_db.dart`.
2. Bump `ProgressDb.currentSchemaVersion`.
3. Add a step to `onUpgrade` in `migration`, one `if (from < N)` block per version, for example `await m.addColumn(mistakes, mistakes.newColumn);`.
4. Run `dart run build_runner build` to regenerate `progress_db.g.dart`.
5. Run `dart run drift_dev make-migrations` from `app/`. This dumps `drift_schemas/progress/drift_schema_vN.json` and generates migration test scaffolding in `test/drift/progress/`. The options are in `app/build.yaml`. Commit the schema dump and add the generated tests. The command also writes a `progress_db.steps.dart` helper for `stepByStep` migrations. Delete it: this database writes its steps by hand in `onUpgrade`. The v1 → v2 step (two new tables) and the v2 → v3 step (the `bookmarks` table and its index, one self-contained `if (from < 3)` block) are tested in `test/drift/progress/migration_test.dart`, including data integrity.
6. Run `flutter test`.

Rules for migrations:

- `review_log` must never lose rows.
- `facet_state` is derived data, so a step may drop and recreate it and then call `rebuildStates()`.
- A database from a newer app version is refused: drift calls `onUpgrade` with `from > to`, and the migration throws.

Changing FSRS parameters or scheduler behaviour needs no schema migration. Call `rebuildStates()` once so that stored states match the new scheduler.

## FSRS

`FsrsScheduler` (`fsrs/fsrs_scheduler.dart`) implements `Scheduler` with these settings:

- FSRS-6 with the 21 default parameters of py-fsrs 6.3.2
- Desired retention 0.9
- Learning steps of 1 minute and 10 minutes, and a relearning step of 10 minutes
- Maximum interval of 36500 days
- No fuzz

Why it's a port:

- **The pub.dev package doesn't match.** `fsrs` 2.0.1 ships older default parameters and rounds with Dart semantics, so it doesn't reproduce py-fsrs's values.
- **Rounding and time math follow Python.** The port copies Python's half-to-even `round`, `timedelta.days` flooring, and `e ** x` computed with `pow`.
- **Retrievability uses whole elapsed days.** This is how py-fsrs computes it.
- **Counters come from the Anki convention.** `reps` counts reviews, and `lapses` counts Again ratings given in the review phase. py-fsrs 6 tracks neither.

The reference vectors are in `test/fixtures/fsrs_vectors.json`: 52 sequences and 569 reviews, generated by `tool/fsrs_reference/gen_fsrs_vectors.py` from py-fsrs with fuzzing disabled. To regenerate them, run the script with `pip install fsrs` in a scratch virtualenv; the steps are in the script's docstring. Tests check stability and difficulty within 1e-6, due times exactly, and retrievability.

## Skill statistics

`SkillStatsService(store, scheduler)`, in `stats/skill_stats.dart`, has two calls:

- `forSkill(course, skillId)` runs one query, for the states of that skill's facets.
- `forCourse(course)` runs one query, `allStates(courseId)`, and computes every skill in Dart. Facets shared between skills are evaluated once.

Each `SkillStats` has these fields:

| Field | Meaning |
| --- | --- |
| `itemCount`, `facetCount` | Size of the skill. |
| `strength` | Mean predicted recall over the skill's facets; unreviewed facets count as 0. |
| `lastPracticed` | The latest `last_review` among the skill's facets. |
| `learnedCount` | Items whose facets in this skill have all left the learning phase (the bronze criterion). |
| `reviewedFacetCount`, `learnedFacetCount` | Facets with at least one review, and facets that left the learning phase. |
| `dueCount` | Reviewed facets that are due now. |
| `minRecall`, `minStability` | Lowest recall and stability across the facets, for the silver and gold checks. |

## Cloud sync (v0.7, `lib/sync/`)

Accounts and sync with Firebase (Google sign-in, Firestore), free tier. Only when the build has a configuration (`--dart-define-from-file=firebase-config.json`, `sync/sync_config.dart`) and the platform can sign in (Android, web, iOS with an iOS client id); otherwise nothing of it exists at run time. Setup: `docs/firebase-setup.md`.

| File | Role |
| --- | --- |
| `core/interfaces/sync.dart` | `SyncBackend`: push/pull event batches and settings with server-time cursors, `deleteAll`; `NullSyncBackend` |
| `sync/sync_engine.dart` | the merge algorithm (pure Dart), `EventOffsets` |
| `sync/sync_store.dart` | local bookkeeping in its own `sync.sqlite` (`SyncDb`, raw SQL, no generated code; web: `tosk-sync`; schema v2 adds the `outbox` table), `InMemorySyncStore` |
| `sync/report_outbox.dart` | reports for the developer (flags, feedback, crash reports) waiting to upload: `ReportOutbox` (batches, backoff), `OutboxStore` (`DriftOutboxStore` on `sync.sqlite`, in memory), `ReportSender`; docs/feedback.md, "Reports to the developer" |
| `sync/firebase_auth.dart`, `sync/firestore_backend.dart` | Firebase Auth and Firestore over REST (package:http; no native Firebase SDKs, so no `google-services.json` and Windows keeps building) |
| `sync/google_identity.dart` | Google ID tokens via google_sign_in (Android Credential Manager, iOS SDK, the web's Google button) |
| `sync/sync_service.dart` | sign-in/out (single-flight), the persisted session (refresh token in secure storage), triggers, one sync at a time, status |
| `sync/sync_errors.dart` | Identity Toolkit/Firestore errors → the sentences the user reads; which sign-in errors are retried |
| `sync/sync_bootstrap.dart`, `sync/sync_providers.dart` | wiring (`bootApp` → `AppBoot.sync`), Riverpod; `ui/settings/sync_section.dart` is Settings → Account & sync |
| `sync/fake_sync_backend.dart` | in-memory server with a clock and an offline switch, for tests |

**Review log: union by event id.** Facet states are recomputed after a merge (`rebuildStates()`), so there are no conflicts. One `SyncEngine.sync()`:

1. Pull the batches written since the last run (cursor = server time + document id, re-reading a 2-minute overlap) and `importEvents` them. **Clock skew:** an event dated more than 5 minutes after its batch's server time is clamped to that time; every device clamps the same way.
2. `rebuildStates()` if anything was new.
3. Push the **upload queue**: the review log after the last uploaded position (`SequencedLog.eventsAfter`, the SQLite `rowid` of `review_log`; never `VACUUM` the progress DB), minus events the account already has, in batches of up to 400 events per Firestore document. A batch id is a hash of its event ids, so a retried upload overwrites itself; the position moves only after a batch is stored. Offline, answers simply wait in the log (`SyncEngine.pending()`).
4. Settings, **last writer wins** per key (`ui/settings/synced_settings.dart` lists the synced keys; display, reduced motion, reminders, e-reader switches, AI and pack bookkeeping stay on the device), on the change time (noted through `ProgressRepo.listeners`, clamped to the server time) with the device id as tie-break. A device's first sync with an account **joins** it: the account's values win, except "my courses" and seen intros, which become the union.

**Time zones.** Each event travels with the UTC offset it was recorded with (`SyncedEvent.utcOffsetMinutes`, noted locally in `event_meta` as answers are recorded). `EventOffsets` maps event times to these offsets and the app's `calendarProvider` uses it, so streaks, the heatmap and the daily goal count the days the learner lived, whatever zone the viewing device is in. Events recorded before sync existed use the device's rules, as before.

**Triggers** (`SyncService`): a few seconds after start, a minute after the last answer, two seconds after a backup import that added answers or settings (`localDataChanged`), on app pause and resume, and "Sync now". After a sync that brought answers or settings, the progress revision is bumped and the settings providers reload.

**One at a time.** *Sign-in* is single-flight: button taps while a sign-in runs join it, and a Google ID token arriving on `GoogleIdentity.idTokens` is ignored while a sign-in runs, once signed in, or when it is the token just used. (v0.7.2 bug: google_sign_in's `authenticate()` returns the account *and* reports it on `authenticationEvents`, which `PluginGoogleIdentity` forwarded on every platform, so an Android sign-in sent two `accounts:signInWithIdp` calls at once; for a new account the loser got `DUPLICATE_RAW_ID`. The events are now forwarded only on the web, where Google's button is the only way in.) A `signInWithIdp` failure that a retry fixes (`isRetryableSignIn`: `DUPLICATE_RAW_ID` and the like, a race with a sign-in that is creating the same account, or HTTP 5xx) is retried once after 1.5 s, showing "Sign-in hiccup, trying again…" as a notice, not an error; the retry signs in to the account just created. The first sync starts only after the session is stored and attached; "Sync now" before that waits for the sign-in. *Syncs* never overlap: a trigger while one runs queues one more run after it, shared by every trigger that arrives meanwhile, so answers recorded or a backup imported during a run (e.g. right after the first sign-in) are uploaded by that next run and nothing is uploaded twice. A run that ends after a sign-out leaves the status alone; "Delete my cloud data" waits for the running sync.

**Errors in words** (`sync/sync_errors.dart`). Identity Toolkit codes, Firestore statuses and exceptions go to the log (`[sync] …`); the status (`SyncStatus.lastError`) holds one of a few sentences (`SyncMessages`): "Sign-in hiccup", "Couldn't reach the server", "Sign-in expired, please sign in again", or a generic "didn't work" for sign-in or sync. Being offline is not an error (`SyncStatus.offline`).

**Firestore layout and rules:** `users/{uid}/batches/{batchId}` (`v`, `dev`, `n`, `events` as JSON lines with `off`, `up` = server time) and `users/{uid}/settings/{key}` (`k`, `v`, `t`, `dev`, `up`). `firebase/firestore.rules` lets a user touch only their own tree, checks the shape and requires `up == request.time`; `firebase/test/rules.test.mjs` tests it on the emulator (CI). A 200-answer day is about 10 writes.

**Caps** (after v0.7.6, against quota abuse): every write needs a Google sign-in (`sign_in_provider == 'google.com'`); batches have `v == 1`, `1 ≤ n ≤ 400`, `dev` ≤ 64 characters, `events` ≤ 250,000 characters and an id of ≤ 64 `[A-Za-z0-9_-]`; settings a key of ≤ 100 (document id ≤ 200 `[A-Za-z0-9._%-]`), a value of ≤ 10,000 and `dev` ≤ 64. The app keeps under them: `FirestoreSyncBackend.pushEvents` splits a batch whose event lines pass 200,000 characters over `batchId`, `batchId-2`, … (the same split on a retry) and cuts typed answers at 2,000 characters.

**Reports for the developer** (after v0.7.6) go to `users/{uid}/feedback/{id}` and `users/{uid}/crashes/{id}`: created by the user (fixed shape and size limits), readable and deletable only by them, never changed; the owner reads all of them with admin credentials (`python -m pipeline feedback pull`, collection-group queries). They wait in the `outbox` of `sync.sqlite` and are uploaded after each sync, separately from the answers (their own batching and backoff; their failures are never sync errors). Details, fields and limits: docs/feedback.md, "Reports to the developer".

**Delete my cloud data** deletes every document of the user's tree (batches, settings, sent reports) and the Firebase account, then signs out; local progress stays, unsent reports are dropped. Firebase deletes an account only after a recent sign-in (`CREDENTIAL_TOO_OLD_LOGIN_AGAIN`): the service then asks for a fresh Google sign-in where the app can start one (Android, iOS) and retries; on the web, or if that is cancelled or fails, it returns `CloudDeleteOutcome.accountKept` and the status says the data is gone but the account remains ("sign in again and choose Delete my cloud data once more"). It never reports success while the account remains. **Sign out** keeps both copies.

Tests: `test/sync/sync_engine_test.dart` (two devices, duplicates, idempotency, offline queue, lost acknowledgements, out-of-order and override events, clock skew, the drift/SQLite path, account switch, streaks across time zones, settings LWW and joining, the free-tier budget), `test/sync/firestore_backend_test.dart` (the REST clients against a fake Firestore/Auth API), `test/sync/sync_service_test.dart`, `test/sync/sync_races_test.dart` (concurrent taps and token reports → one `signInWithIdp`, against a fake Identity Toolkit that answers a concurrent create with `DUPLICATE_RAW_ID`; the retry; serialized, coalesced syncs and an import during the first sync), `test/sync/sync_errors_test.dart` (the message mapping), `test/sync/report_outbox_test.dart` (the outbox: batches, offline, backoff, a rejected report, the cap, the SQLite table and the v1 → v2 migration, the report builders, the Firestore request, the size-split batches, `SyncService` only signed in, after a sync, a refused upload that isn't a sync error, delete with sent reports, the re-authentication and the "account remains" outcome), `test/ui/sync_section_test.dart`.

### Progress backup (`sync/progress_backup.dart`, Settings → Backup)

Independent of cloud sync, and still the way to move progress without an account. One JSON-lines file, format `tosk-backup/1`: a header line (`format`, `exported_at`, `app`, counts), the review log exactly as `encodeReviewLogJsonl` writes it, then `{"kind":"mistake",…}` per mistake, `{"kind":"setting","key","value"}` per setting and (v0.4) `{"kind":"bookmark","course","k","id","at",…}` per bookmark, tombstones included (`exportBackup(bookmarks:)`), (stores that implement `SettingsLister`, `ProgressRepo` and `InMemoryProgressStore`, list every setting). Flags have their own export (docs/feedback.md). A plain review-log file imports too, and unknown `kind`s are skipped.

**Import merges, never deletes:** events are a union by id (`importEvents`, idempotent), then `rebuildStates()`; mistakes are added when their id is new; settings only fill keys this device lacks, except "my courses" (`courses.added`), which is a union. A backup file may come from someone else, so **only learner preferences are imported**: `isImportableSetting` allows the keys in `kImportableSettings` (course, languages, lesson and display preferences, goals, seen intros) and the per-course recent-sentence memory, and skips everything else: device-only keys (reminder, e-reader switches, the course index URL), unknown keys, and `ai.*` (provider, model and base URL decide where the AI key is sent; they are not exported either). A new preference becomes importable once it is added to `kImportableSettings` (a test checks that every `SettingKeys.all` and synced key is). `chat.*` settings (AI conversations) are neither exported nor imported. Bookmarks merge last-writer-wins per bookmark (`importBackup(bookmarks:)`, `BackupImportReport.bookmarksChanged`); older apps skip the unknown line kind, so the format tag stays `/1`. `importBackup` returns the counts the UI shows. Tests: `test/data/progress_backup_test.dart` (round trip between two on-disk databases, a duplicate import, the layout, bad files).

## Web assets

`app/web/sqlite3.wasm` comes from the `sqlite3-3.7.1` release of simolus3/sqlite3.dart, matching the resolved `sqlite3` package. `app/web/drift_worker.js` comes from the `drift-2.35.2` release of simolus3/drift.

When `sqlite3` or `drift` is upgraded in `pubspec.lock`, download the matching files again from:

```
https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-<version>/sqlite3.wasm
https://github.com/simolus3/drift/releases/download/drift-<version>/drift_worker.js
```

`flutter build web -t lib/main_debug.dart` builds the debug screen for the web. It was checked in a browser: packs load from assets, and progress persists in IndexedDB.
