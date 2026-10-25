import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/engine/engine.dart' show EngineSessionFactory;
import 'package:tosk/ui/settings/app_settings.dart';
import 'package:uuid/uuid.dart';

import 'demo_exercises.dart';
import 'demo_grader.dart';

/// Test fake [SessionFactory] over hand-made exercises of every type (the app
/// itself uses the engine). It grades correctly, records every outcome in the
/// [ProgressStore] and re-queues mistakes once, so widget tests get a fixed,
/// deterministic exercise of each type.
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

  static const _assessable = {
    ExerciseType.multipleChoice,
    ExerciseType.conjPick,
    ExerciseType.conjGrid,
    ExerciseType.sentenceBuilder,
    ExerciseType.cloze,
    ExerciseType.spotError,
    ExerciseType.transform,
  };

  DemoAssessmentSession _assess(SessionMode mode, List<Exercise> source, List<List<String>> units, double passMark) =>
      DemoAssessmentSession(
        mode: mode,
        source: source,
        store: store,
        grader: DemoGrader(accents: options.accents),
        clock: clock,
        course: course,
        units: units,
        passMark: passMark,
      );

  /// The skill's pool exercises (no flashcards or match pairs), each once.
  @override
  Future<AssessmentSession> testOut(String skillId, {int length = 10, double passMark = 0.8}) async {
    final source = pool.where((e) => e.skillId == skillId && _assessable.contains(e.type)).take(length).toList();
    return _assess(SessionMode.testOut, source, [
      [skillId],
    ], passMark);
  }

  /// Every assessable pool exercise, unit by unit.
  @override
  Future<AssessmentSession> placement({int maxExercises = 40, int perSkill = 2, double passMark = 0.8}) async {
    final units = [
      for (final u in course.units)
        [
          for (final s in course.skills)
            if (s.unitId == u.id) s.id,
        ],
    ];
    final source = [
      for (final u in units)
        for (final s in u) ...pool.where((e) => e.skillId == s && _assessable.contains(e.type)).take(perSkill),
    ];
    return _assess(SessionMode.placement, source.take(maxExercises).toList(), units, passMark);
  }

  /// Self-declared credits through the real engine's rules.
  @override
  Future<AssessmentOutcome> skipAhead(List<String> unitIds) => EngineSessionFactory(
        course: course,
        store: store,
        scheduler: FsrsScheduler(),
        options: const SessionOptions(sourceLang: 'en'),
        clock: clock,
      ).skipAhead(unitIds);

  /// Pool exercises on facets with at least [minLapses] lapses.
  @override
  Future<PracticeSession> toughWords({int length = 12, int minLapses = 4}) async {
    final tough = {
      for (final st in await store.allStates(courseId: course.meta.id))
        if (st.lapses >= minLapses) st.facetId,
    };
    final source = pool.where((e) => tough.contains(e.facetId)).toList();
    return _make(SessionMode.review, source, source.isEmpty ? 0 : length.clamp(1, source.length));
  }

  /// The pool's exercises whose facet has a stored mistake (no resolution
  /// rule here; the engine's `openMistakes` is tested in the engine tests).
  @override
  Future<PracticeSession> review({int length = 12}) async {
    final facets = {for (final m in await store.mistakes(courseId: course.meta.id)) m.facetId};
    final source = pool.where((e) => facets.contains(e.facetId)).toList();
    return _make(SessionMode.review, source, source.isEmpty ? 0 : length.clamp(1, source.length));
  }

  /// The starred exercises as they are, then pool exercises on starred words.
  @override
  Future<PracticeSession> starred(StarredPractice starred, {int length = 12}) async {
    String item(String facetId) => facetId.substring(0, facetId.lastIndexOf('#'));
    final words = starred.itemIds.toSet();
    final source = [
      ...starred.exercises,
      ...pool.where((e) => words.contains(item(e.facetId))),
    ];
    return _make(SessionMode.starred, source, source.isEmpty ? 0 : length.clamp(1, source.length));
  }
}

