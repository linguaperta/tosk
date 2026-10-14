/// Test-out, placement and "tough words" sessions.
///
/// * **Test out** (`factory.testOut(skillId)`, mode `testOut`): about 10
///   production-leaning exercises over one skill's facets, no re-asks. Passing
///   (score >= pass mark, default 80 %) credits every not-yet-learned facet of
///   the skill with one `kTestOutCreditType` event (Easy), so the skill is
///   bronze and the skills after it unlock. Log-derived, so it syncs.
/// * **Placement** (`factory.placement()`, mode `placement`): a few exercises
///   per skill, unit by unit in course order; a unit passes at the pass mark.
///   It stops at the first unit that fails (as soon as the unit can no longer
///   reach the mark) and credits every skill of the units passed before.
/// * **Tough words** (`factory.toughWords()`, mode `review`): leeches, facets
///   with at least `minLapses` lapses, each as a recognition -> production
///   ladder.
library;

import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../core/interfaces/course_data.dart';
import '../../core/interfaces/progress_store.dart';
import '../../core/interfaces/session.dart';
import '../../core/models/course.dart';
import '../../core/models/exercise.dart';
import '../../core/models/facet.dart';
import '../../core/models/progress.dart';
import 'engine_session.dart';

/// Types an assessment may use: everything auto-graded on a single facet
/// (no self-graded flashcards, no multi-facet match pairs).
const Set<ExerciseType> kAssessmentTypes = {
  ExerciseType.multipleChoice,
  ExerciseType.conjPick,
  ExerciseType.conjGrid,
  ExerciseType.sentenceBuilder,
  ExerciseType.cloze,
  ExerciseType.spotError,
  ExerciseType.transform,
  ExerciseType.listenPick,
};

/// Production-leaning types per facet kind, tried first in an assessment.
Set<ExerciseType> productionTypes(FacetKind kind) => switch (kind) {
      FacetKind.rec => const {ExerciseType.multipleChoice},
      FacetKind.prod => const {ExerciseType.sentenceBuilder, ExerciseType.cloze, ExerciseType.multipleChoice},
      FacetKind.form => const {
          ExerciseType.conjGrid,
          ExerciseType.cloze,
          ExerciseType.transform,
          ExerciseType.spotError,
        },
      FacetKind.article => const {ExerciseType.cloze, ExerciseType.spotError, ExerciseType.multipleChoice},
    };

/// Facets of [skillId], production first (prod, form, article), then
/// recognition, each group shuffled with [random].
List<SkillFacet> productionFirst(CourseData course, String skillId, Random random) {
  final facets = course.skillFacets(skillId);
  final prod = [for (final f in facets) if (f.kind != FacetKind.rec) f]..shuffle(random);
  final rec = [for (final f in facets) if (f.kind == FacetKind.rec) f]..shuffle(random);
  return [...prod, ...rec];
}

/// Whether [s] counts as learned (progression's rule: reviewed and out of
/// the initial learning phase).
bool isLearned(FacetState? s) => s != null && s.reps > 0 && s.phase != CardPhase.learning;

/// A session over a queue of slots. When a slot restricted to some types
/// can't be generated, it is retried once with [fallbackTypes] (null: any type).
abstract class _QueuedSession extends EngineSession {
  _QueuedSession(super.env, {required super.mode, required super.states, super.maxReasks});

  Set<ExerciseType>? get fallbackTypes => null;

  SessionSlot? _pending;
  int _pendingServed = -1;

  /// The next slot from the queue, or null.
  SessionSlot? nextQueued();

  @override
  SessionSlot? nextSlot() {
    final pending = _pending;
    if (pending != null && servedPlanned == _pendingServed) {
      _pending = null;
      if (pending.only != null && pending.only != fallbackTypes) {
        return SessionSlot(pending.facet, only: fallbackTypes);
      }
    }
    final slot = nextQueued();
    _pending = slot;
    _pendingServed = servedPlanned;
    return slot;
  }
}

/// Shared by test-out and placement: scoring and crediting.
abstract class _Assessment extends _QueuedSession implements AssessmentSession {
  _Assessment(super.env, {required super.mode, required super.states, required this.passMark})
      : super(maxReasks: 0);

  final double passMark;
  AssessmentOutcome? _outcome;

  @override
  AssessmentOutcome? get outcome => _outcome;

  @override
  Set<ExerciseType>? get fallbackTypes => kAssessmentTypes;

  /// Computes the outcome and writes the credits (called once, at the end).
  Future<AssessmentOutcome> conclude();

  @override
  Future<Exercise?> next() async {
    final e = await super.next();
    if (e == null && !isStopped && _outcome == null) _outcome = await conclude();
    return e;
  }

  /// One Easy credit for every facet of [skillIds] that is not learned yet.
  Future<void> credit(Iterable<String> skillIds) async {
    final now = env.now();
    final seen = <String>{};
    for (final skillId in skillIds) {
      for (final f in env.course.skillFacets(skillId)) {
        if (!seen.add(f.facetId)) continue;
        if (isLearned(states[f.facetId] ?? await env.store.state(f.facetId))) continue;
        await recordExtra(ReviewEvent(
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
        ));
      }
    }
  }
}

