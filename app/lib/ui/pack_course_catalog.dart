import '../core/core.dart';
import '../data/app_data.dart';
import 'course_catalog.dart';

/// [CourseCatalog] over the data layer: the installed course packs
/// ([AppData.availableCourses], bundled packs are installed on first use) and
/// [AppData.openCourse] (a cached `CourseRepo`, which implements [CourseData]).
///
/// When **no** pack is installed it falls back to [fallback] (the demo courses),
/// whose courses report [isDemo]. As soon as packs exist (for example after
/// `assets/courses/*.sqlite` ship with the app) they are used instead,
/// automatically.
class PackCourseCatalog implements CourseCatalog {
  PackCourseCatalog(this.app, {this.fallback});

  final AppData app;
  final CourseCatalog? fallback;

  /// Course ids served by [fallback] in the latest listing.
  final Set<String> _fallbackIds = {};

  @override
  Future<List<CourseMeta>> listCourses() async {
    final packs = await app.availableCourses();
    final fb = fallback;
    if (packs.isEmpty && fb != null) {
      final demo = await fb.listCourses();
      _fallbackIds
        ..clear()
        ..addAll(demo.map((c) => c.id));
      return demo;
    }
    _fallbackIds.clear();
    return [for (final p in packs) listingMeta(p)];
  }

  /// A summary [CourseMeta] from pack info, without loading the pack: id,
  /// version, title and the unverified flag are real; persons, tenses and
  /// translations are empty (read them from the opened course).
  static CourseMeta listingMeta(PackInfo p) => CourseMeta(
    id: p.id,
    version: p.version,
    title: p.title,
    target: p.id,
    translations: const [],
    persons: const [],
    tenses: const [],
    unverified: p.unverified,
    schemaVersion: p.schemaVersion,
  );

  @override
  Future<CourseData> open(String courseId) {
    if (_fallbackIds.contains(courseId)) return fallback!.open(courseId);
    return app.openCourse(courseId);
  }

  @override
  bool isDemo(String courseId) => _fallbackIds.contains(courseId);
}
