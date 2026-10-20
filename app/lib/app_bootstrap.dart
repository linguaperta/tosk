/// Opens the data layer for the app and turns it into provider overrides.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/misc.dart' show Override;

import 'data/bootstrap.dart';
import 'progression/calendar.dart';
import 'providers.dart';
import 'sync/sync_bootstrap.dart';
import 'sync/sync_config.dart';
import 'sync/sync_providers.dart';
import 'ui/course_catalog.dart';
import 'ui/demo/demo_courses.dart';
import 'ui/demo/demo_seed.dart';
import 'ui/pack_course_catalog.dart';
import 'ui/settings/synced_settings.dart';

/// Suffix of the progress database used while running on the demo courses, so
/// demo practice never mixes with progress on real course packs.
const demoProgressDbSuffix = '-demo';

/// The opened data layer plus the catalog the app uses.
class AppBoot {
  const AppBoot({required this.app, required this.catalog, required this.demoMode, this.sync});

  final AppData app;
  final CourseCatalog catalog;

  /// True when no course pack was installed at start-up: the app runs on the
  /// demo courses with the `{progressDbName}-demo` progress database.
  final bool demoMode;

  /// Cloud sync, when the build has a Firebase configuration, the platform
  /// can sign in and real packs are in use (demo progress never syncs).
  final SyncSetup? sync;

  /// Overrides for the root `ProviderScope`.
  List<Override> get overrides => [
    appDataProvider.overrideWithValue(app),
    progressStoreProvider.overrideWithValue(app.progress),
    courseCatalogProvider.overrideWithValue(catalog),
    if (sync case final s?) ...[
      syncServiceProvider.overrideWithValue(s.service),
      // Local days from the UTC offset each answer was recorded with.
      calendarProvider.overrideWithValue(LocalCalendar(s.engine.offsets.offsetAt)),
    ],
  ];

  Future<void> close() async {
    await sync?.close();
    await app.close();
  }
}

/// Opens [openAppData] and picks the course source:
///
/// * Course packs installed (bundled `assets/courses/*.sqlite` count, they are
///   installed on first use): a [PackCourseCatalog] over them and the normal
///   progress database.
/// * No packs: the demo courses (labelled "Demo" in the UI) with a separate
///   progress database (`progress-demo`), seeded once with some history. Real
///   packs that show up later are used automatically on the next start.
///
/// [syncConfig] (default: none) turns on cloud sync where the platform supports it.
Future<AppBoot> bootApp({
  AppDataOptions options = const AppDataOptions(),
  DateTime Function()? clock,
  FirebaseSyncConfig? syncConfig,
}) async {
  final app = await openAppData(options: options);
  // From the web pack mirror (nothing bundled), no packs is the normal first
  // visit: the learner downloads a course from the picker, so the real
  // progress database is used from the start (the demo course only fills the
  // map until then, unseeded); a separate demo database would lose the
  // picked courses and the first answers at the next reload.
  if (options.packsFromWebMirror || (await app.availableCourses()).isNotEmpty) {
    SyncSetup? sync;
    if (syncConfig != null) {
      try {
        sync = await openSync(
          progress: app.progress,
          config: syncConfig,
          syncedSettings: kSyncedSettingKeys,
          unionKeys: kUnionSettingKeys,
          directory: options.dataDirectory,
        );
      } on Object catch (e) {
        // Sync is optional: without it the app works exactly as offline.
        debugPrint('[sync] not available: $e');
      }
    }
    return AppBoot(
      app: app,
      catalog: PackCourseCatalog(app, fallback: DemoCourseCatalog()),
      demoMode: false,
      sync: sync,
    );
  }
  await app.close();

  final demoApp = await openAppData(
    options: AppDataOptions(
      dataDirectory: options.dataDirectory,
      progressDbName: '${options.progressDbName}$demoProgressDbSuffix',
      bundled: options.bundled,
      appVersion: options.appVersion,
      httpClient: options.httpClient,
      packIndexUrl: options.packIndexUrl,
    ),
  );
  final demo = DemoCourseCatalog();
  if (await demoApp.progress.logCount() == 0) {
    final now = (clock ?? DateTime.now)();
    for (final meta in await demo.listCourses()) {
      await seedDemoProgress(demoApp.progress, await demo.open(meta.id), now);
    }
  }
  return AppBoot(app: demoApp, catalog: PackCourseCatalog(demoApp, fallback: demo), demoMode: true);
}
