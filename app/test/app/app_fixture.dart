/// The real app wiring (data layer, engine, progression) over the data layer's
/// fixture course, for integration tests.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:tosk/app_bootstrap.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/app_data.dart';
import 'package:tosk/data/course/course_bytes.dart';
import 'package:tosk/data/packs/local_pack_source.dart';
import 'package:tosk/data/packs/pack_file_store.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/pack_course_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../fixtures/course_fixture.dart';

class MapBundledPacks implements BundledPacks {
  MapBundledPacks(this.packs);
  final Map<String, Uint8List> packs;
  @override
  Future<List<String>> list() async => packs.keys.toList();
  @override
  Future<Uint8List> load(String key) async => packs[key]!;
}

/// Bundled packs with the fixture course as `it`.
MapBundledPacks fixtureBundledPacks() => MapBundledPacks({'assets/courses/it.sqlite': fixtureCourseBytes()});

/// A progress repo on an on-disk SQLite file (synchronous connection, so it
/// works inside widget tests' fake async).
ProgressRepo fileProgressRepo(String path) => ProgressRepo(ProgressDb(NativeDatabase(File(path))));

/// [AppData] over [progress] with the fixture course as the only bundled pack
/// (in-memory pack store, synchronous loaders).
AppData fixtureAppData(ProgressRepo progress) => AppData(
  progress: progress,
  packs: LocalPackSource(
    bundled: fixtureBundledPacks(),
    store: MemoryPackFileStore(),
    readMeta: (d) async => readCourseMetaFromBytes(sqlite3, (d as PackBytes).bytes),
  ),
  loadPack: (d) async => loadCourseRepoFromBytes(sqlite3, (d as PackBytes).bytes),
);

/// The overrides `main.dart` would install for [app] (packs mode).
AppBoot fixtureBoot(AppData app) =>
    AppBoot(app: app, catalog: PackCourseCatalog(app, fallback: DemoCourseCatalog()), demoMode: false);

/// A fresh temp directory, deleted after the test.
Directory tempDir(String name) {
  final dir = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold the SQLite file briefly; the OS cleans temp.
    }
  });
  return dir;
}
