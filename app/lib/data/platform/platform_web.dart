/// Web implementation of `platform.dart`: course packs are bytes opened with
/// sqlite3 WASM (`web/sqlite3.wasm`, matching package:sqlite3's version) in an
/// in-memory VFS. Installed packs live in memory for the session.
library;

import 'package:sqlite3/wasm.dart';

import '../../core/core.dart';
import '../course/course_bytes.dart';
import '../course/course_repo.dart';
import '../packs/pack_file_store.dart';

const bool supportsPackFiles = false;

Future<WasmSqlite3>? _sqlite;

/// sqlite3 compiled to WebAssembly, loaded once from `sqlite3.wasm` next to index.html.
Future<WasmSqlite3> loadWasmSqlite3() => _sqlite ??= WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));

Future<CourseRepo> loadCoursePack(PackData data) async => switch (data) {
      PackBytes(:final bytes) => loadCourseRepoFromBytes(await loadWasmSqlite3(), bytes),
      PackFile() => throw UnsupportedError('Pack files are not available on the web'),
    };

Future<CourseMeta> readPackMeta(PackData data) async => switch (data) {
      PackBytes(:final bytes) => readCourseMetaFromBytes(await loadWasmSqlite3(), bytes),
      PackFile() => throw UnsupportedError('Pack files are not available on the web'),
    };

PackFileStore defaultPackFileStore(String? baseDir) => MemoryPackFileStore();
