/// The engine's [SessionFactory]: what the UI uses to start practice.
library;

import 'dart:math';

import '../../core/interfaces/course_data.dart';
import '../../core/interfaces/progress_store.dart';
import '../../core/interfaces/session.dart';
import '../../core/models/progress.dart';
import '../focus_presets.dart';
import '../gen_context.dart';
import '../grading/rating.dart';
import '../selector.dart';
import '../template.dart';
import 'assessment.dart';
import 'builders.dart';
import 'engine_session.dart';
import 'mistake_review.dart';
import 'starred.dart';

/// Creates sessions for one course.
///
/// ```dart
/// final factory = EngineSessionFactory(
///   course: courseData,            // InMemoryCourseData from the data layer
///   store: progressRepo,           // ProgressStore
///   scheduler: fsrs,               // Scheduler (retrievability for ordering)
///   options: SessionOptions(sourceLang: 'en', accents: AccentStrictness.lenient),
///   presets: FocusPresets.fromJsonString(await rootBundle.loadString('assets/config/focus_presets.json')),
/// );
/// final session = await factory.lesson('present-are', focus: LessonFocus.grammar);
/// for (var e = await session.next(); e != null; e = await session.next()) {
///   final result = await session.submit(e, answer, elapsed: stopwatch.elapsed);
/// }
/// ```
class EngineSessionFactory implements SessionFactory {
  EngineSessionFactory({
    required this.course,
    required this.store,
    required this.scheduler,
    required this.options,
    FocusPresets presets = FocusPresets.defaults,
    List<ExerciseTemplate>? templates,
    this.rating = const RatingPolicy(),
    this.stagePolicy = const StagePolicy(),
    DateTime Function()? clock,
    Random? random,
  })  : selector = ExerciseSelector(templates: templates, presets: presets),
        _clock = clock, // ignore: prefer_initializing_formals
        _random = random; // ignore: prefer_initializing_formals

  final CourseData course;
  final ProgressStore store;
  final Scheduler scheduler;
  final SessionOptions options;
  final ExerciseSelector selector;
  final RatingPolicy rating;
  final StagePolicy stagePolicy;
  final DateTime Function()? _clock;
  final Random? _random;

  SessionEnv _env() => SessionEnv(
        course: course,
        store: store,
        scheduler: scheduler,
        options: options,
        selector: selector,
        rating: rating,
        stagePolicy: stagePolicy,
        clock: _clock,
        random: _random,
      );

  @override
  Future<LessonSession> lesson(String skillId, {LessonFocus focus = LessonFocus.mixed, int length = 12}) async {
    final skill = course.skill(skillId);
    if (skill == null) throw ArgumentError.value(skillId, 'skillId', 'Unknown skill');
    return LessonBuilder(skill, focus, length: length).start(_env());
  }

  @override
  Future<LabSession> lab({required List<String> skillIds, required List<ExerciseType> types, required int length}) =>
      LabBuilder(skillIds, types, length).start(_env());

  @override
  Future<NonStopSession> nonStop() => const NonStopQueue().start(_env());

  @override
  Future<FadingSession> fading({int length = 12}) => FadingBuilder(length: length).start(_env());

  @override
  Future<MistakeReviewSession> review({int length = 12}) => ReviewBuilder(length: length).start(_env());

  @override
  Future<TestOutSession> testOut(String skillId, {int length = 10, double passMark = 0.8}) async {
    final skill = course.skill(skillId);
    if (skill == null) throw ArgumentError.value(skillId, 'skillId', 'Unknown skill');
    return TestOutBuilder(skill, length: length, passMark: passMark).start(_env());
  }

  @override
  Future<PlacementSession> placement({int maxExercises = kPlacementMaxExercises, PlacementConfig? config}) =>
      PlacementBuilder(config: config ?? PlacementConfig(maxExercises: maxExercises)).start(_env());

  @override
  Future<AssessmentOutcome> skipAhead(List<String> unitIds) async {
    final env = _env();
    final states = await store.allStates(courseId: course.meta.id);
    return SkipAheadSession(env, {for (final s in states) s.facetId: s}, unitIds).declare();
  }

  @override
  Future<ToughWordsSession> toughWords({int length = 12, int minLapses = kDefaultLeechLapses}) =>
      ToughWordsBuilder(length: length, minLapses: minLapses).start(_env());

  @override
  Future<StarredSession> starred(StarredPractice starred, {int length = 12}) =>
      StarredBuilder(starred, length: length).start(_env());
}
