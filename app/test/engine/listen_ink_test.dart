// v0.5 engine additions: the listen_pick template (text-to-speech capability,
// sound-alike options, word and sentence variants, sessions) and ink answers
// (recognizer candidates for cloze, conjugation pick and grid cells).
import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/feedback/exercise_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fakes.dart';
import 'fixtures/dutch_course.dart';
import 'fixtures/italian_course.dart';
import 'helpers.dart';

final _now = DateTime.utc(2026, 10, 14, 12);
const _elapsed = Duration(seconds: 2);

GenContext _ctx(CourseData c, {int seed = 0, bool listening = true, String? skill, Map<String, FacetState> states = const {}}) =>
    GenContext(
      course: c,
      options: SessionOptions(sourceLang: 'en', listening: listening),
      random: Random(seed),
      states: states,
      skill: skill == null ? null : c.skill(skill),
      now: _now,
    );

FacetState _stable(String id) => FacetState(
      facetId: id,
      stability: 30,
      difficulty: 5,
      due: _now.add(const Duration(days: 10)),
      lastReview: _now.subtract(const Duration(days: 1)),
      reps: 4,
      lapses: 0,
      phase: CardPhase.review,
    );

SkillFacet _facet(CourseData c, String skillId, String facetId) =>
    c.skillFacets(skillId).firstWhere((f) => f.facetId == facetId);

