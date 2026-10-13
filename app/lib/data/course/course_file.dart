/// Native (dart:ffi) course loading from a file path. Pure Dart, usable from
/// `dart run` tools and tests. Not importable on the web; app code goes
/// through `data/platform/platform.dart` instead.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../../core/core.dart';
import 'course_loader.dart';
import 'course_repo.dart';
import 'course_schema.dart';

/// Opens a course database file read-only.
Database openCourseFile(String path) {
  if (!File(path).existsSync()) {
    throw CourseFormatException('Course file not found: $path');
  }
  return sqlite3.open(path, mode: OpenMode.readOnly);
}

/// Loads a whole course from the database file at [path] (opened read-only).
InMemoryCourseData loadCourseFile(String path) => loadCourseRepoFile(path).data;

/// Like [loadCourseFile] but returns the [CourseRepo] (meta info and counts).
CourseRepo loadCourseRepoFile(String path) {
  final db = openCourseFile(path);
  try {
    return loadCourseRepoFromSqlite(db);
  } finally {
    db.close();
  }
}

/// Reads and validates only the meta of the course file at [path].
CourseMeta readCourseMetaFile(String path) {
  final db = openCourseFile(path);
  try {
    return readCourseMeta(db);
  } finally {
    db.close();
  }
}
