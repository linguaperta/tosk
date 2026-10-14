/// Shared session machinery: serving exercises, grading, writing review
/// events and mistakes, re-queuing mistakes, and the result stream.
library;

import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../../core/interfaces/course_data.dart';
import '../../core/interfaces/hooks.dart';
import '../../core/interfaces/progress_store.dart';
import '../../core/interfaces/session.dart';
import '../../core/models/exercise.dart';
import '../../core/models/facet.dart';
import '../../core/models/progress.dart';
import '../debug/exercise_printer.dart';
import '../gating.dart';
import '../gen_context.dart';
import '../grading/rating.dart';
import '../selector.dart';

/// Dependencies shared by every session of one course.
class SessionEnv {
  SessionEnv({
    required this.course,
    required this.store,
    required this.scheduler,
    required this.options,
    ExerciseSelector? selector,
    this.rating = const RatingPolicy(),
    this.stagePolicy = const StagePolicy(),
    DateTime Function()? clock,
    Random? random,
  })  : selector = selector ?? ExerciseSelector(),
        clock = clock ?? (() => DateTime.now().toUtc()),
        random = random ?? (options.seed == null ? Random() : Random(options.seed));

  final CourseData course;
  final ProgressStore store;
  final Scheduler scheduler;
  final SessionOptions options;
  final ExerciseSelector selector;
  final RatingPolicy rating;
  final StagePolicy stagePolicy;
  final DateTime Function() clock;
  final Random random;

  DateTime now() => clock().toUtc();
}

/// What to practice next: a facet, optionally restricted to some types.
class SessionSlot {
  const SessionSlot(this.facet, {this.only, this.reask = false, this.avoid});
  final SkillFacet facet;
  final Set<ExerciseType>? only;

  /// A mistake asked again later in the same session.
  final bool reask;

  /// Exercise type to prefer not to repeat (the one answered wrong).
  final ExerciseType? avoid;
}

/// Emitted after every graded answer: the hook point for progression
/// (XP, combos, bonus rounds) and for the UI's "Why?" button.
class AnswerEvent {
  const AnswerEvent({
    required this.sessionId,
    required this.mode,
    required this.exercise,
    required this.result,
    required this.events,
    required this.states,
    required this.answered,
    required this.correctCount,
    required this.streak,
    required this.isReask,
    this.mistake,
  });

  final String sessionId;
  final SessionMode mode;
  final Exercise exercise;
  final Result result;

  /// Review events written for this answer (see docs/engine.md for the re-ask policy).
  final List<ReviewEvent> events;

  /// New facet states returned by the store for [events].
  final Map<String, FacetState> states;
  final int answered;
  final int correctCount;

  /// Consecutive correct answers including this one (0 after a wrong answer).
  final int streak;
  final bool isReask;
  final MistakeContext? mistake;
}

class _Served {
  _Served(this.exercise, this.slot);
  final Exercise exercise;
  final SessionSlot slot;
  bool answered = false;
  Result? result;

  /// Events this answer recorded.
  List<ReviewEvent> events = const [];
  bool overridden = false;
}

/// Base class of every engine session. Subclasses decide what comes next
/// ([nextSlot], [targetLength]); this class serves, grades and records.
///
/// Review-event policy (no double penalty): per facet and session, the first
/// wrong answer writes one `Again` event. After that, wrong answers on the
/// same facet (re-asks or later exercises) write nothing; the first correct
/// answer after the mistake writes one `Good` (never `Easy`) as the
/// relearning step; later answers on that facet write nothing. Facets never
/// answered wrong in the session write an event for every answer.
abstract class EngineSession implements PracticeSession, OverridableSession {
  EngineSession(this.env, {required this.mode, required Map<String, FacetState> states, this.maxReasks = 2})
      : id = const Uuid().v4(),
        _states = Map.of(states) {
    startedAt = env.now();
  }

  final SessionEnv env;
  @override
  final String id;
  @override
  final SessionMode mode;

  /// How many times one facet may be re-queued after mistakes.
  final int maxReasks;

  final Map<String, FacetState> _states;
  late final DateTime startedAt;
  DateTime? _endedAt;
  bool _stopped = false;

  int _answered = 0;
  int _correct = 0;
  int _streak = 0;
  int _servedTotal = 0;
  int _servedPlanned = 0;
  int _requeuedTotal = 0;
  ExerciseType? _lastType;
  final List<ExerciseType> _recentTypes = [];
  final List<String> _recentFacets = [];
  Future<void>? _prepared;
  SentenceGate? _gate;
  SentenceHistory? _history;

