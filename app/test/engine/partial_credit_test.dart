// Partly right sentence answers: the word diff, per-facet credit and how the
// session records it in the review log (docs/engine.md, "Partly right
// sentence answers").
import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fakes.dart';
import 'fixtures/italian_course.dart';
import 'helpers.dart';

final _now = DateTime.utc(2026, 10, 20, 12);
const _elapsed = Duration(seconds: 4);
const _mela = 'it:mela#prod';
const _mangiare = 'it:mangiare#form:presente';

void main() {
  final it = italianCourse();
  late InMemoryProgressStore store;
  late DateTime clock;

  EngineSessionFactory factory({int seed = 1}) => EngineSessionFactory(
        course: it,
        store: store,
        scheduler: const FakeScheduler(),
        options: SessionOptions(sourceLang: 'en', seed: seed),
        clock: () => clock,
      );

  setUp(() {
    store = InMemoryProgressStore();
    clock = _now;
  });

  /// "The boy eats an apple." -> `Il ragazzo mangia una mela.`, testing `mela`.
  SentenceBuilderExercise builder(String id) => SentenceBuilderExercise(
        id: id,
        facetId: _mela,
        skillId: 'cibo',
        prompt: 'The boy eats an apple.',
        tiles: const ['il', 'ragazzo', 'mangia', 'una', 'mela.', 'mangio', 'pane'],
        answers: const [
          ['il', 'ragazzo', 'mangia', 'una', 'mela.'],
        ],
        sentenceId: 's:it4',
        answerTokens: tokenRefsOf(it.sentence('s:it4')!),
      );

  Result grade(Exercise e, Answer a) =>
      defaultTemplates().firstWhere((t) => t.type == e.type).grade(e, a, elapsed: _elapsed);

  group('grading', () {
    test('one wrong word: the tested word is credited, the wrong word is a lapse', () {
      final r = grade(builder('b'), const TilesAnswer(['il', 'ragazzo', 'mangio', 'una', 'mela.']));
      expect(r.correct, isFalse, reason: 'the exercise is still a mistake');
      expect(r.diff!.partial, isTrue);
      expect(AnswerDiff.render(r.diff!.expected), 'Il ragazzo mangia una mela.');
      final byFacet = {for (final o in r.outcomes) o.facetId: o};
      expect(byFacet.keys, {_mela, _mangiare});
      expect(byFacet[_mela]!.correct, isTrue);
      expect(byFacet[_mela]!.partial, isTrue);
      expect(byFacet[_mela]!.rating, Rating.good, reason: 'never Easy for a wrong answer');
      expect(byFacet[_mangiare]!.correct, isFalse);
      expect(byFacet[_mangiare]!.secondary, isTrue);
      expect(byFacet[_mangiare]!.rating, Rating.again);
    });

    test('the tested word wrong: Again for it, nothing for the right words', () {
      final r = grade(builder('b'), const TilesAnswer(['il', 'ragazzo', 'mangia', 'una', 'pane']));
      expect(r.diff!.partial, isTrue);
      expect(r.outcomes.map((o) => (o.facetId, o.correct, o.rating)), [(_mela, false, Rating.again)]);
    });

    test('a misplaced word is no lapse of any word', () {
      final r = grade(builder('b'), const TilesAnswer(['il', 'ragazzo', 'una', 'mela.', 'mangia']));
      expect(r.correct, isFalse);
      expect(r.outcomes.map((o) => (o.facetId, o.correct, o.partial)), [(_mela, true, true)]);
    });

    test('a mostly wrong answer is graded as a whole', () {
      final r = grade(builder('b'), const TilesAnswer(['pane', 'mangio']));
      expect(r.diff!.partial, isFalse);
      expect(r.outcomes.map((o) => (o.facetId, o.correct)), [(_mela, false)]);
    });

    test('a right answer has no diff', () {
      final r = grade(builder('b'), const TilesAnswer(['il', 'ragazzo', 'mangia', 'una', 'mela.']));
      expect(r.correct, isTrue);
      expect(r.diff, isNull);
    });

    test('typed: accents follow the setting', () {
      const e = ClozeExercise(
        id: 'c',
        facetId: 'it:mangiare#form:passato_prossimo',
        before: '',
        after: ' il pane.',
        expected: 'Ho mangiato',
        accepted: ['Ho mangiato'],
      );
      final r = grade(e, const TextAnswer('ho mangiata'));
      expect(r.diff!.partial, isTrue);
      expect(r.diff!.expected.where((t) => t.mark == DiffMark.wrong).map((t) => t.text), ['mangiato']);
      // One facet: whole-answer grading, but the diff is shown.
      expect(r.outcomes.map((o) => (o.facetId, o.correct)), [('it:mangiare#form:passato_prossimo', false)]);
    });

    test('transform: the changed words carry the facet, a copy slip is no lapse', () {
      const e = TransformExercise(
        id: 't',
        facetId: 'it:mangiare#form:passato_prossimo',
        source: 'Io mangio la mela.',
        targetDescription: '→ passato prossimo',
        tiles: ['io', 'ho', 'mangiato', 'la', 'mela', 'pane'],
        answers: [
          ['io', 'ho', 'mangiato', 'la', 'mela'],
        ],
      );
      final slip = grade(e, const TilesAnswer(['io', 'ho', 'mangiato', 'il', 'mela']));
      expect(slip.correct, isFalse);
      expect(slip.outcomes.map((o) => (o.correct, o.partial, o.secondary)), [(true, true, false)]);
      final verb = grade(e, const TilesAnswer(['io', 'ho', 'mangiata', 'la', 'mela']));
      expect(verb.outcomes.map((o) => (o.correct, o.partial)), [(false, false)]);
    });
  });

  group('recording (the review log)', () {
    test('the tested word: Good with correct = false; a studied wrong word: Again and a mistake', () async {
      store.seed(stateWith(_mangiare, stability: 3, now: _now, ago: const Duration(days: 2)));
      final s = await factory().lesson('cibo');
      final r = await s.submit(builder('m1'), const TilesAnswer(['il', 'ragazzo', 'mangio', 'una', 'mela.']), elapsed: _elapsed);
      expect(r.correct, isFalse);
      final ev = {for (final e in store.events) e.facetId: e};
      expect(ev.keys, {_mela, _mangiare});
      expect(ev[_mela]!.rating, Rating.good);
      expect(ev[_mela]!.correct, isFalse, reason: 'the answer was a mistake (XP, accuracy, non-stop replay)');
      expect(ev[_mangiare]!.rating, Rating.again);
      expect(ev[_mangiare]!.correct, isFalse);
      expect(ev[_mela]!.at, ev[_mangiare]!.at, reason: 'one exercise, one instant');
      expect(store.mistakeList.map((m) => m.facetId), [_mangiare]);
      expect(store.mistakeList.single.skillId, 'presente-are', reason: "the wrong word's own skill");
      expect(s.summary().mistakes, [_mangiare]);
      expect(s.pendingRetries, 1, reason: 'the exercise still comes back');
      expect(s.mistakeContext('m1')?.facetId, _mela);
    });

    test('a wrong word the learner has not studied records nothing', () async {
      final s = await factory().lesson('cibo');
      await s.submit(builder('m2'), const TilesAnswer(['il', 'ragazzo', 'mangio', 'una', 'mela.']), elapsed: _elapsed);
      expect(store.events.map((e) => (e.facetId, e.rating, e.correct)), [(_mela, Rating.good, false)]);
      expect(store.mistakeList, isEmpty);
    });

    test('a partly right answer comes back; the retry is practice and records nothing', () async {
      final s = await factory(seed: 7).lab(skillIds: ['cibo'], types: [ExerciseType.sentenceBuilder], length: 3);
      final first = (await s.next())! as SentenceBuilderExercise;
      final words = List.of(first.answers.first);
      final swapped = [words[1], words[0], ...words.skip(2)];
      final r = await s.submit(first, TilesAnswer(swapped), elapsed: _elapsed);
      expect(r.correct, isFalse);
      expect(r.diff!.partial, isTrue);
      expect(store.events.single.facetId, first.facetId);
      expect(store.events.single.rating, Rating.good);
      expect(s.plannedLength, 4);
      final served = <Exercise>[first];
      for (var e = await s.next(); e != null; e = await s.next()) {
        served.add(e);
        await s.submit(e, correctAnswer(e), elapsed: _elapsed);
        clock = clock.add(const Duration(seconds: 30));
      }
      expect(served.length, 4);
      expect(s.isRetry(served.last.id), isTrue);
      expect(served.last.facetId, first.facetId);
      expect(served.last.type, ExerciseType.sentenceBuilder);
      expect([for (final e in store.events) if (e.facetId == first.facetId) e.rating], [Rating.good]);
    });

    test('"I was right" on a partly right answer: the event is overridden, no retry', () async {
      final s = await factory(seed: 7).lab(skillIds: ['cibo'], types: [ExerciseType.sentenceBuilder], length: 2);
      final first = (await s.next())! as SentenceBuilderExercise;
      final words = List.of(first.answers.first);
      await s.submit(first, TilesAnswer([words[1], words[0], ...words.skip(2)]), elapsed: _elapsed);
      expect(s.canOverride(first.id), isTrue);
      final written = await s.overrideAnswer(first.id);
      expect(written.map((e) => e.facetId), [first.facetId]);
      expect(s.pendingRetries, 0);
      expect(s.plannedLength, 2);
    });
  });
}
