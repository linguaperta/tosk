import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fakes.dart';
import 'fixtures/italian_course.dart';
import 'helpers.dart';

final _now = DateTime.utc(2026, 10, 13, 12);
const _elapsed = Duration(seconds: 10);

void main() {
  final it = italianCourse();
  late InMemoryProgressStore store;
  late DateTime clock;

  EngineSessionFactory factory({int seed = 1, AccentStrictness accents = AccentStrictness.lenient}) =>
      EngineSessionFactory(
        course: it,
        store: store,
        scheduler: const FakeScheduler(),
        options: SessionOptions(sourceLang: 'en', seed: seed, accents: accents),
        clock: () => clock,
      );

  setUp(() {
    store = InMemoryProgressStore();
    clock = _now;
  });

  /// Runs a session to the end; [wrong] decides which exercises (0-based) are answered wrong.
  Future<List<Exercise>> drive(PracticeSession s, {bool Function(int i, Exercise e)? wrong, int max = 200}) async {
    final served = <Exercise>[];
    for (var i = 0; i < max; i++) {
      final e = await s.next();
      if (e == null) break;
      served.add(e);
      final w = wrong?.call(i, e) ?? false;
      await s.submit(e, w ? wrongAnswer(e) : correctAnswer(e), elapsed: _elapsed);
      clock = clock.add(const Duration(seconds: 15));
    }
    return served;
  }

  group('lesson plan', () {
    test('due facets first (most overdue first), then up to 5 new, then filler', () {
      final skill = it.skill('presente-are')!;
      FacetState st(String verb, {required Duration due, double stability = 3}) => FacetState(
            facetId: 'it:$verb#form:presente',
            stability: stability,
            difficulty: 5,
            due: _now.add(due),
            lastReview: _now.subtract(const Duration(days: 3)),
            reps: 3,
            lapses: 0,
            phase: CardPhase.review,
          );
      final states = {
        for (final s in [
          st('parlare', due: const Duration(hours: -1)),
          st('mangiare', due: const Duration(days: -2)),
          st('cantare', due: const Duration(days: 4)),
        ])
          s.facetId: s,
      };
      final plan = LessonBuilder(skill, LessonFocus.mixed).plan(it, states, scheduler: const FakeScheduler(), now: _now);
      expect(plan.due.map((f) => f.itemId), ['it:mangiare', 'it:parlare']);
      expect(plan.fresh.map((f) => f.itemId), ['it:lavorare', 'it:abitare', 'it:cominciare', 'it:iniziare']);
      expect(plan.filler.first.itemId, 'it:cantare');
      expect(plan.all.length, 12);
      for (var i = 0; i + 1 < plan.all.length; i++) {
        expect(plan.all[i].facetId, isNot(plan.all[i + 1].facetId), reason: 'immediate repeat at $i');
      }
    });

    test('at most 5 new facets, in introduction order', () {
      final skill = it.skill('persone')!;
      final plan = LessonBuilder(skill, LessonFocus.vocab).plan(it, const {}, scheduler: const FakeScheduler(), now: _now);
      expect(plan.due, isEmpty);
      expect(plan.fresh.map((f) => f.facetId), [for (final f in it.skillFacets('persone').take(5)) f.facetId]);
      expect(plan.all.length, 12);
    });

    test('due facets fill the whole lesson when there are many', () {
      final skill = it.skill('persone')!;
      final states = {
        for (final f in it.skillFacets('persone'))
          f.facetId: stateWith(f.facetId, stability: 2, now: _now, ago: const Duration(days: 3), due: true),
      };
      final plan = LessonBuilder(skill, LessonFocus.vocab).plan(it, states, scheduler: const FakeScheduler(), now: _now);
      expect(plan.due.length, 12);
      expect(plan.fresh, isEmpty);
    });
  });

  group('lesson session', () {
    test('a perfect lesson: 12 exercises, one review event per outcome', () async {
      final s = await factory().lesson('presente-are');
      expect(s.mode, SessionMode.lesson);
      expect(s.plannedLength, 12);
      final served = await drive(s);
      expect(served.length, 12);
      expect(await s.next(), isNull);
      expect(s.answered, 12);
      expect(s.correctCount, 12);
      expect(store.events.length, 12); // grammar facets: one outcome per exercise
      for (final e in store.events) {
        expect(e.sessionId, s.id);
        expect(e.mode, 'lesson');
        expect(e.responseMs, 10000);
        expect(e.correct, isTrue);
        expect(e.rating, anyOf(Rating.good, Rating.easy));
        expect(e.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      }
      expect({for (final e in store.events) e.exerciseType}, isNot(contains('flashcard')));
      expect(store.mistakeList, isEmpty);
      final sum = s.summary();
      expect(sum.answered, 12);
      expect(sum.accuracy, 1.0);
      expect(sum.mistakes, isEmpty);
      expect(sum.facetsPracticed, isNotEmpty);
    });

    test('vocabulary lessons grade match pairs per pair', () async {
      final s = await factory(seed: 3).lesson('persone', focus: LessonFocus.vocab);
      final served = await drive(s);
      final outcomes = served.fold<int>(0, (n, e) => n + e.facetIds.length);
      expect(store.events.length, outcomes);
      expect(served.every((e) => FocusPresets.defaults.typesFor(LessonFocus.vocab).contains(e.type)), isTrue);
    });

    test('a mistake comes back at the end of the lesson; events: Again then Good', () async {
      final s = await factory().lesson('presente-are');
      final results = <AnswerEvent>[];
      s.results.listen(results.add);
      final served = await drive(s, wrong: (i, e) => i == 0);
      final first = served.first;
      final retries = [for (var i = 0; i < served.length; i++) if (s.isRetry(served[i].id)) i];
      expect(retries, [12], reason: 'after the 12 planned exercises');
      expect(served[12].facetId, first.facetId);
      expect(served[12].type, first.type, reason: 'the same thing again: the missed type');
      expect(served.length, 13);
      expect(s.plannedLength, 13);
      expect(s.pendingRetries, 0);
      final later = [for (var i = 1; i < served.length; i++) if (served[i].facetId == first.facetId) i];

      final events = [for (final e in store.events) if (e.facetId == first.facetId) e];
      expect(events.map((e) => e.rating), [Rating.again, Rating.good]);
      expect(events.first.correct, isFalse);

      expect(store.mistakeList.length, 1);
      final m = store.mistakeList.single;
      expect(m.id, events.first.id);
      expect(m.facetId, first.facetId);
      expect(m.exerciseType, first.type.id);
      expect(m.prompt, isNotEmpty);
      expect(m.expected, isNotEmpty);
      expect(m.skillId, 'presente-are');
      expect(m.note, contains('Present tense of -are verbs'));

      await Future<void>.delayed(Duration.zero);
      expect(results.length, served.length);
      expect(results.first.mistake, isNotNull);
      expect(results.first.streak, 0);
      expect(results[1].streak, 1);
      expect(results[later.last].isReask, isTrue);
      expect(s.mistakeContext(first.id)?.note, contains('-are'));
      expect(s.summary().mistakes, [first.facetId]);
    });
  });

  group('retries', () {
    test('a wrong retry comes back again until it is right; nothing more is recorded', () async {
      final s = await factory(seed: 5).lesson('presente-are');
      String? facet;
      var retriesWrong = 0;
      final served = await drive(s, wrong: (i, e) {
        facet ??= e.facetId;
        if (e.facetId != facet) return false;
        // Wrong the first time and on the first retry, right on the second.
        if (!s.isRetry(e.id)) return true;
        return retriesWrong++ < 1;
      });
      final retries = [for (final e in served) if (s.isRetry(e.id)) e];
      expect(retries.map((e) => e.facetId), [facet, facet]);
      expect(served.length, 14);
      expect(s.plannedLength, 14, reason: 'every retry counts in the progress');
      expect(s.answered, s.plannedLength);
      final events = [for (final e in store.events) if (e.facetId == facet) e];
      expect(events.map((e) => e.rating), [Rating.again, Rating.good], reason: 'first attempt + relearning step');
      expect(store.mistakeList.length, 1);
    });

    test('at most 3 retries per facet, then it waits for mistake review', () async {
      final s = await factory(seed: 2).lesson('presente-are');
      String? facet;
      final served = await drive(s, wrong: (i, e) {
        facet ??= e.facetId;
        return e.facetId == facet;
      });
      final retries = [for (final e in served) if (s.isRetry(e.id)) e];
      expect(retries.length, 3);
      expect(retries.every((e) => e.facetId == facet), isTrue);
      expect(served.length, 15);
      expect(s.plannedLength, 15);
      expect(await s.next(), isNull);
      final events = [for (final e in store.events) if (e.facetId == facet) e];
      expect(events.map((e) => e.rating), [Rating.again], reason: 'no double penalty');
      final open = await openMistakes(store: store, course: it, scheduler: const FakeScheduler(), now: clock.add(const Duration(days: 1)));
      expect(open.map((m) => m.facet.facetId), [facet]);
    });

    test('several mistakes come back in the order they were made', () async {
      final s = await factory(seed: 3).lesson('presente-are');
      final missed = <String>[];
      final served = await drive(s, wrong: (i, e) {
        if (i < 3 && !missed.contains(e.facetId)) {
          missed.add(e.facetId);
          return true;
        }
        return false;
      });
      final retries = [for (final e in served) if (s.isRetry(e.id)) e.facetId];
      expect(retries, missed);
      expect(served.length, 12 + missed.length);
    });

    test('pendingRetries tracks the waiting mistakes', () async {
      final s = await factory().lesson('presente-are');
      final e = (await s.next())!;
      expect(s.pendingRetries, 0);
      await s.submit(e, wrongAnswer(e), elapsed: _elapsed);
      expect(s.pendingRetries, 1);
      expect(s.plannedLength, 13);
    });

    test('non-stop: a mistake comes back 4-8 exercises later, then spaced further', () async {
      final s = await factory(seed: 4).nonStop();
      final served = <Exercise>[];
      String? facet;
      for (var i = 0; i < 60; i++) {
        final e = (await s.next())!;
        served.add(e);
        facet ??= e.facetId;
        // The first facet is always answered wrong (it never gets right).
        final wrong = e.facetId == facet && (i == 0 || s.isRetry(e.id));
        await s.submit(e, wrong ? wrongAnswer(e) : correctAnswer(e), elapsed: _elapsed);
        clock = clock.add(const Duration(seconds: 20));
      }
      final at = [for (var i = 0; i < served.length; i++) if (s.isRetry(served[i].id)) i];
      expect(at.length, 3, reason: 'three retries, then mistake review');
      final gaps = [at[0] - 0, at[1] - at[0], at[2] - at[1]];
      expect(gaps[0], inInclusiveRange(4, 8));
      expect(gaps[1], inInclusiveRange(8, 16));
      expect(gaps[2], inInclusiveRange(16, 32));
      expect(endlessRetryGap(1), (4, 8));
      expect(endlessRetryGap(2), (8, 16));
      expect(s.plannedLength, isNull);
    });

    test('non-stop: a retry answered right is not asked again', () async {
      final s = await factory(seed: 6).nonStop();
      String? facet;
      var retries = 0;
      for (var i = 0; i < 40; i++) {
        final e = (await s.next())!;
        facet ??= e.facetId;
        if (s.isRetry(e.id)) retries++;
        final wrong = i == 0;
        await s.submit(e, wrong ? wrongAnswer(e) : correctAnswer(e), elapsed: _elapsed);
        clock = clock.add(const Duration(seconds: 20));
      }
      expect(retries, 1);
      expect(s.pendingRetries, 0);
    });
  });

  group('lesson session: restrictions and grading', () {

    test('skill restrictions hold in lessons (essere-avere has no transform)', () async {
      for (var seed = 0; seed < 4; seed++) {
        store = InMemoryProgressStore();
        final s = await factory(seed: seed).lesson('essere-avere', focus: LessonFocus.grammar);
        final served = await drive(s);
        expect(served, isNotEmpty);
        expect(served.where((e) => e.type == ExerciseType.transform), isEmpty);
      }
    });

    test('unknown skill', () {
      expect(factory().lesson('nope'), throwsArgumentError);
    });

    test('strict accents are applied when grading', () async {
      final s = await factory(accents: AccentStrictness.strict).lesson('essere-avere');
      final cloze = ClozeExercise(
        id: 'manual',
        facetId: 'it:essere#form:presente',
        before: 'La città ',
        after: ' grande.',
        expected: 'è',
        accepted: const ['è'],
      );
      final r = await s.submit(cloze, const TextAnswer('e'), elapsed: _elapsed);
      expect(r.correct, isFalse);
      expect(store.events.single.answer, 'e');
      expect(store.events.single.inputMode, InputMode.keyboard);
    });
  });

  group('lab', () {
    test('only the chosen types, from the chosen skills', () async {
      final s = await factory().lab(skillIds: ['persone', 'presente-are'], types: [ExerciseType.conjPick], length: 8);
      expect(s.mode, SessionMode.lab);
      final served = await drive(s);
      expect(served.length, 8);
      expect(served.every((e) => e.type == ExerciseType.conjPick), isTrue);
      expect(served.every((e) => it.skillsForFacet(e.facetId).contains('presente-are')), isTrue);
      expect(store.events.every((e) => e.mode == 'lab'), isTrue);
    });

    test('the lab overrides skill restrictions (transform on essere-avere)', () async {
      final s = await factory().lab(skillIds: ['essere-avere'], types: [ExerciseType.transform], length: 5);
      final served = await drive(s);
      expect(served.length, 5);
      expect(served.every((e) => e.type == ExerciseType.transform), isTrue);
    });

    test('no applicable facets: an empty session', () async {
      final s = await factory().lab(skillIds: ['saluti'], types: [ExerciseType.conjGrid], length: 5);
      expect(s.plannedLength, 0);
      expect(await s.next(), isNull);
    });
  });

  group('non-stop', () {
    test('endless, unlocks skills as prerequisites are started, bonus rounds', () async {
      final s = await factory().nonStop();
      expect(s.plannedLength, isNull);
      expect(s.unlockedSkills().map((k) => k.id), ['saluti']);
      final results = <AnswerEvent>[];
      s.results.listen(results.add);

      var bonusAsked = false;
      var bonusServed = 0;
      for (var i = 0; i < 60; i++) {
        final unlocked = {for (final k in s.unlockedSkills()) k.id};
        if (!bonusAsked && unlocked.contains('presente-are')) {
          s.enqueueBonus(types: {ExerciseType.conjPick}, count: 3);
          bonusAsked = true;
          for (var b = 0; b < 3; b++) {
            final e = (await s.next())!;
            expect(e.type, ExerciseType.conjPick);
            bonusServed++;
            await s.submit(e, correctAnswer(e), elapsed: _elapsed);
          }
          continue;
        }
        final e = await s.next();
        expect(e, isNotNull, reason: 'non-stop ended at $i');
        final skills = it.skillsForFacet(e!.facetId);
        expect(skills.any(unlocked.contains), isTrue, reason: '${e.facetId} not in $unlocked');
        await s.submit(e, correctAnswer(e), elapsed: _elapsed);
        clock = clock.add(const Duration(minutes: 1));
      }
      expect(bonusServed, 3);
      final unlocked = {for (final k in s.unlockedSkills()) k.id};
      expect(unlocked, containsAll(['saluti', 'persone', 'cibo', 'verbi', 'presente-are']));
      await Future<void>.delayed(Duration.zero);
      expect(results.length, s.answered);
      expect(results.last.streak, s.answered);
      s.stop();
      expect(await s.next(), isNull);
      expect(s.summary().answered, s.answered);
    });

    test('unlock rule: a skill unlocks when every prerequisite has a reviewed facet', () async {
      store.seed(stateWith('it:ciao#rec', stability: 1, now: _now)); // saluti started
      store.seed(stateWith('it:parlare#form:presente', stability: 1, now: _now)); // presente-are started
      final s = await factory().nonStop();
      final unlocked = {for (final k in s.unlockedSkills()) k.id};
      expect(unlocked, containsAll(['saluti', 'persone', 'cibo', 'verbi', 'presente-are', 'presente-ere-ire', 'essere-avere']));
      expect(unlocked, isNot(contains('passato-prossimo'))); // essere-avere not started yet
      expect(unlocked, isNot(contains('articoli'))); // persone not started yet
    });

    test('due facets come first; new ones are mixed in', () async {
      store.seed(stateWith('it:ciao#rec', stability: 1, now: _now, ago: const Duration(days: 2), due: true));
      store.seed(stateWith('it:grazie#rec', stability: 9, now: _now));
      final s = await factory().nonStop();
      final first = (await s.next())!;
      expect(first.facetId, 'it:ciao#rec');
      await s.submit(first, correctAnswer(first), elapsed: _elapsed);
      final seen = <String>[];
      for (var i = 0; i < 8; i++) {
        final e = (await s.next())!;
        seen.add(e.facetId);
        await s.submit(e, correctAnswer(e), elapsed: _elapsed);
      }
      expect(seen.where((f) => f != 'it:ciao#rec' && f != 'it:grazie#rec'), isNotEmpty);
    });
  });

  group('fading', () {
    test('due and lowest-recall facets across skills, no new ones', () async {
      FacetState st(String id, {required int daysAgo, required double stability, bool due = false}) => FacetState(
            facetId: id,
            stability: stability,
            difficulty: 5,
            due: due ? _now.subtract(const Duration(hours: 2)) : _now.add(const Duration(days: 5)),
            lastReview: _now.subtract(Duration(days: daysAgo)),
            reps: 3,
            lapses: 0,
            phase: CardPhase.review,
          );
      for (final s in [
        st('it:ragazzo#rec', daysAgo: 2, stability: 40),
        st('it:pane#rec', daysAgo: 20, stability: 2, due: true),
        st('it:parlare#form:presente', daysAgo: 10, stability: 3),
        st('it:vedere#form:presente', daysAgo: 1, stability: 30),
        st('it:essere#form:passato_prossimo', daysAgo: 4, stability: 1, due: true),
      ]) {
        store.seed(s);
      }
      final s = await factory().fading(length: 3);
      expect(s.mode, SessionMode.review);
      expect(s.plannedLength, 3);
      final served = await drive(s);
      expect(served.map((e) => e.facetId).take(3).toList(), [
        'it:pane#rec',
        'it:essere#form:passato_prossimo',
        'it:parlare#form:presente',
      ]);
      expect(store.events.every((e) => e.mode == 'review'), isTrue);
    });

    test('nothing learned yet: an empty session', () async {
      final s = await factory().fading();
      expect(s.plannedLength, 0);
      expect(await s.next(), isNull);
    });
  });

  group('hooks', () {
    test('NullExplainer is unavailable and silent', () async {
      const x = NullExplainer();
      expect(x.isAvailable, isFalse);
      final ctx = MistakeContext(
        courseId: 'it',
        facetId: 'it:ciao#rec',
        exerciseType: ExerciseType.cloze,
        prompt: 'p',
        expected: 'a',
        given: 'b',
        sourceLang: 'en',
        targetLang: 'it',
      );
      expect(await x.explain(ctx).toList(), isEmpty);
      expect(ctx.cacheKey, 'it:ciao#rec|cloze|a|b');
    });

    test('answer inputs: keyboard is one candidate, recognizers keep the top k', () {
      const k = KeyboardAnswerInput();
      expect(k.mode, InputMode.keyboard);
      expect(k.toAnswer(['ciao']).text, 'ciao');
      final ink = _FakeInk();
      final a = ink.toAnswer(['mangiano', 'mangiamo', 'mangiate', 'mangia']);
      expect(a.inputMode, InputMode.ink);
      expect(a.text, 'mangiano');
      expect(a.candidates, ['mangiamo', 'mangiate']);
      final r = const ClozeTemplate().grade(
        const ClozeExercise(id: 'x', facetId: 'it:mangiare#form:presente', before: '', after: '', expected: 'mangiamo', accepted: ['mangiamo']),
        a,
        elapsed: _elapsed,
      );
      expect(r.correct, isTrue);
    });
  });
}

class _FakeInk extends RecognizerAnswerInput {
  _FakeInk() : super(topK: 3);
  @override
  bool get isAvailable => true;
}
