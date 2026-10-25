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
import '../../core/models/user_word.dart';
import '../debug/exercise_printer.dart';
import '../gating.dart';
import '../gen_context.dart';
import '../grading/rating.dart';
import '../selector.dart';
import 'my_words.dart';

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
    this.userWordsLoader,
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

  /// Loads the learner's own words of the course ("my words"); null: none.
  final Future<Iterable<UserWord>> Function()? userWordsLoader;

  /// The learner's words, once [loadUserWords] ran (the sessions that use
  /// them load them at start: lessons and "My words").
  UserWordPool userWords = UserWordPool.empty;
  Future<UserWordPool>? _userWordsLoad;

  /// Loads [userWords] once (an empty pool when there is no loader or it fails).
  Future<UserWordPool> loadUserWords() => _userWordsLoad ??= () async {
    final load = userWordsLoader;
    if (load == null) return userWords;
    try {
      return userWords = UserWordPool(course.meta.id, await load());
    } catch (_) {
      return userWords;
    }
  }();

  DateTime now() => clock().toUtc();
}

/// What to practice next: a facet, optionally restricted to some types.
class SessionSlot {
  const SessionSlot(this.facet, {this.only, this.reask = false, this.avoid, this.fixed, this.retryType});
  final SkillFacet facet;

  /// A retry asks the facet again with the exercise type that was missed
  /// when that type can be built (a fresh exercise testing the same thing),
  /// else with any type ([only] still applies).
  final ExerciseType? retryType;

