import '../core/core.dart';

/// The courses the app can open. The UI depends only on this. The real
/// implementation is `PackCourseCatalog` (`ui/pack_course_catalog.dart`) over
/// the data layer's packs; `DemoCourseCatalog` (`ui/demo/`) is the fallback
/// when no pack is installed.
abstract interface class CourseCatalog {
  /// Installed courses (meta only), in display order.
  Future<List<CourseMeta>> listCourses();

  /// Opens one course for reading. Called again when the user switches courses.
  Future<CourseData> open(String courseId);

  /// Whether [courseId] is built-in sample content rather than a real course
  /// pack. The UI labels such courses "Demo".
  bool isDemo(String courseId);
}