  final Map<String, _Served> _served = {};
  final List<(int, SessionSlot)> _requeue = []; // (due exercise number, slot)
  final Map<String, int> _reaskCount = {};
  final Set<String> _mistaken = {};
  final Set<String> _recovered = {};
  final Set<String> _practiced = {};
  final List<String> _mistakeOrder = [];
  final Map<String, MistakeContext> _mistakes = {};
  final StreamController<AnswerEvent> _events = StreamController.broadcast();

  // ------------------------------------------------------------ subclass API

  /// Planned number of (non-re-ask) exercises; null = endless.
  int? get targetLength;

  /// The next planned slot, or null when there is nothing left to plan.
  /// Called until an exercise can be generated.
  SessionSlot? nextSlot();

  LessonFocus get focus => LessonFocus.mixed;

  /// Lab: the chosen types override the skill's `exercises` restriction.
  bool get ignoreSkillRestriction => false;

  /// Skills whose grammar and words count as known in this session besides
  /// the started ones (grammar gating): the lesson's skill, the lab's skills.
  /// Non-stop, fading and review sessions use started skills only.
  Iterable<String> get currentSkillIds => const [];

  /// Grammar gating for this session (null before [prepare], or when the
  /// course carries no gating data).
  SentenceGate? get gate => _gate;

  /// Recently seen sentences (null before [prepare]).
  SentenceHistory? get sentenceHistory => _history;

  /// Loads what sentence choice needs: the started skills (every facet state
  /// of the course) for grammar gating, and the recently seen sentences.
  /// [next] calls it; call it yourself before using [genContext] directly.
  Future<void> prepare() => _prepared ??= _prepare();

  Future<void> _prepare() async {
    final course = env.course;
    _history = await SentenceHistory.load(env.store, course.meta.id);
    if (!SentenceGate.supports(course)) return;
    final reviewed = <String>{..._states.keys};
    try {
      for (final s in await env.store.allStates(courseId: course.meta.id)) {
        reviewed.add(s.facetId);
      }
    } catch (_) {
      // Without the full log, the session's own states still say something.
    }
    _gate = SentenceGate(
      course,
      started: SentenceGate.startedSkills(course, reviewed),
      current: currentSkillIds,
    );
  }

  /// Writes this session's sentences to the stored history (variety).
  Future<void> saveSentenceHistory() async {
    final h = _history;
    if (h != null) await h.save(env.store, env.course.meta.id);
  }

  /// Number of planned exercises served so far (re-asks excluded).
  int get servedPlanned => _servedPlanned;

  /// Facet states as known to this session (loaded at start, updated on every answer).
  Map<String, FacetState> get states => UnmodifiableMapView(_states);

  /// Facets served in the last few exercises (most recent last).
  List<String> get recentFacets => UnmodifiableListView(_recentFacets);

  // ------------------------------------------------------------ public API

  /// Every graded answer, for progression (combos, bonuses) and analytics.
  Stream<AnswerEvent> get results => _events.stream;

  /// The mistake context of a wrongly answered exercise (for "Why?").
  MistakeContext? mistakeContext(String exerciseId) => _mistakes[exerciseId];

  bool get isStopped => _stopped;

  @override
  int? get plannedLength => targetLength == null ? null : targetLength! + _requeuedTotal;

  @override
  int get answered => _answered;

  @override
  int get correctCount => _correct;

  @override
  Future<Exercise?> next() async {
    if (_stopped) return null;
    await prepare();
    for (var attempt = 0; attempt < 60; attempt++) {
      final number = _servedTotal + 1;
      SessionSlot? slot;
      final dueIdx = _requeue.indexWhere((r) => r.$1 <= number);
      if (dueIdx >= 0) {
        slot = _requeue.removeAt(dueIdx).$2;
      } else if (targetLength == null || _servedPlanned < targetLength!) {
        slot = nextSlot();
      }
      if (slot == null && _requeue.isNotEmpty) {
        slot = _requeue.removeAt(0).$2;
      }
      if (slot == null) {
        await saveSentenceHistory();
        return null;
      }
      final ex = _generate(slot);
      if (ex == null) continue;
      _servedTotal++;
      if (!slot.reask) _servedPlanned++;
      _lastType = ex.type;
      _recentTypes.add(ex.type);
      if (_recentTypes.length > 3) _recentTypes.removeAt(0);
      _recentFacets.add(slot.facet.facetId);
      if (_recentFacets.length > 6) _recentFacets.removeAt(0);
      _served[ex.id] = _Served(ex, slot);
      return ex;
    }
    await saveSentenceHistory();
    return null;
  }

