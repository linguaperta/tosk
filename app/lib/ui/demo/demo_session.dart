import 'package:uuid/uuid.dart';

import '../../core/core.dart';
import '../settings/app_settings.dart';
import 'demo_exercises.dart';
import 'demo_grader.dart';

/// Fake [SessionFactory] over the hand-made demo exercises. It grades correctly,
/// records every outcome in the [ProgressStore] and re-queues mistakes once, so
/// the UI behaves as it will with the real engine.
///
/// TODO(integration): replace with the engine's SessionFactory in `providers.dart`.
class DemoSessionFactory implements SessionFactory {
  DemoSessionFactory({
    required this.course,
    required this.store,
    required this.options,
    List<Exercise>? pool,
    DateTime Function()? clock,
  }) : pool = pool ?? demoExercises(course.meta.id, options.sourceLang),
       clock = clock ?? DateTime.now;

  final CourseData course;
  final ProgressStore store;
  final SessionOptions options;
  final List<Exercise> pool;
  final DateTime Function() clock;

  DemoPracticeSession _make(SessionMode mode, List<Exercise> source, int? length, {bool requeue = true}) =>
      DemoPracticeSession(
        mode: mode,
        source: source,
        length: length,
        store: store,
        grader: DemoGrader(accents: options.accents),
        clock: clock,
        requeueMistakes: requeue,
      );

  @override
  Future<PracticeSession> lesson(String skillId, {LessonFocus focus = LessonFocus.mixed, int length = 12}) async {
    final types = kFocusTypes[focus]!;
    var source = pool.where((e) => e.skillId == skillId && types.contains(e.type)).toList();
    if (source.isEmpty) source = pool.where((e) => e.skillId == skillId).toList();
    if (source.isEmpty) source = pool.where((e) => types.contains(e.type)).toList();
    return _make(SessionMode.lesson, source, length);
  }

  @override
  Future<PracticeSession> lab({
    required List<String> skillIds,
    required List<ExerciseType> types,
    required int length,
  }) async {
    final source = pool
        .where((e) => (skillIds.isEmpty || skillIds.contains(e.skillId)) && (types.isEmpty || types.contains(e.type)))
        .toList();
    return _make(SessionMode.lab, source, length);
  }

  @override
  Future<PracticeSession> nonStop() async => _make(SessionMode.nonstop, pool, null, requeue: false);

  @override
  Future<PracticeSession> fading({int length = 12}) async => _make(SessionMode.review, pool.reversed.toList(), length);
}

class DemoPracticeSession implements PracticeSession {
  DemoPracticeSession({
    required this.mode,
    required List<Exercise> source,
    required int? length,
    required this.store,
    required this.grader,
    required this.clock,
    this.requeueMistakes = true,
  }) : _source = source,
       plannedLength = length == null ? null : (source.isEmpty ? 0 : length),
       _startedAt = clock() {
    if (length != null) {
      for (var i = 0; i < plannedLength!; i++) {
        _queue.add(source[i % source.length]);
      }
    }
  }

  @override
  final String id = const Uuid().v4();
  @override
  final SessionMode mode;
  @override
  final int? plannedLength;
  final ProgressStore store;
  final DemoGrader grader;
  final DateTime Function() clock;
  final bool requeueMistakes;

  final List<Exercise> _source;
  final List<Exercise> _queue = [];
  final Set<Exercise> _requeued = {};
  final Set<String> _facets = {};
  final List<String> _mistakes = [];
  final DateTime _startedAt;
  DateTime? _endedAt;
  int _served = 0;
  int _answered = 0;
  int _correct = 0;
  bool _stopped = false;

  @override
  int get answered => _answered;
  @override
  int get correctCount => _correct;

  @override
  Future<Exercise?> next() async {
    if (_stopped) return null;
    if (plannedLength == null) {
      if (_source.isEmpty) return null;
      return _source[_served++ % _source.length];
    }
    if (_queue.isEmpty) {
      _endedAt ??= clock();
      return null;
    }
    _served++;
    return _queue.removeAt(0);
  }

  @override
  Future<Result> submit(Exercise exercise, Answer answer, {required Duration elapsed}) async {
    final result = grader.grade(exercise, answer, elapsed: elapsed);
    _answered++;
    if (result.correct) _correct++;
    final now = clock().toUtc();
    for (final o in result.outcomes) {
      _facets.add(o.facetId);
      final eventId = const Uuid().v4();
      await store.record(
        ReviewEvent(
          id: eventId,
          facetId: o.facetId,
          at: now,
          rating: o.rating,
          exerciseType: exercise.type.id,
          inputMode: answer.inputMode,
          responseMs: elapsed.inMilliseconds,
          correct: o.correct,
          answer: result.given,
          sessionId: id,
          mode: mode.name,
        ),
      );
      if (!o.correct) {
        if (!_mistakes.contains(o.facetId)) _mistakes.add(o.facetId);
        await store.saveMistake(
          MistakeRecord(
            id: eventId,
            facetId: o.facetId,
            at: now,
            exerciseType: exercise.type.id,
            prompt: exercise.instruction,
            expected: result.expected,
            given: result.given,
            skillId: exercise.skillId,
          ),
        );
      }
    }
    if (!result.correct && requeueMistakes && plannedLength != null && _requeued.add(exercise)) {
      _queue.add(exercise);
    }
    return result;
  }

  @override
  void stop() {
    _stopped = true;
    _endedAt ??= clock();
  }

  @override
  SessionSummary summary() => SessionSummary(
    sessionId: id,
    mode: mode,
    answered: _answered,
    correct: _correct,
    startedAt: _startedAt,
    endedAt: _endedAt ?? clock(),
    facetsPracticed: Set.of(_facets),
    mistakes: List.of(_mistakes),
  );
}
