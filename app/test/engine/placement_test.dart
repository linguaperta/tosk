// Placement (engine/session/placement.dart, placement_items.dart): probes of
// production items without context, the binary search, crediting grammar
// per unit and words per word (the word check), the credits' next-day
// confirmation, skip ahead and re-runs.
import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart' as data;
import 'package:tosk/engine/engine.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/course_builder.dart';
import 'fixtures/italian_course.dart';
import 'helpers.dart';

final _now = DateTime.utc(2026, 10, 13, 12);
const _elapsed = Duration(seconds: 10);

const _persons = ['io', 'tu', 'lui', 'noi', 'voi', 'loro'];
const _endings = ['o', 'i', 'a', 'amo', 'ate', 'ano'];
const _letters = 'bcdfghlmnprstvz';

/// A main tree of [n] units, each with a verb grammar skill (one tense per
/// unit, three verbs) and a vocabulary skill of eight nouns. Units in
/// [vocabOnly] have no grammar skill.
InMemoryCourseData gradedCourse(int n, {Set<int> vocabOnly = const {}}) {
  final b = CourseBuilder(CourseMeta(
    id: 'gx',
    version: '0.1.0',
    title: const {'en': 'Graded'},
    target: 'gx',
    translations: const ['en'],
    persons: _persons,
    tenses: [for (var u = 0; u < n; u++) 't$u'],
    tenseLabels: {
      for (var u = 0; u < n; u++) 't$u': {'en': 'tense ${u + 1}'},
    },
    articles: const [],
    attribution: 'Synthetic test fixture.',
  ));
  const verbs = {'parlare': 'parl', 'vedere': 'ved', 'finire': 'fin'};
  for (var u = 0; u < n; u++) {
    b.unit('u$u', u, 'Unit ${u + 1}', 'Unit ${u + 1}');
    if (u == 0) {
      for (final MapEntry(key: lemma, value: stem) in verbs.entries) {
        b.verb(lemma, ['to $lemma'], tables: {
          for (var t = 0; t < n; t++) 't$t': [for (final e in _endings) '$stem${_letters[t]}|$e'],
        }, irregular: lemma == 'vedere');
      }
    }
    final words = [for (var i = 0; i < 8; i++) 'w${_letters[u]}o${_letters[i]}a'];
    for (var i = 0; i < 8; i++) {
      b.word(words[i], 'noun', en: ['thing ${u + 1}.${i + 1}'], freq: 100 + u * 10 + i, tags: ['unit$u']);
    }
    b.vocabSkill('v$u', 0, 'Words ${u + 1}', 'Woorden', words, requires: [if (u > 0) 'v${u - 1}']);
    if (!vocabOnly.contains(u)) b.verbSkill('g$u', 1, 'Tense ${u + 1}', 'Tijd', 't$u', verbs.keys.toList(), requires: ['v$u']);
  }
  return b.build();
}