// ==================================================================== test out

class TestOutBuilder {
  const TestOutBuilder(this.skill, {this.length = 10, this.passMark = 0.8});

  final Skill skill;
  final int length;
  final double passMark;

  Future<TestOutSession> start(SessionEnv env) async {
    final states = await env.store.states(env.course.skillFacets(skill.id).map((f) => f.facetId));
    return build(env, states);
  }

  TestOutSession build(SessionEnv env, Map<String, FacetState> states) {
    final facets = productionFirst(env.course, skill.id, env.random);
    final plan = <SkillFacet>[
      if (facets.isNotEmpty)
        for (var i = 0; i < length; i++) facets[i % facets.length],
    ];
    return TestOutSession._(env, states, skill, plan, passMark);
  }
}

class TestOutSession extends _Assessment {
  TestOutSession._(super.env, Map<String, FacetState> states, this.skill, this.plan, double passMark)
      : super(mode: SessionMode.testOut, states: states, passMark: passMark);

  final Skill skill;

  /// The facets asked, in order.
  final List<SkillFacet> plan;
  int _i = 0;

  @override
  int? get targetLength => plan.length;

  @override
  SessionSlot? nextQueued() {
    if (_i >= plan.length) return null;
    final f = plan[_i++];
    return SessionSlot(f, only: productionTypes(f.kind));
  }

  @override
  Future<AssessmentOutcome> conclude() async {
    final passed = answered > 0 && correctCount / answered >= passMark;
    if (passed) await credit([skill.id]);
    return AssessmentOutcome(
      passed: passed,
      correct: correctCount,
      total: answered,
      passMark: passMark,
      creditedSkills: passed ? [skill.id] : const [],
    );
  }
}

// ==================================================================== placement

class _UnitPlan {
  _UnitPlan(this.unit, this.skills, this.slots);
  final Unit unit;
  final List<String> skills;
  final List<SkillFacet> slots;
  int correct = 0;
  int answered = 0;
}

class PlacementBuilder {
  const PlacementBuilder({this.perSkill = 2, this.passMark = 0.8});

  final int perSkill;
  final double passMark;

  Future<PlacementSession> start(SessionEnv env) async {
    final states = await env.store.allStates(courseId: env.course.meta.id);
    return build(env, {for (final s in states) s.facetId: s});
  }

  PlacementSession build(SessionEnv env, Map<String, FacetState> states) {
    final course = env.course;
    final units = <_UnitPlan>[];
    for (final u in course.units) {
      final skills = [for (final s in course.skills) if (s.unitId == u.id && course.skillFacets(s.id).isNotEmpty) s.id];
      if (skills.isEmpty) continue;
      final slots = <SkillFacet>[
        for (final s in skills) ...productionFirst(course, s, env.random).take(perSkill),
      ];
      units.add(_UnitPlan(u, skills, slots));
    }
    return PlacementSession._(env, states, units, passMark);
  }
}

class PlacementSession extends _Assessment {
  PlacementSession._(super.env, Map<String, FacetState> states, this._units, double passMark)
      : super(mode: SessionMode.placement, states: states, passMark: passMark);

  final List<_UnitPlan> _units;
  int _u = 0;
  int _k = 0;
  final List<String> _passed = [];
  String? _failed;

  /// Units in test order.
  List<Unit> get units => [for (final u in _units) u.unit];

  /// The unit being tested (null when done).
  Unit? get currentUnit => _u < _units.length ? _units[_u].unit : null;

  @override
  int? get targetLength => _units.fold<int>(0, (n, u) => n + u.slots.length);

  @override
  Future<Result> submit(Exercise exercise, Answer answer, {required Duration elapsed}) async {
    final before = answered;
    final r = await super.submit(exercise, answer, elapsed: elapsed);
    if (answered > before && _u < _units.length) {
      final u = _units[_u];
      u.answered++;
      if (r.correct) u.correct++;
    }
    return r;
  }

  bool _canStillPass(_UnitPlan u) {
    final allowedWrong = (u.slots.length * (1 - passMark) + 1e-9).floor();
    return u.answered - u.correct <= allowedWrong;
  }

  @override
  SessionSlot? nextQueued() {
    while (_u < _units.length && _failed == null) {
      final u = _units[_u];
      if (!_canStillPass(u)) {
        _failed = u.unit.id;
        return null;
      }
      if (_k < u.slots.length) {
        final f = u.slots[_k++];
        return SessionSlot(f, only: productionTypes(f.kind));
      }
      if (!_settle(u)) return null;
    }
    return null;
  }

  /// Unit [u] is done (every slot served and answered: the player asks for
  /// the next exercise only after the answer): records a pass and moves on,
  /// or records the failure. Returns whether to go on.
  bool _settle(_UnitPlan u) {
    if (u.answered > 0) {
      if (u.correct / u.answered >= passMark) {
        _passed.add(u.unit.id);
      } else {
        _failed = u.unit.id;
        return false;
      }
    }
    _u++;
    _k = 0;
    return true;
  }

