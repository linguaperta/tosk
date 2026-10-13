import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers.dart';
import 'ui/demo/demo_courses.dart';
import 'ui/demo/demo_progress_store.dart';
import 'ui/demo/demo_skill_stats.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo wiring until integration: in-memory courses and progress, seeded with
  // some history so the map shows strength, decay and tiers.
  // TODO(integration): open the real course catalog and progress database here
  // and pass them as overrides instead.
  final catalog = DemoCourseCatalog();
  final store = InMemoryProgressStore();
  final now = DateTime.now();
  for (final meta in await catalog.listCourses()) {
    await seedDemoProgress(store, await catalog.open(meta.id), now);
  }

  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [courseCatalogProvider.overrideWithValue(catalog), progressStoreProvider.overrideWithValue(store)],
      child: const ToskApp(),
    ),
  );
}