  Exercise? _generate(SessionSlot slot) {
    final ctx = genContext(slot.facet);
    return env.selector.generate(
      slot.facet,
      ctx,
      focus: focus,
      only: slot.only,
      ignoreSkillRestriction: ignoreSkillRestriction,
      avoid: slot.avoid ?? _lastType,
      recent: _recentTypes,
    );
  }

  /// Generation context for [facet] at this moment.
  GenContext genContext(SkillFacet facet) {
    final skill = env.course.skill(facet.skillId);
    return GenContext(
      course: env.course,
      options: env.options,
      random: env.random,
      states: _states,
      skill: skill,
      now: env.now(),
      stagePolicy: env.stagePolicy,
      nextId: () => '$id#${_servedTotal + 1}',
      gate: _gate,
      history: _history,
      wordCap: SentenceGate.capFor(focus, skill),
    );
  }

  @override
  Future<Result> submit(Exercise exercise, Answer answer, {required Duration elapsed}) async {
    final template = env.selector.template(exercise.type);
    if (template == null) throw StateError('No template for ${exercise.type.id}');
    final result = template.grade(
      exercise,
      answer,
      elapsed: elapsed,
      options: GradeOptions(accents: env.options.accents, rating: env.rating),
    );
    final served = _served[exercise.id];
    if (served != null && served.answered) return result; // already recorded
    served?.answered = true;

    _answered++;
    if (result.correct) {
      _correct++;
      _streak++;
    } else {
      _streak = 0;
    }

    final now = env.now();
    final events = <ReviewEvent>[];
    final newStates = <String, FacetState>{};
    MistakeContext? mistake;
    for (final o in result.outcomes) {
      _practiced.add(o.facetId);
      // An answered facet starts its skills: their grammar and words count as known from now on.
      _gate?.markStarted(env.course.skillsForFacet(o.facetId));
      Rating? rating;
      if (!_mistaken.contains(o.facetId)) {
        rating = o.rating;
      } else if (o.correct && !_recovered.contains(o.facetId)) {
        rating = o.rating == Rating.easy ? Rating.good : o.rating;
        _recovered.add(o.facetId);
      }
      String? eventId;
      if (rating != null) {
        final ev = ReviewEvent(
          id: const Uuid().v4(),
          facetId: o.facetId,
          at: now,
          rating: rating,
          exerciseType: exercise.type.id,
          inputMode: answer.inputMode,
          responseMs: elapsed.inMilliseconds,
          correct: o.correct,
          answer: result.given,
          sessionId: id,
          mode: mode.name,
        );
        eventId = ev.id;
        events.add(ev);
        final st = await env.store.record(ev);
        _states[o.facetId] = st;
        newStates[o.facetId] = st;
      }
      if (!o.correct && !_mistaken.contains(o.facetId)) {
        _mistaken.add(o.facetId);
        _mistakeOrder.add(o.facetId);
        final ctx = _mistakeContext(exercise, result, o.facetId, served?.slot, now);
        mistake ??= ctx;
        await env.store.saveMistake(MistakeRecord(
          id: eventId ?? const Uuid().v4(),
          facetId: o.facetId,
          at: now,
          exerciseType: exercise.type.id,
          prompt: ctx.prompt,
          expected: ctx.expected,
          given: ctx.given,
          skillId: ctx.skillId,
          note: ctx.note,
        ));
      }
      if (!o.correct) _requeueFacet(o.facetId, exercise, served?.slot);
    }
    if (!result.correct && mistake == null) {
      // Wrong again on a facet that already has a mistake record: keep a
      // context for "Why?" without storing a second record.
      mistake = _mistakeContext(exercise, result, exercise.facetId, served?.slot, now);
    }
    if (mistake != null) _mistakes[exercise.id] = mistake;
    served?.result = result;
    served?.events = events;

    if (!_events.isClosed) {
      _events.add(AnswerEvent(
        sessionId: id,
        mode: mode,
        exercise: exercise,
        result: result,
        events: events,
        states: newStates,
        answered: _answered,
        correctCount: _correct,
        streak: _streak,
        isReask: served?.slot.reask ?? false,
        mistake: mistake,
      ));
    }
    return result;
  }

