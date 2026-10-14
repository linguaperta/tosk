// Test out, placement and tough-words sessions (engine/session/assessment.dart).
import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart' as data;
import 'package:tosk/engine/engine.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/italian_course.dart';
import 'helpers.dart';

final _now = DateTime.utc(2026, 10, 13, 12);
const _elapsed = Duration(seconds: 10);

void main() {
  final it = italianCourse();
  final scheduler = FsrsScheduler();
  late data.InMemoryProgressStore store;
  late DateTime clock;

  EngineSessionFactory factory({int seed = 1}) => EngineSessionFactory(
    course: it,
    store: store,
    scheduler: scheduler,
    options: SessionOptions(sourceLang: 'en', seed: seed),
    clock: () => clock,
  );

  setUp(() {
    store = data.InMemoryProgressStore(scheduler: scheduler);
    clock = _now;
  });

  /// Runs [s] to the end; [wrong] decides which exercises are answered wrong.
  Future<List<Exercise>> drive(PracticeSession s, {bool Function(int i, Exercise e)? wrong, int max = 300}) async {
    final served = <Exercise>[];
    for (var i = 0; i < max; i++) {
      final e = await s.next();
      if (e == null) break;
      served.add(e);
      await s.submit(e, (wrong?.call(i, e) ?? false) ? wrongAnswer(e) : correctAnswer(e), elapsed: _elapsed);
      clock = clock.add(const Duration(seconds: 15));
    }
    return served;
  }

  Future<Map<String, SkillProgress>> tiers() =>
      ProgressionService(store: store, scheduler: scheduler, course: it, clock: () => clock).skillTiers(clock);

  group('test out', () {
    test('about 10 production-leaning exercises, no flashcards or match pairs, no re-asks', () async {
      final s = await factory().testOut('persone');
      expect(s.mode, SessionMode.testOut);
      expect(s.plannedLength, 10);
      final served = await drive(s, wrong: (i, _) => i == 0);
      expect(served.length, 10, reason: 'a wrong answer is not re-asked');
      for (final e in served) {
        expect(e.type, isNot(anyOf(ExerciseType.flashcard, ExerciseType.matchPairs)));
        expect(e.skillId, 'persone');
      }
      // persone has 9 items: 9 #prod facets come before any #rec facet.
      expect(served.take(9).every((e) => e.facetId.endsWith('#prod')), isTrue);
    });

    test('passing credits every facet: the skill is bronze and what follows unlocks', () async {
      expect((await tiers())['persone']!.tier, SkillTier.locked);
      expect((await tiers())['saluti']!.tier, SkillTier.available);
      final s = await factory().testOut('saluti');
      await drive(s, wrong: (i, _) => i == 3); // 9 of 10
      final o = s.outcome!;
      expect(o.passed, isTrue);
      expect(o.correct, 9);
      expect(o.total, 10);
      expect(o.creditedSkills, ['saluti']);
      final credits = (await store.log()).where((e) => e.isCredit).toList();
      // Every saluti facet that wasn't graduated by the quiz got exactly one Easy credit.
      expect(credits, isNotEmpty);
      for (final c in credits) {
        expect(c.rating, Rating.easy);
        expect(c.correct, isTrue);
        expect(c.mode, 'testOut');
        expect(c.sessionId, s.id);
      }
      expect({for (final c in credits) c.facetId}.length, credits.length);
      final t = await tiers();
      expect(t['saluti']!.tier, SkillTier.bronze);
      expect(t['persone']!.tier, SkillTier.available, reason: 'its prerequisite is now started');
      // Credits earn no XP and are not counted as reviews.
      final svc = ProgressionService(store: store, scheduler: scheduler, course: it, clock: () => clock);
      final profile = await svc.profile(clock);
      expect(profile.todayReviews, 10);
    });

    test('failing below 80 % credits nothing', () async {
      final s = await factory().testOut('saluti');
      await drive(s, wrong: (i, _) => i < 3); // 7 of 10
      expect(s.outcome!.passed, isFalse);
      expect(s.outcome!.score, closeTo(0.7, 1e-9));
      expect((await store.log()).where((e) => e.isCredit), isEmpty);
      expect((await tiers())['saluti']!.tier, SkillTier.started);
    });

    test('stopping early gives no outcome and no credit', () async {
      final s = await factory().testOut('saluti');
      final e = await s.next();
      await s.submit(e!, correctAnswer(e), elapsed: _elapsed);
      s.stop();
      expect(await s.next(), isNull);
      expect(s.outcome, isNull);
      expect((await store.log()).where((e) => e.isCredit), isEmpty);
    });

    test('a grammar skill is tested with conjugation production', () async {
      final s = await factory().testOut('presente-are');
      final served = await drive(s);
      expect(served, isNotEmpty);
      expect(served.every((e) => e.facetId.contains('#form:presente')), isTrue);
      expect(s.outcome!.passed, isTrue);
      expect((await tiers())['presente-are']!.tier, SkillTier.bronze);
    });
  });

  group('placement', () {
    test('passes units in order and stops at the first failed unit', () async {
      final s = await factory().placement();
      expect(s.mode, SessionMode.placement);
      // Everything right in unit 1, everything wrong afterwards.
      final served = await drive(s, wrong: (i, e) => !_unit1.contains(e.skillId));
      final o = s.outcome!;
      expect(o.passedUnits, ['u1']);
      expect(o.failedUnit, 'u2');
      expect(o.creditedSkills, ['saluti', 'persone', 'cibo']);
      // Stopped as soon as unit 2 could no longer pass (2 per skill, 80 %).
      final u2 = served.where((e) => !_unit1.contains(e.skillId)).length;
      expect(u2, lessThanOrEqualTo(3));
      final t = await tiers();
      for (final skill in ['saluti', 'persone', 'cibo']) {
        expect(t[skill]!.tier, SkillTier.bronze, reason: skill);
      }
      expect(t['presente-are']!.tier, isNot(SkillTier.bronze));
      expect(t['presente-are']!.tier, isNot(SkillTier.locked));
    });

    test('a few exercises per skill, every unit when all is known', () async {
      final s = await factory().placement(perSkill: 1);
      final served = await drive(s);
      final skills = {for (final e in served) e.skillId};
      expect(skills.length, greaterThanOrEqualTo(it.skills.length - 1));
      expect(s.outcome!.failedUnit, isNull);
      expect(s.outcome!.passedUnits, ['u1', 'u2', 'u3']);
      final t = await tiers();
      expect(t.values.every((p) => p.tier.index >= SkillTier.bronze.index), isTrue);
    });

    test('failing the first unit credits nothing', () async {
      final s = await factory().placement();
      await drive(s, wrong: (_, _) => true);
      expect(s.outcome!.passed, isFalse);
      expect(s.outcome!.failedUnit, 'u1');
      expect((await store.log()).where((e) => e.isCredit), isEmpty);
    });
  });

  group('tough words', () {
    FacetState leech(String facetId, int lapses) => FacetState(
      facetId: facetId,
      stability: 1,
      difficulty: 8,
      due: _now.subtract(const Duration(hours: 1)),
      lastReview: _now.subtract(const Duration(days: 1)),
      reps: 10,
      lapses: lapses,
      phase: CardPhase.review,
    );

    test('leechFacets and the progression helper agree on the threshold', () {
      final states = {
        'it:ragazzo#prod': leech('it:ragazzo#prod', 5),
        'it:pane#rec': leech('it:pane#rec', 4),
        'it:mangiare#form:presente': leech('it:mangiare#form:presente', 6),
        'it:grazie#prod': leech('it:grazie#prod', 3),
      };
      final engine = leechFacets(it, states, scheduler: scheduler, now: _now);
      expect(engine.map((f) => f.facetId), ['it:mangiare#form:presente', 'it:ragazzo#prod', 'it:pane#rec']);
      final progression = toughWords(it, states.values);
      expect(progression.map((t) => t.facet.facetId), engine.map((f) => f.facetId));
      expect(toughWords(it, states.values, minLapses: 3).length, 4);
    });

    test('a recognition -> production ladder per tough facet', () {
      final ragazzo = it.skillFacets('persone').firstWhere((f) => f.facetId == 'it:ragazzo#prod');
      final ladder = leechLadder(it, ragazzo);
      expect(ladder.map((s) => s.facet.facetId), ['it:ragazzo#rec', 'it:ragazzo#prod', 'it:ragazzo#prod']);
      expect(ladder.first.only, {ExerciseType.multipleChoice});
      expect(ladder.last.only, {ExerciseType.cloze, ExerciseType.sentenceBuilder});
    });

    test('the session serves only the tough facets and their siblings, recognition first', () async {
      store = _SeededStore(scheduler, [leech('it:ragazzo#prod', 5), leech('it:mangiare#form:presente', 4)]);
      final s = await factory().toughWords();
      expect(s.mode, SessionMode.review);
      expect(s.leeches.length, 2);
      final served = await drive(s);
      expect(served, isNotEmpty);
      final items = {for (final e in served) FacetId.parse(e.facetId).itemId};
      expect(items, {'it:ragazzo', 'it:mangiare'});
      final first = served.first;
      // Most lapses first: ragazzo, starting with recognition.
      expect(first.facetId, 'it:ragazzo#rec');
      expect(first.type, ExerciseType.multipleChoice);
      final form = served.firstWhere((e) => e.facetId == 'it:mangiare#form:presente');
      expect(form.type, anyOf(ExerciseType.conjPick, ExerciseType.conjGrid));
    });

    test('empty without leeches', () async {
      final s = await factory().toughWords();
      expect(s.plannedLength, 0);
      expect(await s.next(), isNull);
    });
  });
}

const _unit1 = {'saluti', 'persone', 'cibo'};

/// The in-memory store with some facet states preset (as if from history).
class _SeededStore extends data.InMemoryProgressStore {
  _SeededStore(Scheduler scheduler, List<FacetState> seeded)
    : _seeded = {for (final s in seeded) s.facetId: s},
      super(scheduler: scheduler);

  final Map<String, FacetState> _seeded;

  @override
  Future<FacetState?> state(String facetId) async => await super.state(facetId) ?? _seeded[facetId];

  @override
  Future<Map<String, FacetState>> states(Iterable<String> facetIds) async => {
    for (final id in facetIds)
      id: ?await state(id),
  };

  @override
  Future<List<FacetState>> allStates({String? courseId}) async {
    final own = {for (final s in await super.allStates(courseId: courseId)) s.facetId: s};
    return [...own.values, for (final s in _seeded.values) if (!own.containsKey(s.facetId)) s];
  }
}
