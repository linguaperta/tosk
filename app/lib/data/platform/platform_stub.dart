/// Fallback for platforms with neither dart:ffi nor JS interop (never used in practice).
library;

import '../../core/core.dart';
import '../course/course_repo.dart';
import '../packs/pack_file_store.dart';

const bool supportsPackFiles = false;

Future<CourseRepo> loadCoursePack(PackData data) =>
    throw UnsupportedError('No sqlite3 implementation on this platform');

Future<CourseMeta> readPackMeta(PackData data) =>
    throw UnsupportedError('No sqlite3 implementation on this platform');

PackFileStore defaultPackFileStore(String? baseDir) => MemoryPackFileStore();

/// Only the web has a page URL.
Uri? pageBaseUri() => null;
