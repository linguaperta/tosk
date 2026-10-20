/// Web implementation of `platform.dart`: course packs are bytes opened with
/// sqlite3 WASM (`web/sqlite3.wasm`, matching package:sqlite3's version) in an
/// in-memory VFS. Installed packs are kept in IndexedDB (v0.7), so downloads
/// survive a reload; where IndexedDB fails they live in memory for the session.
library;

import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

import '../../core/core.dart';
import '../course/course_bytes.dart';
import '../course/course_repo.dart';
import '../packs/blob_pack_file_store.dart';
import '../packs/pack_file_store.dart';
import 'idb_blob_store.dart';

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

PackFileStore defaultPackFileStore(String? baseDir) => BlobPackFileStore(
      FallbackBlobStore(
        IdbBlobStore(),
        // ignore: avoid_print
        onFallback: (e) => print('[packs] IndexedDB unavailable, packs are kept in memory: $e'),
      ),
    );

/// The page's base URL (`<base href>`), against which the same-origin pack
/// mirror (`packs/index.json` on GitHub Pages) is resolved.
Uri? pageBaseUri() => Uri.tryParse(web.document.baseURI);