  /// Serve this exercise as it is instead of generating one (starred
  /// practice replays a starred exercise). Its id must be unique in the session.
  final Exercise? fixed;
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

/// A mistake waiting to come back: at the end of a finite session ([due]
/// null), or once exercise number [due] is reached in an endless one.
class _Retry {
  _Retry(this.slot, this.due);
  final SessionSlot slot;
  final int? due;
}

/// When an endless session (non-stop) asks a mistake again: retry n
/// (1-based) comes `[4·2^(n−1), 8·2^(n−1)]` exercises later, so 4–8, then
/// 8–16, then 16–32.
(int, int) endlessRetryGap(int n) {
  final lo = 4 << (n - 1);
  return (lo, 2 * lo);
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

/// The sentence a sentence-based exercise shows, or null.
String? sentenceIdOf(Exercise e) => switch (e) {
  SentenceBuilderExercise() => e.sentenceId,
  ClozeExercise() => e.sentenceId,
  SpotErrorExercise() => e.sentenceId,
  TransformExercise() => e.sentenceId,
  ListenPickExercise() => e.sentenceId,
  _ => null,
};

/// Base class of every engine session. Subclasses decide what comes next
/// ([nextSlot], [targetLength]); this class serves, grades and records.
///
/// Review-event policy (no double penalty): per facet and session, the first
/// wrong answer writes one `Again` event. After that, wrong answers on the
/// same facet (re-asks or later exercises) write nothing; the first correct
/// answer after the mistake writes one `Good` (never `Easy`) as the
/// relearning step; later answers on that facet write nothing. Facets never
/// answered wrong in the session write an event for every answer, except in
/// a retry, which is practice: the retried facet records only its
/// relearning step.
///
/// Retries (docs/engine.md, "Retries"): every wrong exercise comes back
/// until it is answered right, at most [maxReasks] times per facet. Finite
/// sessions ask them after the planned exercises, in the order they were
/// missed; endless ones [endlessRetryGap] exercises later.
abstract class EngineSession implements PracticeSession, OverridableSession, RetryingSession {
  EngineSession(this.env, {required this.mode, required Map<String, FacetState> states, this.maxReasks = 3})
      : id = const Uuid().v4(),
        _states = Map.of(states) {
    startedAt = env.now();
  }

  final SessionEnv env;
  @override
  final String id;
  @override
  final SessionMode mode;

  /// How many times one facet may come back after mistakes (then it waits
  /// for mistake review).
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
  final List<_Retry> _requeue = []; // in the order the mistakes were made
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

  /// No exercise could be generated for [slot] (no template can serve its
  /// facet right now, e.g. under grammar gating). Subclasses that pick facets
  /// themselves can skip it from then on.
  void onGenerateFailed(SessionSlot slot) {}

  LessonFocus get focus => LessonFocus.mixed;

  /// Lab: the chosen types override the skill's `exercises` restriction.
  bool get ignoreSkillRestriction => false;

  /// Skills whose grammar and words count as known in this session besides
  /// the started ones (grammar gating): the lesson's skill, the lab's skills.
  /// Non-stop, fading and review sessions use started skills only.
  Iterable<String> get currentSkillIds => const [];

  /// Sentences the templates should pick first when eligible
  /// ([GenContext.preferredSentences]; starred practice).
  Set<String> get preferredSentences => const {};

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
    _gateStarted = SentenceGate.startedSkills(course, reviewed);
    _gate = SentenceGate(course, started: _gateStarted, current: currentSkillIds);
  }

  Set<String> _gateStarted = const {};

  /// Replaces the gate's current skills (placement moves unit by unit, and
  /// each unit is asked as to a learner who knows it and every unit before):
  /// a new gate over the skills started before the session and [current].
  /// No effect without gating or before [prepare].
  void setCurrentSkills(Iterable<String> current) {
    if (_gate == null) return;
    _gate = SentenceGate(env.course, started: _gateStarted, current: current);
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
  int get pendingRetries => _requeue.length;

  @override
  bool isRetry(String exerciseId) => _served[exerciseId]?.slot.reask ?? false;

  /// The spaced retry (endless sessions) whose turn has come, if any.
  SessionSlot? _dueRetry(int number) {
    _Retry? best;
    for (final r in _requeue) {
      final due = r.due;
      if (due != null && due <= number && (best == null || due < best.due!)) best = r;
    }
    if (best == null) return null;
    _requeue.remove(best);
    return best.slot;
  }

  /// The next waiting retry once nothing else is planned: the earliest
  /// mistake (or the earliest due), but not the facet just asked when
  /// another one is waiting.
  SessionSlot? _takeRetry() {
    if (_requeue.isEmpty) return null;
    final order = [..._requeue]..sort((a, b) => (a.due ?? 0).compareTo(b.due ?? 0));
    final last = _recentFacets.isEmpty ? null : _recentFacets.last;
    final r = order.firstWhere((r) => r.slot.facet.facetId != last, orElse: () => order.first);
    _requeue.remove(r);
    return r.slot;
  }

  @override
  Future<Exercise?> next() async {
    if (_stopped) return null;
    await prepare();
    for (var attempt = 0; attempt < 60; attempt++) {
      final number = _servedTotal + 1;
      var slot = _dueRetry(number);
      if (slot == null && (targetLength == null || _servedPlanned < targetLength!)) {
        slot = nextSlot();
      }
      slot ??= _takeRetry();
      if (slot == null) {
        await saveSentenceHistory();
        return null;
      }
      final ex = _generate(slot);
      if (ex == null) {
        // A retry that can't be built any more drops out of the count.
        if (slot.reask) _requeuedTotal--;
        onGenerateFailed(slot);
        continue;
      }
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
    final fixed = slot.fixed;
    if (fixed != null) {
      final sentence = sentenceIdOf(fixed);
      if (sentence != null) _history?.use(sentence);
      return fixed;
    }
    if (isUserFacetId(slot.facet.facetId)) {
      // The learner's own words: their own small generator (docs/engine.md, "My words").
      return env.userWords.generate(
        slot.facet,
        course: env.course,
        options: env.options,
        random: env.random,
        state: _states[slot.facet.facetId],
        nextId: () => '$id#${_servedTotal + 1}',
        stagePolicy: env.stagePolicy,
        only: slot.only,
        retryType: slot.retryType,
        avoid: slot.avoid ?? _lastType,
      );
    }
    final ctx = genContext(slot.facet);
    final retry = slot.retryType;
    if (retry != null && (slot.only == null || slot.only!.contains(retry))) {
      // A retry tests the same thing: the missed type first (a fresh
      // exercise, usually another sentence), any type only when it can't be built.
      final same = env.selector.generate(
        slot.facet,
        ctx,
        focus: focus,
        only: {retry},
        ignoreSkillRestriction: ignoreSkillRestriction,
        recent: const [],
      );
      if (same != null) return same;
    }
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
      preferredSentences: preferredSentences,
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
    final slot = served?.slot;
    final retried = slot != null && slot.reask ? slot.facet.facetId : null;
    for (final o in result.outcomes) {
      // Another word of a partly right answer: only facets the learner studies.
      if (o.secondary && !await _gradesSecondary(o.facetId)) continue;
      _practiced.add(o.facetId);
      // An answered facet starts the skill that introduces it: its grammar and words count as
      // known from now on (not a later skill sharing the facet: SentenceGate.startedSkills).
      _gate?.markStarted(SentenceGate.startedSkills(env.course, [o.facetId]));
      Rating? rating;
      final mistaken = _mistaken.contains(o.facetId);
      if (mistaken) {
        // The relearning step: the first fully right answer after the mistake.
        if (o.correct && !o.partial && !_recovered.contains(o.facetId)) {
          rating = o.rating == Rating.easy ? Rating.good : o.rating;
          _recovered.add(o.facetId);
        }
      } else if (o.facetId != retried) {
        // A retry is practice: its facet's first attempt was graded already.
        rating = o.rating;
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
          // Partial credit: rated Good, but the answer was a mistake.
          correct: o.correct && !o.partial,
          answer: result.given,
          sessionId: id,
          mode: mode.name,
        );
        eventId = ev.id;
        events.add(ev);
        // An answer always gives a state (only a skill reset clears one).
        final st = (await env.store.record(ev))!;
        _states[o.facetId] = st;
        newStates[o.facetId] = st;
      }
      if (!o.correct && !mistaken) {
        _mistaken.add(o.facetId);
        _mistakeOrder.add(o.facetId);
        final ctx = _mistakeContext(exercise, result, o.facetId, served?.slot, now, secondary: o.secondary);
        if (!o.secondary) mistake ??= ctx;
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
    }
    // The wrong exercise comes back: its wrong facets (not the other words of
    // a partly right sentence), or its own facet when only those were wrong.
    final again = <String>{
      for (final o in result.outcomes)
        if (!o.correct && !o.secondary) o.facetId,
    };
    if (!result.correct && again.isEmpty) again.add(exercise.facetId);
    for (final f in again) {
      _requeueFacet(f, exercise, slot);
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

  /// Queues [facetId] to come back (at most [maxReasks] times, once at a time).
  void _requeueFacet(String facetId, Exercise exercise, SessionSlot? slot) {
    final count = _reaskCount[facetId] ?? 0;
    if (count >= maxReasks || _stopped) return;
    if (_requeue.any((r) => r.slot.facet.facetId == facetId)) return;
    final facet = (slot != null && slot.facet.facetId == facetId) ? slot.facet : facetFor(facetId, exercise.skillId);
    if (facet == null) return;
    _reaskCount[facetId] = count + 1;
    int? due;
    if (targetLength == null) {
      final (lo, hi) = endlessRetryGap(count + 1);
      due = _servedTotal + lo + env.random.nextInt(hi - lo + 1);
    }
    _requeue.add(_Retry(SessionSlot(facet, only: slot?.only, reask: true, retryType: exercise.type), due));
    _requeuedTotal++;
  }

  /// A secondary outcome is graded only for a facet the course trains and the
  /// learner has studied: a lapse never introduces a new word.
  Future<bool> _gradesSecondary(String facetId) async {
    if (env.course.skillsForFacet(facetId).isEmpty) return false;
    if (_states.containsKey(facetId)) return true;
    try {
      return await env.store.state(facetId) != null;
    } catch (_) {
      return false;
    }
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

  MistakeContext _mistakeContext(Exercise e, Result r, String facetId, SessionSlot? slot, DateTime at, {bool secondary = false}) {
    final course = env.course;
    // Another word of the sentence: its own skill's note.
    final skillId = secondary
        ? course.skillsForFacet(facetId).firstOrNull
        : e.skillId ?? slot?.facet.skillId ?? course.skillsForFacet(facetId).firstOrNull;
    final sentenceId = sentenceIdOf(e);
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
      _states[e.facetId] = (await env.store.record(ev))!;
      // The facet's mistake is void: no re-asks, and later answers in this
      // session record as usual.
      _mistaken.remove(e.facetId);
      _recovered.remove(e.facetId);
      _mistakeOrder.remove(e.facetId);
      _reaskCount.remove(e.facetId);
      final before = _requeue.length;
      _requeue.removeWhere((r) => r.slot.facet.facetId == e.facetId);
      _requeuedTotal -= before - _requeue.length;
    }
    // The answer was right: it doesn't come back, even where it recorded
    // nothing (a retry) or nothing wrong.
    final again = {
      served.exercise.facetId,
      for (final o in served.result!.outcomes)
        if (!o.correct && !o.secondary) o.facetId,
    };
    final before = _requeue.length;
    _requeue.removeWhere((r) => again.contains(r.slot.facet.facetId));
    _requeuedTotal -= before - _requeue.length;
    _mistakes.remove(exerciseId);
    return written;
  }

  /// Records [event] outside of [submit] (test-out credits) and updates [states].
  Future<FacetState?> recordExtra(ReviewEvent event) async {
    final st = await env.store.record(event);
    if (st == null) {
      _states.remove(event.facetId);
    } else {
      _states[event.facetId] = st;
    }
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
