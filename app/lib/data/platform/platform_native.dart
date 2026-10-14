/// Native (dart:ffi + dart:io) implementation of `platform.dart`.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../core/core.dart';
import '../course/course_bytes.dart';
import '../course/course_file.dart';
import '../course/course_repo.dart';
import '../packs/pack_file_store.dart';

const bool supportsPackFiles = true;

/// Loads a whole pack on a background isolate (the result is handed back without copying).
Future<CourseRepo> loadCoursePack(PackData data) => switch (data) {
      PackFile(:final path) => Isolate.run(() => loadCourseRepoFile(path)),
      PackBytes(:final bytes) => Isolate.run(() => loadCourseRepoFromBytes(sqlite3, bytes)),
    };

Future<CourseMeta> readPackMeta(PackData data) async => switch (data) {
      PackFile(:final path) => readCourseMetaFile(path),
      PackBytes(:final bytes) => readCourseMetaFromBytes(sqlite3, bytes),
    };

/// Installed packs live in `{baseDir}/courses/{id}.sqlite`.
PackFileStore defaultPackFileStore(String? baseDir) {
  if (baseDir == null) throw ArgumentError('A base directory is required on native platforms');
  return NativePackFileStore(Directory(p.join(baseDir, 'courses')));
}

class NativePackFileStore implements PackFileStore {
  NativePackFileStore(this.dir);
  final Directory dir;

  File _file(String id) => File(p.join(dir.path, '$id.sqlite'));
  File get _manifest => File(p.join(dir.path, 'packs.json'));

  @override
  Future<PackData> data(String courseId) async {
    final f = _file(courseId);
    if (!f.existsSync()) throw StateError('Pack $courseId is not installed (${f.path})');
    return PackFile(f.path);
  }

  @override
  Future<int?> size(String courseId) async {
    final f = _file(courseId);
    return f.existsSync() ? f.lengthSync() : null;
  }

  @override
  Future<void> writeBytes(String courseId, Uint8List bytes) async {
    await dir.create(recursive: true);
    final tmp = File('${_file(courseId).path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await _replace(tmp, _file(courseId));
  }

  @override
  Future<void> copyFile(String courseId, String sourcePath) async {
    await dir.create(recursive: true);
    final tmp = File('${_file(courseId).path}.tmp');
    await File(sourcePath).copy(tmp.path);
    await _replace(tmp, _file(courseId));
  }

  /// Atomic where the OS allows (rename over an existing file fails on Windows,
  /// so the old file is removed first there).
  Future<void> _replace(File tmp, File target) async {
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      if (target.existsSync()) await target.delete();
      await tmp.rename(target.path);
    }
  }

  @override
  Future<bool> delete(String courseId) async {
    final f = _file(courseId);
    if (!f.existsSync()) return false;
    await f.delete();
    return true;
  }

  @override
  Future<List<String>> installedIds() async {
    if (!dir.existsSync()) return const [];
    return [
      for (final f in dir.listSync().whereType<File>())
        if (p.extension(f.path).toLowerCase() == '.sqlite') p.basenameWithoutExtension(f.path),
    ]..sort();
  }

  @override
  Future<String?> readManifest() async =>
      _manifest.existsSync() ? _manifest.readAsString() : null;

  @override
  Future<void> writeManifest(String json) async {
    await dir.create(recursive: true);
    final tmp = File('${_manifest.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await _replace(tmp, _manifest);
  }

  @override
  String location(String courseId) => _file(courseId).path;
}
