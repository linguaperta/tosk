import '../core/core.dart';

/// The courses the app can open. The UI depends only on this; the demo
/// implementation lives in `ui/demo/`, the real one (at integration) adapts the
/// data layer's `LocalPackSource` + course repository.
abstract interface class CourseCatalog {
  /// Installed courses (meta only), in display order.
  Future<List<CourseMeta>> listCourses();

  /// Opens one course for reading. Called again when the user switches courses.
  Future<CourseData> open(String courseId);
}