  @override
  Future<AssessmentOutcome> conclude() async {
    // The last unit ends without another call to [nextQueued].
    if (_failed == null && _u < _units.length && _k >= _units[_u].slots.length) {
      if (!_canStillPass(_units[_u])) {
        _failed = _units[_u].unit.id;
      } else {
        _settle(_units[_u]);
      }
    }
    final credited = [
      for (final u in _units)
        if (_passed.contains(u.unit.id)) ...u.skills,
    ];
    await credit(credited);
    return AssessmentOutcome(
      passed: _passed.isNotEmpty,
      correct: correctCount,
      total: answered,
      passMark: passMark,
      creditedSkills: credited,
      passedUnits: List.of(_passed),
      failedUnit: _failed,
    );
  }
}

// ==================================================================== tough words

/// Default lapse count from which a facet is a "tough word" (leech).
const int kDefaultLeechLapses = 4;

/// Facets of [course] with at least [minLapses] lapses, most lapses first
/// (then lowest recall), one per facet id.
List<SkillFacet> leechFacets(
  CourseData course,
  Map<String, FacetState> states, {
  required Scheduler scheduler,
  required DateTime now,
  int minLapses = kDefaultLeechLapses,
}) {
  final seen = <String>{};
  final out = <SkillFacet>[
    for (final s in course.skills)
      for (final f in course.skillFacets(s.id))
        if ((states[f.facetId]?.lapses ?? 0) >= minLapses && seen.add(f.facetId)) f,
  ];
  out.sort((a, b) {
    final c = states[b.facetId]!.lapses.compareTo(states[a.facetId]!.lapses);
    if (c != 0) return c;
    return scheduler.retrievability(states[a.facetId], now).compareTo(scheduler.retrievability(states[b.facetId], now));
  });
  return out;
}

/// The facet `{itemId}#{kind}` as some skill trains it, or null.
SkillFacet? siblingFacet(CourseData course, String itemId, FacetKind kind) {
  final id = FacetId(itemId, kind).toString();
  for (final s in course.skillsForFacet(id)) {
    for (final f in course.skillFacets(s)) {
      if (f.facetId == id) return f;
    }
  }
  return null;
}

/// The recognition -> production ladder for one tough facet.
List<SessionSlot> leechLadder(CourseData course, SkillFacet f) {
  const mc = {ExerciseType.multipleChoice};
  switch (f.kind) {
    case FacetKind.rec:
      final prod = siblingFacet(course, f.itemId, FacetKind.prod);
      return [
        SessionSlot(f, only: mc),
        SessionSlot(f, only: const {ExerciseType.matchPairs, ExerciseType.multipleChoice}),
        if (prod != null)
          SessionSlot(prod, only: const {ExerciseType.multipleChoice, ExerciseType.cloze, ExerciseType.sentenceBuilder}),
      ];
    case FacetKind.prod:
      final rec = siblingFacet(course, f.itemId, FacetKind.rec);
      return [
        SessionSlot(rec ?? f, only: mc),
        SessionSlot(f, only: mc),
        SessionSlot(f, only: const {ExerciseType.cloze, ExerciseType.sentenceBuilder}),
      ];
    case FacetKind.form:
      return [
        SessionSlot(f, only: const {ExerciseType.conjPick, ExerciseType.conjGrid}),
        SessionSlot(f, only: const {ExerciseType.cloze, ExerciseType.transform, ExerciseType.spotError, ExerciseType.conjGrid}),
      ];
    case FacetKind.article:
      return [
        SessionSlot(f, only: mc),
        SessionSlot(f, only: const {ExerciseType.cloze, ExerciseType.spotError}),
      ];
  }
}

class ToughWordsBuilder {
  const ToughWordsBuilder({this.length = 12, this.minLapses = kDefaultLeechLapses});

  final int length;
  final int minLapses;

  Future<ToughWordsSession> start(SessionEnv env) async {
    final states = await env.store.allStates(courseId: env.course.meta.id);
    return build(env, {for (final s in states) s.facetId: s});
  }

  ToughWordsSession build(SessionEnv env, Map<String, FacetState> states) {
    final leeches = leechFacets(env.course, states, scheduler: env.scheduler, now: env.now(), minLapses: minLapses);
    final queue = <SessionSlot>[];
    for (final f in leeches) {
      final ladder = leechLadder(env.course, f);
      if (queue.isNotEmpty && queue.length + ladder.length > length) break;
      queue.addAll(ladder);
    }
    return ToughWordsSession._(env, states, leeches, queue);
  }
}

class ToughWordsSession extends _QueuedSession {
  ToughWordsSession._(super.env, Map<String, FacetState> states, this.leeches, this._queue)
      : super(mode: SessionMode.review, states: states);

  /// The tough facets, most lapses first.
  final List<SkillFacet> leeches;
  final List<SessionSlot> _queue;
  int _i = 0;

  @override
  int? get targetLength => _queue.length;

  @override
  SessionSlot? nextQueued() => _i < _queue.length ? _queue[_i++] : null;
}