void main() {
  final it = italianCourse();
  final nl = dutchCourse();

  group('soundKey', () {
    test('folds what sounds the same', () {
      expect(soundKey('ha'), soundKey('a'));
      expect(soundKey('È qui.'), soundKey('e qui'));
      expect(soundKey('Hij wordt moe'), soundKey('hij word moe'));
      expect(soundKey('gebeurd'), soundKey('gebeurt'));
      expect(soundKey("l'acqua"), soundKey('la cqua'));
      expect(soundKey('palla'), soundKey('pala'));
    });

    test('keeps what sounds different', () {
      expect(soundKey('mangio'), isNot(soundKey('mangia')));
      expect(soundKey('Deze wijn is lekker'), isNot(soundKey('Deze wijn was lekker')));
      expect(soundKey('non'), isNot(soundKey('no')));
    });
  });

  group('listen_pick', () {
    const t = ListenPickTemplate();
    final rec = _facet(it, 'persone', 'it:ragazzo#rec');

    test('needs text-to-speech: never generated without a voice', () {
      expect(t.canGenerate(rec, _ctx(it, listening: false)), isFalse);
      expect(t.generate(rec, _ctx(it, listening: false)), isNull);
      expect(t.canGenerate(rec, _ctx(it)), isTrue);
      // Recognition only.
      expect(t.supports(_facet(it, 'persone', 'it:ragazzo#prod')), isFalse);
      final selector = ExerciseSelector();
      for (var i = 0; i < 60; i++) {
        final e = selector.generate(rec, _ctx(it, seed: i, listening: false));
        expect(e?.type, isNot(ExerciseType.listenPick));
      }
    });

    test('fresh facets hear the word; options are other words that sound different', () {
      for (var i = 0; i < 30; i++) {
        final e = t.generate(rec, _ctx(it, seed: i)) as ListenPickExercise?;
        expect(e, isNotNull);
        expect(e!.isSentence, isFalse);
        expect(e.text, 'ragazzo');
        expect(e.options[e.correctIndex], e.text);
        expect(e.languageCode, 'it');
        expect(e.translation, isNotEmpty);
        expect(e.options.length, greaterThanOrEqualTo(3));
        final keys = {for (final o in e.options) soundKey(o)};
        expect(keys.length, e.options.length, reason: '${e.options}');
        expect(e.instruction, 'Which word do you hear?');
      }
    });

    test('stable facets hear a sentence with the item, with its translation and tokens', () {
      var sentences = 0;
      for (var i = 0; i < 30; i++) {
        final e = t.generate(rec, _ctx(it, seed: i, states: {rec.facetId: _stable(rec.facetId)})) as ListenPickExercise?;
        if (e == null || !e.isSentence) continue;
        sentences++;
        final s = it.sentence(e.sentenceId!)!;
        expect(e.text, s.text);
        expect(s.tokens.any((x) => x.lex == 'it:ragazzo'), isTrue);
        expect(e.translation, s.translation('en'));
        expect(renderTokenRefs(e.tokens!), s.text);
        expect({for (final o in e.options) soundKey(o)}.length, e.options.length);
      }
      expect(sentences, greaterThan(10));
    });

    test('grading: the spoken option is right, the others wrong; listening is not instant', () {
      final e = t.generate(rec, _ctx(it)) as ListenPickExercise;
      for (var i = 0; i < e.options.length; i++) {
        final r = t.grade(e, ChoiceAnswer(i), elapsed: _elapsed);
        expect(r.correct, i == e.correctIndex);
        expect(r.expected, e.text);
      }
      // 2 s is fast for most types, but listening takes time: Easy below 8 s.
      expect(t.grade(e, ChoiceAnswer(e.correctIndex), elapsed: const Duration(seconds: 9)).outcomes.single.rating, Rating.good);
      expect(t.grade(e, ChoiceAnswer(e.correctIndex), elapsed: _elapsed).outcomes.single.rating, Rating.easy);
    });

    test('Dutch: never two options that sound alike', () {
      for (final f in nl.skillFacets('mensen').where(t.supports)) {
        for (var i = 0; i < 10; i++) {
          final e = const ListenPickTemplate(sentenceShare: 1).generate(f, _ctx(nl, seed: i)) as ListenPickExercise?;
          if (e == null) continue;
          expect({for (final o in e.options) soundKey(o)}.length, e.options.length, reason: '${e.options}');
        }
      }
    });

    test('presets: vocab and mixed lessons favor it, grammar never', () {
      const p = FocusPresets.defaults;
      expect(p.weight(LessonFocus.vocab, ExerciseType.listenPick), greaterThan(0));
      expect(p.weight(LessonFocus.mixed, ExerciseType.listenPick), greaterThan(0));
      expect(p.weight(LessonFocus.grammar, ExerciseType.listenPick), 0);
      expect(ExerciseType.parse('listen_pick'), ExerciseType.listenPick);
    });

    test('snapshot round trip', () {
      final e = t.generate(rec, _ctx(it, states: {rec.facetId: _stable(rec.facetId)})) as ListenPickExercise;
      expect(exercisePrompt(e), contains(e.text));
      expect(formatExercise(e), contains('[listen_pick]'));
      final back = exerciseFromJson(exerciseToJson(e)) as ListenPickExercise;
      expect(back.text, e.text);
      expect(back.options, e.options);
      expect(back.correctIndex, e.correctIndex);
      expect(back.languageCode, e.languageCode);
      expect(back.isSentence, e.isSentence);
      expect(back.sentenceId, e.sentenceId);
      expect(exerciseChoices(e), e.options);
    });
  });

  group('listen_pick in sessions', () {
    late InMemoryProgressStore store;
    EngineSessionFactory factory({required bool listening, int seed = 3}) => EngineSessionFactory(
          course: it,
          store: store,
          scheduler: const FakeScheduler(),
          options: SessionOptions(sourceLang: 'en', seed: seed, listening: listening),
          clock: () => _now,
        );

    setUp(() => store = InMemoryProgressStore());

    Future<List<Exercise>> play(PracticeSession s) async {
      final out = <Exercise>[];
      for (var i = 0; i < 60; i++) {
        final e = await s.next();
        if (e == null) break;
        out.add(e);
        await s.submit(e, correctAnswer(e), elapsed: _elapsed);
      }
      return out;
    }

    test('lab: served only when the device can speak', () async {
      final on = await play(await factory(listening: true)
          .lab(skillIds: ['persone', 'cibo'], types: [ExerciseType.listenPick], length: 6));
      expect(on, isNotEmpty);
      expect(on.every((e) => e is ListenPickExercise), isTrue);
      final off = await play(await factory(listening: false)
          .lab(skillIds: ['persone', 'cibo'], types: [ExerciseType.listenPick], length: 6));
      expect(off, isEmpty);
    });

    test('vocab lessons mix it in with listening on, never with it off', () async {
      var seen = 0;
      for (var seed = 0; seed < 6; seed++) {
        store = InMemoryProgressStore();
        final served = await play(await factory(listening: true, seed: seed).lesson('persone', focus: LessonFocus.vocab));
        seen += served.whereType<ListenPickExercise>().length;
        store = InMemoryProgressStore();
        final silent = await play(await factory(listening: false, seed: seed).lesson('persone', focus: LessonFocus.vocab));
        expect(silent.whereType<ListenPickExercise>(), isEmpty);
      }
      expect(seen, greaterThan(0));
    });
  });

  group('ink answers (recognizer candidates)', () {
    test('cloze: accepted when any candidate matches; best-first text is what was given', () {
      const e = ClozeExercise(
        id: 'c',
        facetId: 'it:mangiare#form:presente',
        before: 'Noi ',
        after: ' la pasta.',
        expected: 'mangiamo',
        accepted: ['mangiamo'],
      );
      const t = ClozeTemplate();
      final ok = t.grade(e, const TextAnswer('mangiarno', inputMode: InputMode.ink, candidates: ['mangiamo']), elapsed: _elapsed);
      expect(ok.correct, isTrue);
      expect(ok.given, 'mangiarno');
      final no = t.grade(e, const TextAnswer('mangiano', inputMode: InputMode.ink, candidates: ['mangiate']), elapsed: _elapsed);
      expect(no.correct, isFalse);
    });

    test('cloze: lenient accents fold the candidates too (an accent slip)', () {
      const e = ClozeExercise(id: 'c', facetId: 'it:essere#form:presente', before: 'Lui ', after: ' qui.', expected: 'è', accepted: ['è']);
      final r = const ClozeTemplate().grade(e, const TextAnswer('c', inputMode: InputMode.ink, candidates: ['e']), elapsed: _elapsed);
      expect(r.correct, isTrue);
      expect(r.accentSlip, isTrue);
      final strict = const ClozeTemplate().grade(
        e,
        const TextAnswer('c', inputMode: InputMode.ink, candidates: ['e']),
        elapsed: _elapsed,
        options: const GradeOptions(accents: AccentStrictness.strict),
      );
      expect(strict.correct, isFalse);
    });

    test('conjugation pick: a handwritten ending with candidates', () {
      final f = _facet(it, 'presente-are', 'it:parlare#form:presente');
      ConjPickExercise? e;
      for (var i = 0; i < 20 && e == null; i++) {
        e = const ConjPickTemplate().generate(f, _ctx(it, seed: i)) as ConjPickExercise?;
      }
      expect(e, isNotNull);
      final ending = e!.endings[e.correctIndex];
      final r = const ConjPickTemplate().grade(
        e,
        TextAnswer('zz', inputMode: InputMode.ink, candidates: ['qq', ending]),
        elapsed: _elapsed,
      );
      expect(r.correct, isTrue);
      expect(
        const ConjPickTemplate().grade(e, const TextAnswer('zz', inputMode: InputMode.ink, candidates: ['qq']), elapsed: _elapsed).correct,
        isFalse,
      );
    });

    test('conjugation grid: per-cell candidates', () {
      final f = _facet(it, 'presente-are', 'it:parlare#form:presente');
      final e = const ConjGridTemplate().generate(f, _ctx(it)) as ConjGridExercise;
      final asked = [for (var i = 0; i < e.cells.length; i++) if (!e.cells[i].prefilled) i];
      final cells = [for (final c in e.cells) c.prefilled ? '' : 'xx'];
      final candidates = [for (final c in e.cells) c.prefilled ? const <String>[] : ['yy', c.expected]];
      final r = const ConjGridTemplate().grade(
        e,
        GridAnswer(cells, inputMode: InputMode.ink, candidates: candidates),
        elapsed: _elapsed,
      );
      expect(r.correct, isTrue);
      expect(r.cellCorrect!.every((c) => c), isTrue);
      // One cell without the right candidate is wrong, the others stay right.
      final partial = [...candidates]..[asked.first] = const ['yy'];
      final r2 = const ConjGridTemplate().grade(
        e,
        GridAnswer(cells, inputMode: InputMode.ink, candidates: partial),
        elapsed: _elapsed,
      );
      expect(r2.correct, isFalse);
      expect(r2.cellCorrect![asked.first], isFalse);
      if (asked.length > 1) expect(r2.cellCorrect![asked[1]], isTrue);
      // Without candidates (keyboard) nothing changes.
      expect(const ConjGridTemplate().grade(e, GridAnswer(cells, inputMode: InputMode.keyboard), elapsed: _elapsed).correct, isFalse);
    });

    test('sentence builder / transform: a handwritten sentence with candidates', () {
      final f = _facet(it, 'persone', 'it:ragazzo#prod');
      SentenceBuilderExercise? e;
      for (var i = 0; i < 30 && e == null; i++) {
        e = const SentenceBuilderTemplate().generate(f, _ctx(it, seed: i, states: {f.facetId: _stable(f.facetId)}))
            as SentenceBuilderExercise?;
      }
      expect(e, isNotNull);
      final answer = e!.answers.first.join(' ');
      final r = const SentenceBuilderTemplate().grade(
        e,
        TextAnswer('qualcosa', inputMode: InputMode.ink, candidates: [answer]),
        elapsed: _elapsed,
      );
      expect(r.correct, isTrue);
    });

    test('RecognizerAnswerInput keeps the top k, best first', () {
      final a = const _Ink().toAnswer(['a', 'b', 'c', 'd']);
      expect(a.text, 'a');
      expect(a.candidates, ['b', 'c']);
      expect(a.inputMode, InputMode.ink);
      expect(const _Ink().toAnswer(const []).text, '');
    });
  });
}

class _Ink extends RecognizerAnswerInput {
  const _Ink();
  @override
  bool get isAvailable => true;
}