  void _requeueFacet(String facetId, Exercise exercise, SessionSlot? slot) {
    final count = _reaskCount[facetId] ?? 0;
    if (count >= maxReasks || _stopped) return;
    final facet = (slot != null && slot.facet.facetId == facetId) ? slot.facet : facetFor(facetId, exercise.skillId);
    if (facet == null) return;
    _reaskCount[facetId] = count + 1;
    final offset = 2 + env.random.nextInt(3); // 2..4 exercises later
    _requeue.add((_servedTotal + offset, SessionSlot(facet, only: slot?.only, reask: true, avoid: exercise.type)));
    _requeue.sort((a, b) => a.$1.compareTo(b.$1));
    _requeuedTotal++;
  }

  /// The [SkillFacet] for [facetId], preferring [skillId].
  SkillFacet? facetFor(String facetId, String? skillId) {
    final course = env.course;
    final skills = [?skillId, ...course.skillsForFacet(facetId)];
    for (final s in skills) {
      for (final f in course.skillFacets(s)) {
        if (f.facetId == facetId) return f;
      }
    }
    return null;
  }

  MistakeContext _mistakeContext(Exercise e, Result r, String facetId, SessionSlot? slot, DateTime at) {
    final course = env.course;
    final skillId = e.skillId ?? slot?.facet.skillId ?? course.skillsForFacet(facetId).firstOrNull;
    String? sentenceId = switch (e) {
      SentenceBuilderExercise() => e.sentenceId,
      ClozeExercise() => e.sentenceId,
      SpotErrorExercise() => e.sentenceId,
      TransformExercise() => e.sentenceId,
      _ => null,
    };
    return MistakeContext(
      courseId: course.meta.id,
      facetId: facetId,
      exerciseType: e.type,
      prompt: exercisePrompt(e),
      expected: r.expected,
      given: r.given,
      sourceLang: env.options.sourceLang,
      targetLang: course.meta.target,
      skillId: skillId,
      note: skillId == null ? null : course.note(skillId, env.options.sourceLang),
      sentenceId: sentenceId,
      at: at,
    );
  }

  @override
  bool canOverride(String exerciseId) {
    final s = _served[exerciseId];
    return s != null && s.answered && !s.overridden && s.result != null && !s.result!.correct;
  }

  @override
  Future<List<ReviewEvent>> overrideAnswer(String exerciseId) async {
    if (!canOverride(exerciseId)) return const [];
    final served = _served[exerciseId]!;
    served.overridden = true;
    _correct++;
    final now = env.now();
    final written = <ReviewEvent>[];
    for (final e in served.events) {
      if (e.correct) continue;
      final ev = ReviewEvent(
        id: const Uuid().v4(),
        facetId: e.facetId,
        // Never before the event it corrects (a clock that went backwards).
        at: now.isAfter(e.at) ? now : e.at.add(const Duration(milliseconds: 1)),
        rating: Rating.good,
        exerciseType: kOverrideType,
        inputMode: InputMode.self,
        responseMs: 0,
        correct: true,
        answer: e.id,
        sessionId: id,
        mode: mode.name,
      );
      written.add(ev);
      _states[e.facetId] = await env.store.record(ev);
      // The facet's mistake is void: no re-asks, and later answers in this
      // session record as usual.
      _mistaken.remove(e.facetId);
      _recovered.remove(e.facetId);
      _mistakeOrder.remove(e.facetId);
      _reaskCount.remove(e.facetId);
      final before = _requeue.length;
      _requeue.removeWhere((r) => r.$2.reask && r.$2.facet.facetId == e.facetId);
      _requeuedTotal -= before - _requeue.length;
    }
    _mistakes.remove(exerciseId);
    return written;
  }

  /// Records [event] outside of [submit] (test-out credits) and updates [states].
  Future<FacetState> recordExtra(ReviewEvent event) async {
    final st = await env.store.record(event);
    _states[event.facetId] = st;
    return st;
  }

  /// Remembers [facetId] as served recently (for subclasses that pick facets).
  bool isRecent(String facetId, {int window = 3}) {
    final n = _recentFacets.length;
    for (var i = max(0, n - window); i < n; i++) {
      if (_recentFacets[i] == facetId) return true;
    }
    return false;
  }

  @override
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _endedAt = env.now();
    _events.close();
    unawaited(saveSentenceHistory());
  }

  @override
  SessionSummary summary() => SessionSummary(
        sessionId: id,
        mode: mode,
        answered: _answered,
        correct: _correct,
        startedAt: startedAt,
        endedAt: _endedAt ?? env.now(),
        facetsPracticed: Set.of(_practiced),
        mistakes: List.of(_mistakeOrder),
      );
}
