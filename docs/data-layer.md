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
  sync/                  review-log JSON lines, FileExportSyncBackend, syncReviewLog
core/interfaces/packs.dart   PackSource, PackInfo, PackData (PackFile | PackBytes), PackHandle
core/interfaces/remote_packs.dart   RemotePackSource, RemoteIndex, RemotePack, CourseOffer, combineOffers
core/interfaces/sync.dart    SyncBackend, NullSyncBackend
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
- **Validation.** `meta` must contain `schema_version`, `course_id`, `version`, `title`, `target`, `persons` and `tenses`. The major version of `schema_version` must equal `kCourseDbSchemaVersion` in `course/course_schema.dart`, so `'1.1'` loads and `'2'` is refused. Errors throw `CourseFormatException`.

### Pack sources

`LocalPackSource` implements `PackSource`:

- **Bundled packs.** These are `assets/courses/*.sqlite`, found through the AssetManifest. On first use they are copied into the installed-pack store. A pack is copied again when its bundled `meta.version` is a newer semver than the installed copy, for example after an app update. A bundled pack that fails validation is skipped with a warning.
- **Installed-pack store.** Natively this is `{app support dir}/courses/{id}.sqlite` plus a `packs.json` manifest. It uses the app support folder rather than Documents, so it stays out of the user's Documents folder on desktop. You can override the folder with `AppDataOptions.dataDirectory`. On the web, packs live in memory and are read from asset bytes on every start.
- **Packs copied in by hand.** A `{id}.sqlite` file placed in the store's `courses/` folder is found when the packs are first listed, validated and registered with origin `local` (a misnamed or invalid file is skipped with a warning). A replaced file is re-read on the next start and a deleted one disappears from the list. This is how the locally built Sarnami pack, which may never be bundled, gets onto a desktop machine (`docs/sarnami.md`). On Windows the folder is `%APPDATA%\io.github.timoverlaan\tosk\courses`.
- **`install(PackFile | PackBytes)`.** Used by the course picker's "Add course from file…" and the debug screen. It validates the pack, then replaces the installed pack with the same course id, with origin `local`.
- **`remove(id)`.** Deletes a `local` pack. A bundled pack for that course comes back the next time packs are listed, and bundled packs themselves can't be removed.

### Downloads: `GitHubPackSource` (`packs/github_pack_source.dart`, v0.4)

`GitHubPackSource` implements `PackSource` (delegating to its `LocalPackSource`, so `available()` is always what opens offline) and the core `RemotePackSource` (`core/interfaces/remote_packs.dart`). `openAppData` wires it when `AppDataOptions.appVersion` is set (`main.dart` passes `kAppVersion`); `AppData.remote` exposes it and `AppData.downloadPack` downloads and evicts the cached course.

- **Index.** `fetchIndex()` reads `index.json` from `kDefaultPackIndexUrl` = `https://github.com/timoverlaan/tosk-data/releases/latest/download/index.json` (GitHub's redirect to the newest release's asset; see docs/release.md, "Publishing course packs"), or from a `url` (the debug setting `packs.index_url`). Redirects are followed by hand natively (`followRedirects: false`, up to 5 hops: `releases/latest` → `releases/download/<tag>` → object storage), and by the browser on the web. Format (`index_version` 1, written by `pipeline/pipeline/publish.py`):

  ```json
  {"index_version": 1, "generated_at": "2026-10-14T10:00:00Z", "tag": "packs-20261014",
   "courses": [{"id": "it", "version": "1.1.0", "title": {"en": "Italian", "nl": "Italiaans"},
     "description": {"en": "..."}, "target": "it", "sources": ["en", "nl"], "unverified": false,
     "schema_version": "1", "min_app_version": "0.3.0", "sha256": "…", "size": 17199104,
     "url": "https://github.com/timoverlaan/tosk-data/releases/download/packs-20261014/it.sqlite"}]}
  ```

  A higher `index_version` is refused ("needs a newer app"); unknown fields are ignored.
- **Offers.** `combineOffers(installed, index, appVersion, schemaMajor)` gives one `CourseOffer` per course: `installed`, `updateAvailable` (installed, the index has a newer semver the app can use), `downloadable`, or `needsAppUpdate` (the schema major differs from `kCourseDbSchemaVersion`, or `min_app_version` is newer than the app). An installed course whose newer version needs a newer app just stays `installed`.
- **Download.** `download(pack, onProgress:, cancel:)` refuses incompatible packs before any request, then streams the asset into `PackFileStore.stage(id)` (natively `courses/{id}.sqlite.download`; memory on the web), hashing as it goes. It checks the size (a body larger than announced is cut off at once; a short one is "incomplete"), the sha256, and then `LocalPackSource.installStaged` validates the file's meta (course id, version, schema major) and swaps it in: `{id}.sqlite` → `{id}.sqlite.bak`, staged → `{id}.sqlite` (two renames; Windows can't rename over a file), opens the new file with `verify` (the app loads it fully, `platform.loadCoursePack`), and only then drops the backup and writes `packs.json` with origin `remote`. If opening fails, the backup is renamed back (rollback). A crash at any step is repaired on the next start (`NativePackFileStore` restores a leftover `.bak` and deletes `.download` files once per store), and since `packs.json` is written last, folder and manifest always agree.
- **Errors** are `PackDownloadException(kind, message)` with kinds `network` (no connection, timeouts of 30 s per connect/idle, a dropped connection), `http` (404, 5xx), `corrupt` (size, checksum, wrong course/version, unreadable or newer-schema file, failed open), `incompatible` and `cancelled` (`DownloadCancel.cancel()`, which also aborts the request through `http.AbortableRequest`). Messages are short and polite; installed packs are never touched by a failure.
- **Progress is never touched.** Item ids are permanent, so a newer pack keeps every id; facets of items a pack drops stay in the log and states but are no longer scheduled. Every session builder, the stats, mistakes and progression iterate the course's own facets, so orphaned states are ignored (`test/engine/removed_items_test.dart`).
- **Bundled packs stay the fallback.** A downloaded pack wins while its version is at least the bundled one; after an app update with a newer bundled pack, the bundled pack is installed again. Removing a downloaded course (`remove`) falls back to the bundled pack.
- **Web.** Downloads go into the in-memory pack store (the layer has no persistent pack storage on the web), so they last for the session; the bundled packs come back on reload. GitHub's release-asset redirect target may not send CORS headers, so web downloads can fail with a polite network error. Open issue: serve a CORS-friendly mirror for the web build (GitHub Pages or `raw.githubusercontent.com/.../dist/`, whose index `url`s the web build would use) and persist downloaded packs in IndexedDB.