/// Re-queues a wrong exercise once, at the end (as itself), and reports it
/// as a retry ([RetryingSession]) so every player test shows the retry note
/// and count.
class DemoPracticeSession implements PracticeSession, OverridableSession, RetryingSession {
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
    final e = _queue.removeAt(0);
    _current = e.id;
    _currentIsRetry = _requeued.contains(e) && _seen.contains(e.id);
    _seen.add(e.id);
    return e;
  }

  final Set<String> _seen = {};
  String? _current;
  bool _currentIsRetry = false;

  @override
  int get pendingRetries => _queue.where(_requeued.contains).length;

  @override
  bool isRetry(String exerciseId) => _currentIsRetry && exerciseId == _current;

  /// Last verdict and the events it wrote, per exercise id ("I was right").
  final Map<String, (Result, List<ReviewEvent>)> _verdicts = {};
  final Set<String> _overridden = {};

  @override
  bool canOverride(String exerciseId) {
    final v = _verdicts[exerciseId];
    return v != null && !v.$1.correct && !_overridden.contains(exerciseId);
  }

  @override
  Future<List<ReviewEvent>> overrideAnswer(String exerciseId) async {
    if (!canOverride(exerciseId)) return const [];
    _overridden.add(exerciseId);
    _correct++;
    final out = <ReviewEvent>[];
    for (final e in _verdicts[exerciseId]!.$2) {
      if (e.correct) continue;
      final o = ReviewEvent(
        id: const Uuid().v4(),
        facetId: e.facetId,
        at: clock().toUtc().add(const Duration(milliseconds: 1)),
        rating: Rating.good,
        exerciseType: kOverrideType,
        inputMode: InputMode.self,
        responseMs: 0,
        correct: true,
        answer: e.id,
        sessionId: id,
        mode: mode.name,
      );
      await store.record(o);
      out.add(o);
      _mistakes.remove(e.facetId);
    }
    return out;
  }

  @override
  Future<Result> submit(Exercise exercise, Answer answer, {required Duration elapsed}) async {
    final result = grader.grade(exercise, answer, elapsed: elapsed);
    _answered++;
    if (result.correct) _correct++;
    final now = clock().toUtc();
    final written = <ReviewEvent>[];
    _verdicts[exercise.id] = (result, written);
    _overridden.remove(exercise.id);
    for (final o in result.outcomes) {
      _facets.add(o.facetId);
      final eventId = const Uuid().v4();
      written.add(ReviewEvent(
        id: eventId,
        facetId: o.facetId,
        at: now,
        rating: o.rating,
        exerciseType: exercise.type.id,
        inputMode: answer.inputMode,
        responseMs: elapsed.inMilliseconds,
        correct: o.correct,
        sessionId: id,
      ));
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

  bool get stopped => _stopped;

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

/// Test out and placement over hand-made exercises: one pass, no re-asks;
/// at the end, units are passed in order until one scores below [passMark],
/// and every facet of the passed units' skills gets a test-out credit.
class DemoAssessmentSession extends DemoPracticeSession implements AssessmentSession {
  DemoAssessmentSession({
    required super.mode,
    required super.source,
    required super.store,
    required super.grader,
    required super.clock,
    required this.course,
    required this.units,
    required this.passMark,
  }) : super(length: source.length, requeueMistakes: false);

  final CourseData course;
  final List<List<String>> units;
  final double passMark;
  final Map<String, (int, int)> _bySkill = {};
  AssessmentOutcome? _outcome;

  @override
  AssessmentOutcome? get outcome => _outcome;

  @override
  Future<Result> submit(Exercise exercise, Answer answer, {required Duration elapsed}) async {
    final r = await super.submit(exercise, answer, elapsed: elapsed);
    final k = exercise.skillId ?? '';
    final (c, n) = _bySkill[k] ?? (0, 0);
    _bySkill[k] = (c + (r.correct ? 1 : 0), n + 1);
    return r;
  }

  @override
  Future<Exercise?> next() async {
    final e = await super.next();
    if (e == null && !stopped && _outcome == null) _outcome = await _conclude();
    return e;
  }

  Future<AssessmentOutcome> _conclude() async {
    final credited = <String>[];
    final passedUnits = <String>[];
    String? failed;
    for (var i = 0; i < units.length; i++) {
      var c = 0, n = 0;
      for (final s in units[i]) {
        final (sc, sn) = _bySkill[s] ?? (0, 0);
        c += sc;
        n += sn;
      }
      if (n == 0) continue;
      if (c / n < passMark) {
        failed = mode == SessionMode.placement && i < course.units.length ? course.units[i].id : null;
        break;
      }
      credited.addAll(units[i]);
      if (mode == SessionMode.placement && i < course.units.length) passedUnits.add(course.units[i].id);
    }
    final now = clock().toUtc();
    for (final skill in credited) {
      for (final f in course.skillFacets(skill)) {
        final st = await store.state(f.facetId);
        if (st != null && st.reps > 0 && st.phase != CardPhase.learning) continue;
        await store.record(
          ReviewEvent(
            id: const Uuid().v4(),
            facetId: f.facetId,
            at: now,
            rating: Rating.easy,
            exerciseType: kTestOutCreditType,
            inputMode: InputMode.self,
            responseMs: 0,
            correct: true,
            sessionId: id,
            mode: mode.name,
          ),
        );
      }
    }
    return AssessmentOutcome(
      passed: credited.isNotEmpty,
      correct: correctCount,
      total: answered,
      passMark: passMark,
      creditedSkills: credited,
      passedUnits: passedUnits,
      failedUnit: failed,
      placedUnit: mode == SessionMode.placement ? failed : null,
    );
  }
}
