/// Compiled course database schema version understood by this app.
///
/// Must match `COURSE_DB_SCHEMA_VERSION` in the pipeline (`pipeline/pipeline/compile.py`)
/// and `PRAGMA user_version` / `meta.schema_version` in `schema/course_db.sql`.
/// The loader refuses packs whose MAJOR version differs (a minor bump such as
/// `'1.1'` is additive and still loads).
library;

const int kCourseDbSchemaVersion = 1;

/// Meta keys that must be present for a pack to load.
const List<String> kRequiredCourseMetaKeys = [
  'schema_version',
  'course_id',
  'version',
  'title',
  'target',
  'persons',
  'tenses',
];

/// Thrown when a course database is missing, malformed, or of an unknown schema version.
class CourseFormatException implements Exception {
  CourseFormatException(this.message);
  final String message;
  @override
  String toString() => 'CourseFormatException: $message';
}

/// Parses the major part of a schema version string ('1', '1.2' -> 1).
int? parseSchemaMajor(String? v) {
  if (v == null) return null;
  final dot = v.indexOf('.');
  return int.tryParse((dot < 0 ? v : v.substring(0, dot)).trim());
}