Tests: `test/data/github_pack_source_test.dart` (a fake GitHub with the release URLs and redirects via `MockClient`, plus a real local `HttpServer` with a dropped connection: index, offers, update with progress, 404, corrupted checksum, truncated, oversized, newer schema/app, wrong course/version in the file, network loss, cancel, rollback when the new pack fails to open, crash recovery, the in-memory store, `AppData.downloadPack` keeping the review log).

## Progress database

The progress database is drift, defined in `progress/progress_db.dart` with generated code in `progress_db.g.dart`. Times are stored as INTEGER UTC epoch milliseconds, so stored states round-trip exactly.

| Table | Contents |
| --- | --- |
| `review_log` | Append-only and the source of truth. Columns: id (UUID PK), facet_id, at, rating, exercise_type, input_mode, response_ms, correct, answer, session_id, mode. Indexes: (facet_id, at) and (at). |
| `facet_state` | Derived from the log. Columns: facet_id PK, stability, difficulty, due (indexed), last_review, reps, lapses, phase, step. |
| `mistakes` | The `MistakeRecord` fields. Indexes: at and facet_id. |
| `settings` | Key/value pairs. |
| `ai_explanations` | Schema v2. Cached AI explanations. Columns: fingerprint, given and lang (together the primary key), body, facet_id, provider, model, created_at. |
| `flags` | Schema v2. Flagged exercises: a full exercise snapshot (JSON), the answers, the reasons, the comment, the AI verdict, and the app and pack versions. Index on created_at. The format and the export are in `docs/feedback.md`. |

`DriftFeedbackStore` (`progress/feedback_store.dart`, exposed as `AppData.feedback`) implements the core `ExplanationCache` and `FlagStore` over these two tables. `InMemoryFeedbackStore` has the same semantics, for tests and the defaults.

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
5. Run `dart run drift_dev make-migrations` from `app/`. This dumps `drift_schemas/progress/drift_schema_vN.json` and generates migration test scaffolding in `test/drift/progress/`. The options are in `app/build.yaml`. Commit the schema dump and add the generated tests. The command also writes a `progress_db.steps.dart` helper for `stepByStep` migrations. Delete it: this database writes its steps by hand in `onUpgrade`. The v1 → v2 step (two new tables) is tested in `test/drift/progress/migration_test.dart`, including data integrity.
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

## Sync

`SyncBackend` (in core) has `push(events)` and `pull(since:)`, and merging is the union of events by id. `syncReviewLog(backend:, store:, importer:)` pulls, imports, then pushes the full log.

v1 has two backends:

- **`NullSyncBackend`**: does nothing.
- **`FileExportSyncBackend`**: reads and writes one JSON-lines file through I/O callbacks you supply, so the same code works with a desktop file or a browser download. One event per line, sorted by `(at, id)`. The codec is `encodeReviewLogJsonl` / `decodeReviewLogJsonl`.

A Google Drive `appDataFolder` backend comes later.

### Progress backup (`sync/progress_backup.dart`, Settings → Backup)

One JSON-lines file, format `tosk-backup/1`: a header line (`format`, `exported_at`, `app`, counts), the review log exactly as `encodeReviewLogJsonl` writes it, then `{"kind":"mistake",…}` per mistake and `{"kind":"setting","key","value"}` per setting (stores that implement `SettingsLister`, `ProgressRepo` and `InMemoryProgressStore`, list every setting). Flags have their own export (docs/feedback.md). A plain review-log file imports too, and unknown `kind`s are skipped.

**Import merges, never deletes:** events are a union by id (`importEvents`, idempotent), then `rebuildStates()`; mistakes are added when their id is new; settings only fill keys this device lacks, except "my courses" (`courses.added`), which is a union; the reminder keys are device-only and never imported. `importBackup` returns the counts the UI shows. Tests: `test/data/progress_backup_test.dart` (round trip between two on-disk databases, a duplicate import, the layout, bad files).

## Web assets

`app/web/sqlite3.wasm` comes from the `sqlite3-3.7.1` release of simolus3/sqlite3.dart, matching the resolved `sqlite3` package. `app/web/drift_worker.js` comes from the `drift-2.35.2` release of simolus3/drift.

When `sqlite3` or `drift` is upgraded in `pubspec.lock`, download the matching files again from:

```
https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-<version>/sqlite3.wasm
https://github.com/simolus3/drift/releases/download/drift-<version>/drift_worker.js
```

`flutter build web -t lib/main_debug.dart` builds the debug screen for the web. It was checked in a browser: packs load from assets, and progress persists in IndexedDB.
