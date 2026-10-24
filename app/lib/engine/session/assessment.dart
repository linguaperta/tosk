/// Test-out, placement and "tough words" sessions.
///
/// * **Test out** (`factory.testOut(skillId)`, mode `testOut`): about 10
///   production-leaning exercises over one skill's facets, no re-asks. Passing
///   (score >= pass mark, default 80 %) credits every not-yet-learned facet of
///   the skill with one `kTestOutCreditType` event (Easy), so the skill is
///   bronze and the skills after it unlock. Log-derived, so it syncs.
/// * **Placement** (`factory.placement()`, mode `placement`): adaptive by
///   unit over the main tree (a probe of 2 per unit, 2 more when mixed,
///   jumps ahead after clean passes), stopping after two failed units, at the
///   end or at 40 exercises; credits the passed units for a light review
///   soon ([PlacementSession]). "Skip ahead without a test" writes
///   self-declared credits ([SkipAheadSession]).
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
import '../../core/trees.dart';
import '../course_index.dart';
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
      FacetKind.infl => const {ExerciseType.conjGrid, ExerciseType.cloze, ExerciseType.spotError, ExerciseType.conjPick},
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

/// Shared by test-out, placement and skip-ahead: scoring and crediting.
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

  Future<AssessmentOutcome>? _concluding;

  /// Concludes now (once): the outcome, with its credits written.
  Future<AssessmentOutcome> finish() => _concluding ??= () async {
        final o = await conclude();
        _outcome = o;
        return o;
      }();

  @override
  Future<Exercise?> next() async {
    final e = await super.next();
    if (e == null && !isStopped && _outcome == null) await finish();
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

/// How placement samples and decides (docs/engine.md, "Placement"). The
/// defaults are tuned for main trees of 15–20+ units: a learner who knows
/// everything reaches the last unit in about 20 exercises, and every path
/// stays within [maxExercises].
class PlacementConfig {
  const PlacementConfig({
    this.maxExercises = kPlacementMaxExercises,
    this.probe = 2,
    this.extension = 2,
    this.failuresToStop = 2,
    this.jumpAfter = 2,
    this.maxStride = 2,
  });

  /// The test never asks more than this.
  final int maxExercises;

  /// Exercises first asked per unit: one on its grammar, one on its core
  /// vocabulary. All right: the unit passes; all wrong: it fails.
  final int probe;

  /// Asked more when the probe is mixed; the unit then passes with at most
  /// one wrong answer (3 of 4).
  final int extension;

  /// Failed units that end the test (a clear failure, not one slip).
  final int failuresToStop;

  /// Clean passes in a row (every answer right) after which the test jumps
  /// ahead ([maxStride] units at a time); a passed unit after a jump also
  /// credits the units skipped on the way, and a failed one has them tested.
  final int jumpAfter;
  final int maxStride;

  /// Most wrong answers a unit may have and pass (after the extension).
  int get allowedWrong => 1;
}

/// The default length cap of a placement test.
const int kPlacementMaxExercises = 40;

/// What one placement unit came to.
enum UnitVerdict {
  /// Tested and passed: credited.
  passed,

  /// Tested and failed: not credited.
  failed,

  /// Skipped by a jump and credited because the unit after it passed.
  inferred,
}

class _UnitProbe {
  _UnitProbe(this.index, this.unit, this.skills, this.candidates);

  /// Position in the session's units.
  final int index;
  final Unit unit;
  final List<String> skills;

  /// Facets to ask, in order: grammar and vocabulary skills alternating,
  /// production first.
  final List<SkillFacet> candidates;
  int next = 0;
  int answered = 0;
  int correct = 0;
  UnitVerdict? verdict;

  /// Units skipped by the jump that reached this one (decided with it).
  List<int> skipped = const [];
}

/// The facets placement asks for one unit: the facets its skills introduce
/// (a facet shared with an earlier unit belongs to that unit), grammar
/// skills and vocabulary skills alternating, each skill production first.
List<SkillFacet> placementCandidates(CourseData course, Iterable<String> unitSkills, Random random) {
  final ix = CourseIndex.of(course);
  final own = unitSkills.toSet();
  List<SkillFacet> facetsOf(String skillId) => [
        for (final f in productionFirst(course, skillId, random))
          if (own.contains(ix.introducingSkill(f.facetId) ?? skillId)) f,
      ];
  final grammar = <List<SkillFacet>>[];
  final vocab = <List<SkillFacet>>[];
  for (final id in unitSkills) {
    final facets = facetsOf(id);
    if (facets.isEmpty) continue;
    (course.skill(id)?.kind == SkillKind.grammar ? grammar : vocab).add(facets);
  }
  final lists = <List<SkillFacet>>[
    for (var i = 0; i < max(grammar.length, vocab.length); i++) ...[
      if (i < grammar.length) grammar[i],
      if (i < vocab.length) vocab[i],
    ],
  ];
  final out = <SkillFacet>[];
  final seen = <String>{};
  for (var round = 0; lists.any((l) => round < l.length); round++) {
    for (final l in lists) {
      if (round < l.length && seen.add(l[round].facetId)) out.add(l[round]);
    }
  }
  return out;
}

class PlacementBuilder {
  const PlacementBuilder({this.config = const PlacementConfig()});

  final PlacementConfig config;

  Future<PlacementSession> start(SessionEnv env) async {
    final states = await env.store.allStates(courseId: env.course.meta.id);
    return build(env, {for (final s in states) s.facetId: s});
  }

  PlacementSession build(SessionEnv env, Map<String, FacetState> states) {
    final course = env.course;
    final main = CourseTrees.of(course).mainUnits;
    final units = <_UnitProbe>[];
    final known = <String>[];
    // The main tree only: topics are side trees, entered on their own.
    for (final u in main) {
      final skills = [for (final s in course.skills) if (s.unitId == u.id && course.skillFacets(s.id).isNotEmpty) s.id];
      if (skills.isEmpty) continue;
      final candidates = placementCandidates(course, skills, env.random);
      if (candidates.isEmpty) continue;
      // A unit already learned (a re-run) has nothing to place.
      if (candidates.every((f) => isLearned(states[f.facetId]))) {
        known.add(u.id);
        continue;
      }
      units.add(_UnitProbe(units.length, u, skills, candidates));
    }
    return PlacementSession._(env, states, units, known, config);
  }
}

/// "Find my level" (docs/engine.md, "Placement"): adaptive by unit over the
/// main tree. Each unit gets a probe of [PlacementConfig.probe] exercises
/// (grammar and core vocabulary), extended when mixed; after clean passes in
/// a row the test jumps ahead, and it stops after
/// [PlacementConfig.failuresToStop] failed units, at the last unit, or at
/// [PlacementConfig.maxExercises]. [placeNow] ends it early with what is
/// known. Units passed (and units a passed jump skipped) are credited with
/// light-review credits ([kPlacementCreditRatings]).
class PlacementSession extends _Assessment implements PlacementControl {
  PlacementSession._(super.env, Map<String, FacetState> states, this._units, this._known, this.config)
      : super(mode: SessionMode.placement, states: states, passMark: 0.75);

  final PlacementConfig config;
  final List<_UnitProbe> _units;
  final List<String> _known;
  _UnitProbe? _current;
  int _frontier = -1;
  final List<int> _backTests = [];
  int _failures = 0;
  int _clean = 0;
  bool _done = false;
  bool _placing = false;

  /// Units in course order that the test may ask (units already learned excluded).
  List<Unit> get units => [for (final u in _units) u.unit];

  /// Units already learned before the test (nothing to place; re-runs).
  List<String> get knownUnits => List.unmodifiable(_known);

  /// The unit being tested (null before the first exercise and when done).
  Unit? get currentUnit => _current?.unit;

  /// What each unit came to so far (by unit id).
  Map<String, UnitVerdict> get verdicts => {
        for (final u in _units)
          if (u.verdict != null) u.unit.id: u.verdict!,
      };

  @override
  int get maxExercises => config.maxExercises;

  @override
  int? get targetLength => config.maxExercises;

  @override
  Future<Result> submit(Exercise exercise, Answer answer, {required Duration elapsed}) async {
    final before = answered;
    final r = await super.submit(exercise, answer, elapsed: elapsed);
    final u = _current;
    if (answered > before && u != null) {
      u.answered++;
      if (r.correct) u.correct++;
    }
    return r;
  }

  @override
  Future<AssessmentOutcome?> placeNow() async {
    if (outcome != null) return outcome;
    _placing = true;
    _done = true;
    final o = await finish();
    stop();
    return o;
  }

  int get _budget => config.maxExercises - answered;

  /// The verdict [u]'s answers so far give, or null to ask more. [exhausted]:
  /// nothing more can be asked (no candidates or no budget left).
  UnitVerdict? _decide(_UnitProbe u, {required bool exhausted}) {
    final n = u.answered, c = u.correct, w = n - c;
    if (n >= config.probe && w == 0) return UnitVerdict.passed;
    if (n >= config.probe && c == 0) return UnitVerdict.failed;
    if (w > config.allowedWrong) return UnitVerdict.failed;
    if (n >= config.probe + config.extension) return UnitVerdict.passed;
    if (exhausted && n > 0) return c / n >= passMark ? UnitVerdict.passed : UnitVerdict.failed;
    return null;
  }

  void _settle(_UnitProbe u, UnitVerdict v) {
    u.verdict = v;
    if (v == UnitVerdict.passed) {
      for (final i in u.skipped) {
        _units[i].verdict ??= UnitVerdict.inferred;
      }
      _clean = u.correct == u.answered ? _clean + 1 : 0;
    } else {
      _failures++;
      _clean = 0;
      // A jump that failed: the units it skipped are tested after all.
      _backTests.addAll([for (final i in u.skipped) if (_units[i].verdict == null) i]);
      if (_failures >= config.failuresToStop) _done = true;
    }
    u.skipped = const [];
  }

  /// The next unit to test, or null when the test is over.
  _UnitProbe? _startNext() {
    if (_budget < config.probe) return null;
    _UnitProbe? u;
    if (_backTests.isNotEmpty) {
      u = _units[_backTests.removeAt(0)];
    } else {
      final last = _units.length - 1;
      final left = last - _frontier;
      if (left <= 0) return null;
      var stride = _clean >= config.jumpAfter ? config.maxStride : 1;
      // Long courses: jump further when the units left wouldn't fit the
      // budget (never before the first unit has been asked).
      while (_frontier >= 0 && stride < left && (left / stride).ceil() * config.probe > _budget) {
        stride++;
      }
      final j = min(_frontier + stride, last);
      u = _units[j];
      u.skipped = [for (var i = _frontier + 1; i < j; i++) if (_units[i].verdict == null) i];
      _frontier = j;
    }
    // Ask the unit as to a learner who knows it and every unit before it.
    final upTo = u.unit;
    final main = CourseTrees.of(env.course).mainUnits;
    final unitIds = {for (final m in main.takeWhile((m) => m.id != upTo.id)) m.id, upTo.id};
    setCurrentSkills([for (final s in env.course.skills) if (unitIds.contains(s.unitId)) s.id]);
    return u;
  }

  @override
  SessionSlot? nextQueued() {
    while (!_done) {
      final u = _current ??= _startNext();
      if (u == null) {
        _done = true;
        return null;
      }
      final exhausted = u.next >= u.candidates.length || _budget <= 0;
      final v = _decide(u, exhausted: exhausted);
      if (v != null) {
        _settle(u, v);
        _current = null;
        continue;
      }
      if (exhausted) {
        // Nothing could be asked: decided by the unit after it, like a skipped one.
        _current = null;
        final next = _startNext();
        if (next == null) {
          _done = true;
          return null;
        }
        if (u.index < next.index) {
          next.skipped = [...next.skipped, ...u.skipped, u.index]..sort();
        } else {
          _backTests.add(u.index);
        }
        _current = next;
        continue;
      }
      final f = u.candidates[u.next++];
      return SessionSlot(f, only: productionTypes(f.kind));
    }
    return null;
  }

  @override
  Future<AssessmentOutcome> conclude() async {
    final u = _current;
    if (u != null) {
      // Ended with a unit under way (the budget, or "place me now"): settled
      // only when its answers already decide it.
      final v = _decide(u, exhausted: !_placing);
      if (v != null) _settle(u, v);
      _current = null;
    }
    final course = env.course;
    final credited = creditedUnits([for (final u in _units) (u.unit.id, u.verdict)]).toSet();
    final creditedSkills = [
      for (final u in _units)
        if (credited.contains(u.unit.id)) ...u.skills,
    ];
    await writePlacementCredits(this, creditedSkills, selfDeclared: false);
    final place = placementOf(course, credited: credited, known: _known.toSet());
    final failed = [for (final u in _units) if (u.verdict == UnitVerdict.failed) u.unit.id];
    return AssessmentOutcome(
      passed: credited.isNotEmpty,
      correct: correctCount,
      total: answered,
      passMark: passMark,
      creditedSkills: creditedSkills,
      passedUnits: [for (final u in _units) if (credited.contains(u.unit.id)) u.unit.id],
      failedUnit: failed.firstOrNull,
      placedUnit: place.placed,
      gapUnits: place.gaps,
      inferredUnits: [
        for (final u in _units)
          if (u.verdict == UnitVerdict.inferred && credited.contains(u.unit.id)) u.unit.id,
      ],
      knownUnits: List.of(_known),
    );
  }
}

/// The units a placement credits, from each unit's verdict in course order
/// (null: not asked). Units passed (or skipped by a passed jump) before the
/// first failure are credited. After a failure a pass counts only once the
/// next unit passes too: one lucky pass between failures (a guessed probe)
/// places no one further, while two in a row show the failure was a gap.
List<String> creditedUnits(List<(String unitId, UnitVerdict? verdict)> verdicts) {
  final out = <String>[];
  final pending = <String>[];
  var confirmed = true;
  for (final (id, v) in verdicts) {
    if (v == null) continue;
    if (v == UnitVerdict.failed) {
      confirmed = false;
      pending.clear();
      continue;
    }
    if (confirmed) {
      out.add(id);
      continue;
    }
    pending.add(id);
    if (pending.length >= 2) {
      out.addAll(pending);
      pending.clear();
      confirmed = true;
    }
  }
  return out;
}

/// Where a learner stands on the main tree given the units [credited] now
/// and [known] before: [placed] is the unit after the last one done (null
/// past the end), [gaps] the units before it that are not done (a failed
/// unit between passed ones stays open to practise).
({String? placed, List<String> gaps}) placementOf(
  CourseData course, {
  required Set<String> credited,
  Set<String> known = const {},
}) {
  final main = CourseTrees.of(course).mainUnits;
  bool done(Unit u) =>
      credited.contains(u.id) ||
      known.contains(u.id) ||
      // A unit with nothing to learn (no facets) is done when reached.
      course.skills.where((s) => s.unitId == u.id).every((s) => course.skillFacets(s.id).isEmpty);
  var last = -1;
  for (var i = 0; i < main.length; i++) {
    if (credited.contains(main[i].id) || known.contains(main[i].id)) last = i;
  }
  var p = last + 1;
  while (p < main.length && done(main[p])) {
    p++;
  }
  return (
    placed: p < main.length ? main[p].id : null,
    gaps: [for (var i = 0; i < last; i++) if (!done(main[i])) main[i].id],
  );
}

/// Ratings of the credits a placement writes per facet, 1 ms apart: Good
/// then Easy graduates a new facet into review with a stability of about
/// 3.9 days (FSRS-6 defaults), so it comes back for a light review in about
/// 4 days instead of counting as mastered (a test-out's single Easy gives
/// about 8 days).
const List<Rating> kPlacementCreditRatings = [Rating.good, Rating.easy];

/// Ratings of a self-declared credit ("Skip ahead without a test"): Good
/// twice, stability about 2.3 days, back for review in 2 days.
const List<Rating> kSelfDeclaredCreditRatings = [Rating.good, Rating.good];

/// Writes placement credits for every not-yet-learned facet of [skillIds]
/// through [session] (its id and mode). See [kPlacementCreditRatings].
Future<void> writePlacementCredits(EngineSession session, Iterable<String> skillIds, {required bool selfDeclared}) async {
  final env = session.env;
  final now = env.now();
  final ratings = selfDeclared ? kSelfDeclaredCreditRatings : kPlacementCreditRatings;
  final seen = <String>{};
  for (final skillId in skillIds) {
    for (final f in env.course.skillFacets(skillId)) {
      if (!seen.add(f.facetId)) continue;
      if (isLearned(session.states[f.facetId] ?? await env.store.state(f.facetId))) continue;
      for (var i = 0; i < ratings.length; i++) {
        await session.recordExtra(ReviewEvent(
          id: const Uuid().v4(),
          facetId: f.facetId,
          at: now.add(Duration(milliseconds: i)),
          rating: ratings[i],
          exerciseType: kTestOutCreditType,
          inputMode: InputMode.self,
          responseMs: 0,
          correct: true,
          answer: selfDeclared ? kSelfDeclaredCredit : null,
          sessionId: session.id,
          mode: session.mode.name,
        ));
      }
    }
  }
}

/// "Skip ahead without a test": the learner marks main-tree units as known.
/// Every skill of [unitIds] is credited with [kSelfDeclaredCreditRatings],
/// marked [kSelfDeclaredCredit], mode `placement`. Built and concluded at
/// once: [outcome] is set by [declare].
class SkipAheadSession extends _Assessment {
  SkipAheadSession(super.env, Map<String, FacetState> states, this.unitIds)
      : super(mode: SessionMode.placement, states: states, passMark: 0);

  final List<String> unitIds;

  @override
  int? get targetLength => 0;

  @override
  SessionSlot? nextQueued() => null;

  /// Writes the credits and returns the outcome.
  Future<AssessmentOutcome> declare() => finish();

  @override
  Future<AssessmentOutcome> conclude() async {
    final course = env.course;
    final main = CourseTrees.of(course).mainUnits;
    final chosen = unitIds.toSet();
    final units = [for (final u in main) if (chosen.contains(u.id)) u.id];
    final skills = [
      for (final u in units)
        for (final s in course.skills)
          if (s.unitId == u && course.skillFacets(s.id).isNotEmpty) s.id,
    ];
    await writePlacementCredits(this, skills, selfDeclared: true);
    final place = placementOf(course, credited: units.toSet());
    return AssessmentOutcome(
      passed: units.isNotEmpty,
      correct: 0,
      total: 0,
      passMark: 0,
      creditedSkills: skills,
      passedUnits: units,
      placedUnit: place.placed,
      gapUnits: place.gaps,
      selfDeclared: true,
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
    case FacetKind.infl:
      return [
        SessionSlot(f, only: const {ExerciseType.conjPick, ExerciseType.conjGrid}),
        SessionSlot(f, only: const {ExerciseType.cloze, ExerciseType.spotError, ExerciseType.conjGrid}),
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
