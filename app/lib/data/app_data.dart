/// Everything the UI needs from the data layer, in one object. Pure Dart; the
/// Flutter wiring is `openAppData()` in `bootstrap.dart`.
///
/// ```dart
/// final app = await openAppData();
/// final packs = await app.availableCourses();          // List<PackInfo>
/// final course = await app.openCourse('it');           // CourseRepo (cached)
/// final stats = await app.stats.forCourse(course);     // skill id -> SkillStats
/// await app.progress.record(event);                    // ProgressStore
/// ```
library;

import '../core/core.dart';
import 'course/course_repo.dart';
import 'fsrs/fsrs_scheduler.dart';
import 'progress/bookmarks.dart';
import 'progress/feedback_store.dart';
import 'progress/progress_repo.dart';
import 'stats/skill_stats.dart';
import 'sync/review_log_sync.dart';

typedef CoursePackLoader = Future<CourseRepo> Function(PackData data);

class AppData {
  AppData({
    required this.progress,
    required this.packs,
    required this.loadPack,
    Scheduler? scheduler,
    this.sync = const NullSyncBackend(),
  }) : scheduler = scheduler ?? progress.scheduler;

  /// The progress store (also an [EventImporter]); the engine takes it as a [ProgressStore].
  final ProgressRepo progress;
  final Scheduler scheduler;
  final PackSource packs;
  final SyncBackend sync;

  /// Loads a pack into memory (platform specific; see `data/platform/platform.dart`).
  final CoursePackLoader loadPack;

  late final SkillStatsService stats = SkillStatsService(progress, scheduler);

  /// Cached AI explanations and exercise flags (tables in the progress database).
  late final FeedbackStore feedback = DriftFeedbackStore(progress.db);

  /// Starred words, sentences and exercises (table `bookmarks`, schema v3).
  late final BookmarkRepo bookmarks = DriftBookmarkRepo(progress.db);

  final Map<String, Future<CourseRepo>> _courses = {};

  /// Packs that can be opened (bundled packs are installed on first call).
  Future<List<PackInfo>> availableCourses() => packs.available();

  /// Loads course [courseId] fully into memory (cached until [evictCourse]).
  Future<CourseRepo> openCourse(String courseId) {
    return _courses[courseId] ??= () async {
      try {
        final handle = await packs.open(courseId);
        return await loadPack(handle.data);
      } catch (_) {
        _courses.remove(courseId);
        rethrow;
      }
    }();
  }

  /// Drops a cached course (e.g. after installing a new version of its pack).
  void evictCourse(String courseId) => _courses.remove(courseId);

  /// Installs a pack (dev file picker) and evicts the cached course.
  Future<PackInfo> installPack(PackData data) async {
    final info = await packs.install(data);
    evictCourse(info.id);
    return info;
  }

  /// Online packs (`GitHubPackSource`), or null when [packs] is local only.
  RemotePackSource? get remote => switch (packs) {
    final RemotePackSource r => r,
    _ => null,
  };

  /// Downloads and installs [pack] (see [RemotePackSource.download]) and
  /// evicts the cached course, so the next [openCourse] loads the new version.
  Future<PackInfo> downloadPack(RemotePack pack, {DownloadProgress? onProgress, DownloadCancel? cancel}) async {
    final r = remote ?? (throw StateError('Downloads are not available'));
    final info = await r.download(pack, onProgress: onProgress, cancel: cancel);
    evictCourse(info.id);
    return info;
  }

  /// Pull + merge + push the review log with [sync].
  Future<SyncReport> syncNow() =>
      syncReviewLog(backend: sync, store: progress, importer: progress);

  Future<void> close() => progress.close();

  /// FSRS scheduler with the app's fixed settings.
  static Scheduler defaultScheduler() => FsrsScheduler();
}
