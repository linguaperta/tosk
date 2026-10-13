/// Opens the data layer for the app and turns it into provider overrides.
library;

import 'package:flutter_riverpod/misc.dart' show Override;

import 'data/bootstrap.dart';
import 'providers.dart';
import 'ui/course_catalog.dart';
import 'ui/demo/demo_courses.dart';
import 'ui/demo/demo_seed.dart';
import 'ui/pack_course_catalog.dart';

/// Suffix of the progress database used while running on the demo courses, so
/// demo practice never mixes with progress on real course packs.
const demoProgressDbSuffix = '-demo';

/// The opened data layer plus the catalog the app uses.
class AppBoot {
  const AppBoot({required this.app, required this.catalog, required this.demoMode});

  final AppData app;
  final CourseCatalog catalog;

  /// True when no course pack was installed at start-up: the app runs on the
  /// demo courses with the `{progressDbName}-demo` progress database.
  final bool demoMode;

  /// Overrides for the root `ProviderScope`.
  List<Override> get overrides => [
    appDataProvider.overrideWithValue(app),
    progressStoreProvider.overrideWithValue(app.progress),
    courseCatalogProvider.overrideWithValue(catalog),
  ];

  Future<void> close() => app.close();
}

/// Opens [openAppData] and picks the course source:
///
/// * Course packs installed (bundled `assets/courses/*.sqlite` count, they are
///   installed on first use): a [PackCourseCatalog] over them and the normal
///   progress database.
/// * No packs: the demo courses (labelled "Demo" in the UI) with a separate
///   progress database (`progress-demo`), seeded once with some history. Real
///   packs that show up later are used automatically on the next start.
Future<AppBoot> bootApp({AppDataOptions options = const AppDataOptions(), DateTime Function()? clock}) async {
  final app = await openAppData(options: options);
  if ((await app.availableCourses()).isNotEmpty) {
    return AppBoot(app: app, catalog: PackCourseCatalog(app, fallback: DemoCourseCatalog()), demoMode: false);
  }
  await app.close();

  final demoApp = await openAppData(
    options: AppDataOptions(
      dataDirectory: options.dataDirectory,
      progressDbName: '${options.progressDbName}$demoProgressDbSuffix',
      bundled: options.bundled,
      sync: options.sync,
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
