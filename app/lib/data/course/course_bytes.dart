/// Opens a course database from raw bytes (web assets, downloads, tests).
///
/// The bytes go into an [InMemoryFileSystem] VFS registered on the given
/// sqlite3 instance (`WasmSqlite3` on the web, the FFI `sqlite3` natively), and
/// the database is opened read-only through it. Pure Dart, platform independent.
library;

import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:typed_data/typed_buffers.dart';

import '../../core/core.dart';
import 'course_loader.dart';
import 'course_repo.dart';
import 'course_schema.dart';

int _vfsCounter = 0;

/// Runs [body] with [bytes] opened read-only as a database, then closes and unregisters everything.
T withCourseBytes<T>(CommonSqlite3 sqlite, Uint8List bytes, T Function(CommonDatabase db) body) {
  if (bytes.length > kMaxPackBytes) throw CourseFormatException('The course file is too large');
  final vfs = InMemoryFileSystem(name: 'course-bytes-${_vfsCounter++}');
  const path = '/course.sqlite';
  vfs.fileData[path] = Uint8Buffer()..addAll(bytes);
  sqlite.registerVirtualFileSystem(vfs);
  CommonDatabase? db;
  try {
    db = sqlite.open(path, vfs: vfs.name, mode: OpenMode.readOnly);
    return body(db);
  } finally {
    db?.close();
    sqlite.unregisterVirtualFileSystem(vfs);
  }
}

/// Loads a whole course from database [bytes].
CourseRepo loadCourseRepoFromBytes(CommonSqlite3 sqlite, Uint8List bytes) =>
    withCourseBytes(sqlite, bytes, loadCourseRepoFromSqlite);

/// Reads only the course meta from database [bytes] ([checkIntegrity]: see `guardCourseDb`).
CourseMeta readCourseMetaFromBytes(CommonSqlite3 sqlite, Uint8List bytes, {bool checkIntegrity = false}) =>
    withCourseBytes(sqlite, bytes, (db) => readCourseMeta(db, checkIntegrity: checkIntegrity));