void main() {
  final scheduler = FsrsScheduler();
  late data.InMemoryProgressStore store;
  late DateTime clock;
  late CourseData course;

  EngineSessionFactory factory({int seed = 1, InputMode input = InputMode.tap}) => EngineSessionFactory(
    course: course,
    store: store,
    scheduler: scheduler,
    options: SessionOptions(sourceLang: 'en', seed: seed, preferredInput: input),
    clock: () => clock,
  );

  setUp(() {
    store = data.InMemoryProgressStore(scheduler: scheduler);
    clock = _now;
    course = gradedCourse(9);
  });

  /// The 0-based main unit of [e]'s skill.
  int unitOf(Exercise e) => int.parse(course.skill(e.skillId!)!.unitId.substring(1));
  bool isWord(Exercise e) => course.skill(e.skillId!)!.kind == SkillKind.vocab;

  /// Runs a placement; [right] decides each answer (with the exercises served so far).
  Future<List<Exercise>> drive(PlacementSession s, bool Function(Exercise e, List<Exercise> before) right) async {
    final served = <Exercise>[];
    for (var i = 0; i < 200; i++) {
      final e = await s.next();
      if (e == null) break;
      final ok = right(e, served);
      served.add(e);
      await s.submit(e, ok ? correctAnswer(e) : wrongAnswer(e), elapsed: _elapsed);
      clock = clock.add(const Duration(seconds: 15));
    }
    return served;
  }

  Future<PlacementSession> start({int seed = 1, int? max}) =>
      max == null ? factory(seed: seed).placement() : factory(seed: seed).placement(maxExercises: max);

  Future<Map<String, SkillProgress>> tiers() =>
      ProgressionService(store: store, scheduler: scheduler, course: course, clock: () => clock).skillTiers(clock);

  group('probes', () {
    test('every item asks for production without context: whole forms of one verb, words from their meaning', () async {
      final s = await start();
      final served = await drive(s, (_, _) => true);
      expect(served, isNotEmpty);
      for (final e in served) {
        expect(isContextFreeProduction(e), isTrue, reason: '${e.type} ${e.facetId}');
        switch (e) {
          case ConjPickExercise():
            // Tap mode: forms of the same verb only (other persons, other tenses).
            final stem = e.fullForm.substring(0, 3);
            expect(e.endings.every((o) => o.startsWith(stem)), isTrue, reason: '${e.endings}');
            expect(e.endings.toSet().length, e.endings.length);
            expect(e.instruction, 'Give the form');
          case ClozeExercise():
            expect(e.translation, startsWith('thing'));
            expect(e.sentenceId, isNull);
            expect(e.options!.length, 4);
          default:
            fail('unexpected ${e.type}');
        }
      }
    });

    test('a grammar probe: five right of six pass, two wrong fail; a couple of words in between', () async {
      final s = await start();
      // The first grammar item of every probe is wrong: 5 of 6 still passes.
      final served = await drive(s, (e, before) {
        if (isWord(e)) return true;
        final unit = unitOf(e);
        return before.any((b) => !isWord(b) && unitOf(b) == unit);
      });
      expect(s.outcome!.placedUnit, isNull);
      final first = [for (final e in served) if (unitOf(e) == 4) e];
      // 6 grammar items (one wrong, five right) and 2 words after the 2nd and 4th grammar item.
      expect([for (final e in first) isWord(e) ? 'w' : 'g'].join(), 'ggwggwgg');
    });

    test('words in a grammar probe do not decide it', () async {
      final s = await start();
      await drive(s, (e, _) => !isWord(e));
      final o = s.outcome!;
      expect(o.placedUnit, isNull);
      expect(o.passedUnits.length, 9);
      expect(o.wordsKnown, 0, reason: 'no word was produced right');
    });

    test('a second wrong answer ends the probe at once', () async {
      final s = await start();
      final served = await drive(s, (_, _) => false);
      // Each probe stops after two wrong answers.
      final perUnit = <int, int>{};
      for (final e in served) {
        perUnit[unitOf(e)] = (perUnit[unitOf(e)] ?? 0) + 1;
      }
      expect(perUnit.values.every((n) => n == 2 || n == 4), isTrue, reason: '$perUnit');
      expect(s.outcome!.placedUnit, 'u0');
      expect(s.outcome!.passedUnits, isEmpty);
    });

    test('typed answers: the whole form (with or without the pronoun), the word with or without its article', () async {
      course = italianCourse();
      final s = await factory(input: InputMode.keyboard).placement();
      var forms = 0, words = 0;
      for (var i = 0; i < 40; i++) {
        final e = await s.next();
        if (e == null) break;
        Answer a = correctAnswer(e);
        if (e is ConjPickExercise && e.stem.isEmpty) {
          forms++;
          a = TextAnswer(forms.isEven ? e.fullForm : '${e.personLabel} ${e.fullForm}');
          if (e.personLabel.contains('/')) a = TextAnswer(e.fullForm);
        } else if (e is ClozeExercise && isBareCloze(e)) {
          words++;
          final item = course.item(FacetId.parse(e.facetId).itemId)!;
          a = TextAnswer(CourseIndex.of(course).withArticle(item));
        }
        final r = await s.submit(e, a, elapsed: _elapsed);
        expect(r.correct, isTrue, reason: '${e.type} ${e.facetId} ${a is TextAnswer ? a.text : ''}');
      }
      expect(forms, greaterThan(0));
      expect(words, greaterThan(0));
      expect(s.outcome!.placedUnit, isNull);
    });

    test('a compound tense offers the other auxiliary as a wrong form', () async {
      course = italianCourse();
      final f = course.skillFacets('passato-prossimo').firstWhere((f) => f.itemId == 'it:mangiare');
      final ctx = GenContext(course: course, options: const SessionOptions(sourceLang: 'en', seed: 3), random: Random(3));
      final seen = <String>{};
      for (var i = 0; i < 20; i++) {
        final e = placementFormItem(f, ctx)!;
        expect(e.stem, isEmpty);
        expect(e.endings[e.correctIndex], e.fullForm);
        seen.addAll(e.endings);
      }
      expect(seen.any((o) => o.startsWith('sono ') || o.startsWith('sei ') || o.startsWith('è ')), isTrue, reason: '$seen');
    });
  });

  group('the search', () {
    test('the middle unit first, then the middle of what is left; a perfect learner gets everything', () async {
      final s = await start();
      final served = await drive(s, (_, _) => true);
      final o = s.outcome!;
      expect(o.askedUnits, ['u4', 'u6', 'u7', 'u8']);
      expect(o.placedUnit, isNull);
      expect(o.passedUnits, [for (var u = 0; u < 9; u++) 'u$u']);
      expect(o.inferredUnits, ['u0', 'u1', 'u2', 'u3', 'u5']);
      expect(served.length, lessThanOrEqualTo(4 * 7));
      expect(o.failedUnit, isNull);
    });

    test('knows units 1-3: placed into unit 4, the boundary confirmed by a second probe', () async {
      final s = await start();
      await drive(s, (e, _) => unitOf(e) < 3);
      final o = s.outcome!;
      expect(o.askedUnits, ['u1', 'u2', 'u3', 'u4']);
      expect(s.probes['u3'], 2, reason: 'the boundary is confirmed');
      expect(o.passedUnits, ['u0', 'u1', 'u2']);
      expect(o.inferredUnits, ['u0']);
      expect(o.placedUnit, 'u3');
      expect(o.failedUnit, 'u3');
    });

    test('never credits a unit above the last passed probe', () async {
      final s = await start();
      // Knows units 1-3 and, oddly, unit 9: the search never gets there.
      await drive(s, (e, _) => unitOf(e) < 3 || unitOf(e) == 8);
      expect(s.outcome!.passedUnits, ['u0', 'u1', 'u2']);
    });

    test('a near miss is probed again straight away', () async {
      final s = await start();
      // Unit 5's first probe: three right, then two wrong; everything else right.
      var u4 = 0;
      final served = await drive(s, (e, _) {
        if (unitOf(e) != 4 || isWord(e)) return true;
        u4++;
        return u4 <= 3 || u4 > 5;
      });
      expect(s.probes['u4'], 2);
      // The second probe follows the first one directly.
      final units = [for (final e in served) unitOf(e)];
      final firstOther = units.indexWhere((u) => u != 4);
      expect(units.take(firstOther).where((u) => u == 4).length, greaterThan(6));
      expect(s.outcome!.placedUnit, isNull);
    });

    test('units without grammar are asked after the search, one by one', () async {
      course = gradedCourse(9, vocabOnly: {8});
      final s = await start();
      // Knows every grammar point and few words.
      await drive(s, (e, _) => !isWord(e));
      final o = s.outcome!;
      expect(o.askedUnits.last, 'u8');
      expect(o.passedUnits.length, 8);
      expect(o.placedUnit, 'u8');
      // A unit without grammar in the middle counts with the units around it.
      course = gradedCourse(9, vocabOnly: {2});
      store = data.InMemoryProgressStore(scheduler: scheduler);
      final t = await start();
      await drive(t, (e, _) => !isWord(e));
      expect(t.outcome!.passedUnits, contains('u2'));
      expect(t.outcome!.askedUnits, isNot(contains('u2')));
    });

    test('"place me now": a probe under way counts only when its answers decide it', () async {
      final s = await start();
      for (var i = 0; i < 3; i++) {
        final e = (await s.next())!;
        await s.submit(e, correctAnswer(e), elapsed: _elapsed);
      }
      final o = (await s.placeNow())!;
      expect(o.passedUnits, isEmpty);
      expect(o.placedUnit, 'u0');
      expect(await s.next(), isNull);
      expect(s.outcome, same(o));
      expect((await store.log()).where((e) => e.isCredit), isEmpty);
    });

    test('the length cap holds; no probe starts that could not pass', () async {
      final s = await start(max: 8);
      final served = await drive(s, (_, _) => true);
      // The first probe passed with five items (no words: the budget is short);
      // three items left cannot pass a probe, so none starts.
      expect(served.length, 5);
      expect(s.outcome!.passedUnits, [for (var u = 0; u <= 4; u++) 'u$u']);
    });

    test('"I was right" counts for the probe', () async {
      final s = await start();
      var overridden = 0;
      for (var i = 0; i < 200; i++) {
        final e = await s.next();
        if (e == null) break;
        // Every grammar item is graded wrong, then "I was right".
        if (!isWord(e)) {
          await s.submit(e, wrongAnswer(e), elapsed: _elapsed);
          await s.overrideAnswer(e.id);
          overridden++;
        } else {
          await s.submit(e, correctAnswer(e), elapsed: _elapsed);
        }
      }
      expect(overridden, greaterThan(0));
      expect(s.outcome!.placedUnit, isNull);
    });
  });

  group('credits', () {
    test('grammar per unit, back the next day; words only once checked', () async {
      final s = await start();
      await drive(s, (e, _) => !isWord(e));
      expect(s.wordCheck, isNotNull);
      final log = await store.log();
      final credits = log.where((e) => e.isCredit).toList();
      expect(credits, isNotEmpty);
      expect(credits.every((e) => e.facetId.contains('#form:')), isTrue, reason: 'grammar only before the word check');
      final byFacet = <String, List<ReviewEvent>>{};
      for (final e in credits) {
        (byFacet[e.facetId] ??= []).add(e);
      }
      var fresh = 0;
      for (final MapEntry(key: id, value: list) in byFacet.entries) {
        final st = (await store.state(id))!;
        expect(st.phase, CardPhase.review, reason: id);
        final asked = log.any((e) => e.facetId == id && !e.isCredit);
        if (!asked) {
          fresh++;
          expect(list.map((e) => e.rating), kPlacementCreditRatings);
          expect(st.due.difference(clock).inHours, inInclusiveRange(20, 36), reason: 'back the next day: $id');
        } else {
          expect(st.due.difference(clock).inHours, lessThanOrEqualTo(60), reason: 'an asked facet: within two days');
        }
      }
      expect(fresh, greaterThan(0));
      final t = await tiers();
      for (var u = 0; u < 9; u++) {
        expect(t['g$u']!.tier, SkillTier.bronze, reason: 'g$u');
        expect(t['v$u']!.tier, isNot(SkillTier.bronze), reason: 'v$u: its words are not checked yet');
      }
    });

    test('a lapse at the next-day confirmation is an ordinary FSRS lapse', () async {
      final s = await start();
      await drive(s, (_, _) => true);
      await s.confirmWords(const []);
      final id = (await store.log()).firstWhere((e) => e.isCredit && e.rating == Rating.hard).facetId;
      final before = (await store.state(id))!;
      clock = before.due;
      final after = (await store.record(ReviewEvent(
        id: 'lapse',
        facetId: id,
        at: clock,
        rating: Rating.again,
        exerciseType: 'cloze',
        inputMode: InputMode.keyboard,
        responseMs: 4000,
        correct: false,
      )))!;
      expect(after.lapses, 1);
      expect(after.phase, CardPhase.relearning);
      expect(after.stability, lessThan(before.stability));
      expect(after.due.difference(clock).inMinutes, lessThanOrEqualTo(10));
      final skill = course.skillsForFacet(id).first;
      final t = await tiers();
      expect(t[skill]!.strength, lessThan(1));
    });

    test('the word check: the still-new words of the credited units, by unit and skill', () async {
      final s = await start();
      final served = await drive(s, (e, _) => unitOf(e) < 3);
      final o = s.outcome!;
      final plan = s.wordCheck!;
      expect([for (final u in plan.units) u.unitId], ['u0', 'u1', 'u2']);
      final rightInTest = {
        for (final e in served)
          if (isWord(e) && unitOf(e) < 3) FacetId.parse(e.facetId).itemId,
      };
      expect(plan.knownFromTest, rightInTest.length);
      final planned = {for (final u in plan.units) for (final sk in u.skills) for (final w in sk.words) w.itemId};
      expect(planned.intersection(rightInTest), isEmpty, reason: 'words produced right in the test are not asked again');
      expect(planned.length + rightInTest.length, 24);
      expect(o.wordsTotal, 24);
      expect(o.wordsKnown, rightInTest.length);
      expect(o.wordsChecked, isFalse);
      final w = plan.units.first.skills.first.words.first;
      expect(w.prompt, startsWith('thing 1.'));
      expect(w.accepted, contains(w.answer));
    });

    test('confirmWords credits the confirmed words only (once); the rest stay new', () async {
      final s = await start();
      await drive(s, (e, _) => unitOf(e) < 3 && !isWord(e));
      final plan = s.wordCheck!;
      final all = [for (final u in plan.units) for (final sk in u.skills) for (final w in sk.words) w.itemId];
      final known = all.take(5).toList();
      final o = await s.confirmWords([...known, 'gx:nothing']);
      expect(o.wordsKnown, 5);
      expect(o.wordsTotal, 24);
      expect(o.wordsChecked, isTrue);
      expect(s.outcome, same(o));
      for (final id in known) {
        expect((await store.state('$id#prod'))!.phase, CardPhase.review);
        expect((await store.state('$id#rec'))!.phase, CardPhase.review);
      }
      for (final id in all.skip(5)) {
        expect(isLearned(await store.state('$id#prod')), isFalse, reason: 'stays new');
      }
      // Once.
      final again = await s.confirmWords(all);
      expect(again.wordsKnown, 5);
      // Replays agree.
      final before = {for (final st in await store.allStates()) st.facetId: st};
      await store.rebuildStates();
      expect({for (final st in await store.allStates()) st.facetId: st}, before);
    });

    test('a re-run starts where the learner is and only adds', () async {
      final first = await start();
      await drive(first, (e, _) => unitOf(e) < 3);
      await first.confirmWords(const []);
      final again = await start(seed: 2);
      expect(again.knownUnits, ['u0', 'u1', 'u2']);
      final served = await drive(again, (_, _) => true);
      expect(served.every((e) => unitOf(e) >= 3), isTrue);
      expect(again.outcome!.placedUnit, isNull);
      expect(again.outcome!.passedUnits, [for (var u = 3; u < 9; u++) 'u$u']);
      // The word check also offers the earlier units' words that are still new.
      expect(again.wordCheck!.units.first.unitId, 'u0');
    });

    test('skip ahead: self-declared credits, back the next day, weaker than tested ones', () async {
      final o = await factory().skipAhead(['u0', 'u1']);
      expect(o.selfDeclared, isTrue);
      expect(o.passedUnits, ['u0', 'u1']);
      expect(o.placedUnit, 'u2');
      final credits = (await store.log()).where((e) => e.isCredit).toList();
      expect(credits.every((e) => e.isSelfDeclared && e.mode == 'placement' && e.answer == kSelfDeclaredCredit), isTrue);
      final f = credits.first.facetId;
      expect(credits.where((e) => e.facetId == f).map((e) => e.rating), kSelfDeclaredCreditRatings);
      final st = (await store.state(f))!;
      expect(st.phase, CardPhase.review);
      expect(st.due.difference(clock).inHours, inInclusiveRange(20, 36));
      // Weaker than a tested credit (lower stability: it fades first).
      final tested = scheduler.review('x', scheduler.review('x', scheduler.review('x', null, Rating.hard, clock), Rating.good, clock), Rating.good, clock);
      expect(st.stability, lessThan(tested.stability));
      final t = await tiers();
      expect(t['v1']!.tier, SkillTier.bronze);
      expect(t['g1']!.tier, SkillTier.bronze);
      expect(t['g2']!.tier, isNot(SkillTier.bronze));
    });
  });

  group('WordCheckRun', () {
    WordCheckPlan plan(List<int> sizes) => WordCheckPlan(units: [
          WordCheckUnit(unitId: 'a', skills: [
            for (final (i, n) in sizes.indexed)
              WordCheckSkill(skillId: 's$i', words: [
                for (var w = 0; w < n; w++) WordCheckWord(itemId: 's$i.$w', prompt: 'p', answer: 'a'),
              ]),
          ]),
          WordCheckUnit(unitId: 'b', skills: [
            WordCheckSkill(skillId: 't', words: [for (var w = 0; w < 3; w++) WordCheckWord(itemId: 't.$w', prompt: 'p', answer: 'a')]),
          ]),
        ]);

    test('a good sample offers to mark the rest; marking it credits them', () {
      final r = WordCheckRun(plan([20]));
      for (var i = 0; i < 6; i++) {
        expect(r.step, WordCheckStep.word);
        expect(r.roundSize, 6);
        r.answer(true);
      }
      expect(r.step, WordCheckStep.offer);
      expect(r.restCount, 14);
      r.markRest();
      expect(r.known.length, 20);
      expect(r.unit!.unitId, 'b');
    });

    test('a weak sample checks every word of the skill', () {
      final r = WordCheckRun(plan([20]));
      r.answer(false);
      for (var i = 0; i < 5; i++) {
        r.answer(true);
      }
      expect(r.step, WordCheckStep.word);
      expect(r.checkingAll, isTrue);
      expect(r.roundSize, 20);
      expect(r.position, 7);
      for (var i = 0; i < 14; i++) {
        r.answer(i.isEven);
      }
      expect(r.known.length, 5 + 7);
      expect(r.unit!.unitId, 'b');
    });

    test('"check them one by one", small skills whole, skipping a unit, stopping', () {
      final r = WordCheckRun(plan([10, 4]));
      for (var i = 0; i < 6; i++) {
        r.answer(true);
      }
      r.checkRest();
      expect(r.step, WordCheckStep.word);
      for (var i = 0; i < 4; i++) {
        r.answer(false);
      }
      // The small skill (4 <= 6 + 2) is asked whole, no offer.
      expect(r.skill!.skillId, 's1');
      expect(r.roundSize, 4);
      r.answer(true);
      r.skipUnit();
      expect(r.unit!.unitId, 'b');
      r.answer(true);
      r.stop();
      expect(r.isDone, isTrue);
      expect(r.known, {'s0.0', 's0.1', 's0.2', 's0.3', 's0.4', 's0.5', 's1.0', 't.0'});
    });
  });
}
