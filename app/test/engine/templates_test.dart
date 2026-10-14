import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/dutch_course.dart';
import 'fixtures/italian_course.dart';

final _now = DateTime.utc(2026, 10, 13, 12);

GenContext _ctx(
  CourseData c, {
  int seed = 0,
  String lang = 'en',
  String? skill,
  Map<String, FacetState> states = const {},
  InputMode input = InputMode.tap,
  StagePolicy stagePolicy = const StagePolicy(),
}) =>
    GenContext(
      course: c,
      options: SessionOptions(sourceLang: lang, preferredInput: input),
      random: Random(seed),
      states: states,
      skill: skill == null ? null : c.skill(skill),
      now: _now,
      stagePolicy: stagePolicy,
    );

SkillFacet _facet(CourseData c, String skillId, String facetId) =>
    c.skillFacets(skillId).firstWhere((f) => f.facetId == facetId);

FacetState _stable(String id, double s) => FacetState(
      facetId: id,
      stability: s,
      difficulty: 5,
      due: _now.add(const Duration(days: 10)),
      lastReview: _now.subtract(const Duration(days: 1)),
      reps: 4,
      lapses: 0,
      phase: CardPhase.review,
    );

/// Generates [n] exercises with different seeds.
List<T> _many<T extends Exercise>(ExerciseTemplate t, CourseData c, SkillFacet f,
    {int n = 40, String? skill, Map<String, FacetState> states = const {}, InputMode input = InputMode.tap}) {
  final out = <T>[];
  for (var i = 0; i < n; i++) {
    final e = t.generate(f, _ctx(c, seed: i, skill: skill ?? f.skillId, states: states, input: input));
    if (e != null) out.add(e as T);
  }
  return out;
}

void main() {
  final it = italianCourse();
  final nl = dutchCourse();
  final ixIt = CourseIndex.of(it);
  final ixNl = CourseIndex.of(nl);

  group('course index', () {
    test('Dutch inverted jij forms are not used as occurrences', () {
      final werken = ixNl.formOccurrences('nl:werken');
      expect(werken.any((o) => o.sentence.id == 's:nl2'), isFalse); // "Werk jij morgen?"
      expect(werken.any((o) => o.sentence.id == 's:nl1'), isTrue);
      expect(ixNl.formOccurrences('nl:eten').any((o) => o.sentence.id == 's:nl11'), isFalse); // "Heb jij gegeten?"
    });

    test('split and reversed compound forms are matched in form order', () {
      final o = ixNl.formOccurrences('nl:eten').firstWhere((o) => o.sentence.id == 's:nl12');
      expect(o.surface, ['heeft', 'gegeten']);
      expect(o.contiguous, isFalse);
      final split = ixNl.formOccurrences('nl:eten').firstWhere((o) => o.sentence.id == 's:nl6');
      expect(split.surface, ['heb', 'gegeten']);
    });

    test('a partially aligned compound form finds its auxiliary', () {
      final o = ixIt.formOccurrences('it:vedere').firstWhere((o) => o.sentence.id == 's:it29');
      expect(o.surface, ['ho', 'visto']);
      expect(o.contiguous, isFalse);
    });

    test('gendered alternative forms match', () {
      final o = ixIt.formOccurrences('it:partire').firstWhere((o) => o.sentence.id == 's:it15');
      expect(o.matched, 'sono partita');
      expect(o.person, 'io');
    });

    test('compound tense contiguity is learned from the sentences', () {
      expect(ixIt.contiguousTense('passato_prossimo'), isTrue);
      expect(ixNl.contiguousTense('perfectum'), isFalse);
    });

    test('pro-drop is learned per person', () {
      expect(ixIt.dropsPronoun('noi'), isTrue);
      expect(ixIt.dropsPronoun('io'), isTrue);
      for (final p in ['ik', 'jij', 'wij']) {
        expect(ixNl.dropsPronoun(p), isFalse, reason: p);
      }
    });

    test('ambiguous persons share a pronoun', () {
      expect(ixNl.ambiguousPersons('hij/zij'), ['zij']);
      expect(ixNl.ambiguousPersons('zij'), ['hij/zij']);
      expect(ixIt.ambiguousPersons('lui/lei'), isEmpty);
    });

    test('elided articles: two tokens and one token', () {
      final acqua = ixIt.articleOccurrences('it:acqua');
      expect(acqua.where((o) => !o.withinToken).map((o) => o.sentence.id), contains('s:it5'));
      final within = acqua.firstWhere((o) => o.withinToken);
      expect(within.sentence.id, 's:it43');
      expect(within.article, 'l’');
      expect(within.nounText, 'acqua');
    });

    test('synonyms: overlapping glosses and homographs', () {
      Item i(String id) => it.item(id)!;
      expect(ixIt.overlaps(i('it:ragazzo'), i('it:bambino')), isTrue); // "kid"
      expect(ixIt.overlaps(i('it:amico'), i('it:amica')), isTrue); // "friend (female)"
      expect(ixIt.overlaps(i('it:essere'), i('it:stare')), isTrue); // "to be"
      expect(ixIt.overlaps(i('it:ragazzo'), i('it:ragazza')), isFalse);
      expect(ixNl.overlaps(nl.item('nl:dag')!, nl.item('nl:dag.2')!), isTrue); // same spelling
      expect(ixNl.overlaps(nl.item('nl:praten')!, nl.item('nl:spreken')!), isTrue);
    });
  });

  group('wrong options never include valid answers', () {
    test('multiple choice: synonyms are never distractors', () {
      final rec = _facet(it, 'persone', 'it:ragazzo#rec');
      final prod = _facet(it, 'persone', 'it:ragazzo#prod');
      for (final e in _many<MultipleChoiceExercise>(const MultipleChoiceTemplate(sentenceShare: 0), it, rec)) {
        expect(e.options.map((o) => o.toLowerCase()), isNot(contains('child')));
        expect(e.options.map((o) => o.toLowerCase()), isNot(contains('kid')));
      }
      for (final e in _many<MultipleChoiceExercise>(const MultipleChoiceTemplate(sentenceShare: 0), it, prod)) {
        expect(e.options, isNot(contains('bambino')));
      }
      final day = _facet(nl, 'dingen', 'nl:dag#prod');
      for (final e in _many<MultipleChoiceExercise>(const MultipleChoiceTemplate(sentenceShare: 0), nl, day)) {
        expect(e.options.where((o) => o == 'dag').length, 1);
      }
    });

    test('match pairs never puts overlapping items on one board', () {
      final f = _facet(it, 'persone', 'it:amico#rec');
      for (final e in _many<MatchPairsExercise>(const MatchPairsTemplate(), it, f)) {
        expect(e.left.contains('amico') && e.left.contains('amica'), isFalse);
        expect(e.left.contains('ragazzo') && e.left.contains('bambino'), isFalse);
      }
    });

    test('conj pick: homographs (Dutch eet ik/jij/hij) are not offered', () {
      final f = _facet(nl, 'tt-onregelmatig', 'nl:eten#form:tegenwoordige_tijd');
      final es = _many<ConjPickExercise>(const ConjPickTemplate(), nl, f, n: 60);
      expect(es, isNotEmpty);
      for (final e in es) {
        final valid = [
          for (final o in e.endings)
            if (nl.verbForms('nl:eten')['${e.tense}.${e.person}']!.accepted.contains(e.stem + (o == kNoEnding ? '' : o))) o,
        ];
        expect(valid.length, 1, reason: '${e.person}: ${e.stem} ${e.endings}');
      }
    });

    test('cloze and spot error: Italian "sono" (io = loro) never counts as wrong', () {
      final f = _facet(it, 'essere-avere', 'it:essere#form:presente');
      for (final e in _many<ClozeExercise>(const ClozeTemplate(), it, f, n: 60)) {
        if (e.expected.toLowerCase() == 'sono') {
          expect(e.options!.where((o) => o.toLowerCase() == 'sono').length, 1);
        }
      }
      for (final e in _many<SpotErrorExercise>(const SpotErrorTemplate(), it, f, n: 60)) {
        expect(e.tokens[e.errorIndex].toLowerCase() == 'sono' && e.correction.toLowerCase() == 'sono', isFalse);
      }
    });

    test('Dutch hij/zij is never swapped with zij (they)', () {
      final f = _facet(nl, 'tt-regelmatig', 'nl:werken#form:tegenwoordige_tijd');
      for (final e in _many<SpotErrorExercise>(const SpotErrorTemplate(), nl, f, n: 60)) {
        if (e.sentenceId == 's:nl3') expect(e.tokens[e.errorIndex], isNot('werken'));
        if (e.sentenceId == 's:nl4') expect(e.tokens[e.errorIndex], isNot('werkt'));
      }
      for (final e in _many<ClozeExercise>(const ClozeTemplate(), nl, f, n: 60)) {
        if (e.sentenceId == 's:nl3') expect(e.options, isNot(contains('werken')));
        if (e.sentenceId == 's:nl4') expect(e.options, isNot(contains('werkt')));
      }
    });

    test('verbs taking hebben or zijn: the other auxiliary is never a wrong option', () {
      final f = _facet(nl, 'perfectum', 'nl:zwemmen#form:perfectum');
      for (final e in _many<ClozeExercise>(const ClozeTemplate(), nl, f, n: 40)) {
        expect(e.options, isNot(contains('ben')));
      }
      for (final e in _many<ConjGridExercise>(const ConjGridTemplate(), nl, f, n: 20)) {
        expect(e.tiles, isNot(contains('ben gezwommen')));
      }
    });

    test('grid distractors exclude forms of a homographic verb (sono stato: essere/stare)', () {
      final f = _facet(it, 'passato-prossimo', 'it:essere#form:passato_prossimo');
      for (final e in _many<ConjGridExercise>(const ConjGridTemplate(), it, f)) {
        final cells = {for (final c in e.cells) ...c.accepted};
        final asked = [for (final c in e.cells) if (!c.prefilled) c.expected];
        final extra = List.of(e.tiles);
        for (final a in asked) {
          extra.remove(a);
        }
        expect(extra.where(cells.contains), isEmpty);
      }
    });
  });

  group('exercise shape', () {
    test('grid: fresh facets get prefilled cells, stable ones none', () {
      final f = _facet(it, 'presente-are', 'it:parlare#form:presente');
      final fresh = const ConjGridTemplate().generate(f, _ctx(it)) as ConjGridExercise;
      expect(fresh.cells.where((c) => c.prefilled).length, 3);
      final stable = const ConjGridTemplate()
          .generate(f, _ctx(it, states: {f.facetId: _stable(f.facetId, 30)})) as ConjGridExercise;
      expect(stable.cells.where((c) => c.prefilled), isEmpty);
      // Dutch: one tile per asked cell, so "werken" appears once per plural cell.
      final w = _facet(nl, 'tt-regelmatig', 'nl:werken#form:tegenwoordige_tijd');
      final g = const ConjGridTemplate().generate(w, _ctx(nl, states: {w.facetId: _stable(w.facetId, 30)})) as ConjGridExercise;
      expect(g.tiles.where((t) => t == 'werken').length, 3);
    });

    test('cloze: typing is never required; free text only for keyboard/ink learners', () {
      final f = _facet(it, 'presente-are', 'it:parlare#form:presente');
      ClozeExercise gen({Map<String, FacetState> states = const {}, InputMode input = InputMode.tap, double days = 0}) =>
          const ClozeTemplate().generate(
                f,
                _ctx(it, states: states, input: input, stagePolicy: StagePolicy(freeTextDays: days)),
              )
              as ClozeExercise;
      final young = <String, FacetState>{};
      final stable = {f.facetId: _stable(f.facetId, 400)};
      // Tap: always choices, however stable the facet or high/low the threshold.
      for (final days in [0.0, 21.0]) {
        expect(gen(days: days).options, isNotNull);
        expect(gen(states: stable, days: days).options, isNotNull);
      }
      // Keyboard and ink: free text (default threshold 0) ...
      expect(gen(input: InputMode.keyboard).options, isNull);
      expect(gen(input: InputMode.ink).options, isNull);
      // ... or, with a threshold, once the facet is stable enough.
      expect(gen(input: InputMode.keyboard, states: young, days: 21).options, isNotNull);
      expect(gen(input: InputMode.keyboard, states: stable, days: 21).options, isNull);
    });

    test('cloze grading: accents, case, alternatives and ink candidates', () {
      const t = ClozeTemplate();
      const e = ClozeExercise(
        id: 'x',
        facetId: 'it:essere#form:presente',
        before: 'La città ',
        after: ' grande.',
        expected: 'è',
        accepted: ['è'],
      );
      Result g(Answer a, [AccentStrictness s = AccentStrictness.lenient]) =>
          t.grade(e, a, elapsed: const Duration(seconds: 10), options: GradeOptions(accents: s));
      expect(g(const TextAnswer('È')).correct, isTrue);
      final slip = g(const TextAnswer('e'));
      expect(slip.correct && slip.accentSlip, isTrue);
      expect(slip.outcomes.single.rating, Rating.good);
      expect(g(const TextAnswer('e'), AccentStrictness.strict).correct, isFalse);
      expect(g(const TextAnswer('ha', candidates: ['è'], inputMode: InputMode.ink)).correct, isTrue);
      expect(g(const TextAnswer('sono')).outcomes.single.rating, Rating.again);
    });

    test('cloze over a split Dutch perfectum gaps the auxiliary', () {
      final f = _facet(nl, 'perfectum', 'nl:eten#form:perfectum');
      final es = _many<ClozeExercise>(const ClozeTemplate(), nl, f, n: 30);
      final split = es.where((e) => e.sentenceId == 's:nl6');
      expect(split, isNotEmpty);
      for (final e in split) {
        expect(e.before, 'Ik ');
        expect(e.expected, 'heb');
        expect(e.after, ' brood gegeten.');
      }
    });

    test('cloze over an elided article inside one token', () {
      final f = _facet(it, 'articoli', 'it:acqua#article');
      final es = _many<ClozeExercise>(const ClozeTemplate(), it, f, n: 40).where((e) => e.sentenceId == 's:it43');
      expect(es, isNotEmpty);
      for (final e in es) {
        expect(e.before, 'Bevo ');
        expect(e.expected, 'l’');
        expect(e.after, 'acqua.');
        expect(e.options, contains('l’'));
        expect(e.options!.length, 4);
      }
    });

    test('spot error keeps spacing right when swapping elided articles', () {
      final f = _facet(it, 'articoli', 'it:acqua#article');
      final es = _many<SpotErrorExercise>(const SpotErrorTemplate(), it, f, n: 40);
      expect(es, isNotEmpty);
      for (final e in es) {
        final text = renderSpotError(e);
        expect(text.contains('  '), isFalse);
        if (!normalizeApostrophes(e.tokens[e.errorIndex]).contains("'")) {
          expect(text, anyOf(contains(' acqua'), contains('a acqua')));
        }
      }
    });

    test('transform: tense swaps; person swaps only in pro-drop sentences', () {
      final f = _facet(it, 'passato-prossimo', 'it:mangiare#form:passato_prossimo');
      final es = _many<TransformExercise>(const TransformTemplate(), it, f, n: 40);
      expect(es.map((e) => e.answers.first.join(' ')), contains('abbiamo mangiato la pizza alle otto'));
      // Dutch never gets a person change (pronoun subjects are always present).
      for (final skill in ['tt-regelmatig', 'tt-onregelmatig', 'perfectum']) {
        for (final sf in nl.skillFacets(skill)) {
          for (final e in _many<TransformExercise>(const TransformTemplate(), nl, sf, n: 8)) {
            expect(e.targetDescription, startsWith('→ '));
            for (final p in nl.meta.persons) {
              expect(e.targetDescription.contains(nl.meta.personLabel(p, 'en')), isFalse, reason: e.targetDescription);
            }
          }
        }
      }
    });

    test('transform: Dutch single -> compound only when the verb ends the sentence', () {
      final f = _facet(nl, 'perfectum', 'nl:lezen#form:perfectum');
      final es = _many<TransformExercise>(const TransformTemplate(), nl, f, n: 40);
      for (final e in es) {
        if (e.source == 'Ik lees.') expect(e.answers.first, ['ik', 'heb', 'gelezen']);
        expect(e.source, isNot('De man leest de krant.'));
      }
    });

    test('transform accepts gendered alternatives', () {
      final f = _facet(it, 'presente-ere-ire', 'it:partire#form:presente');
      final pp = _facet(it, 'passato-prossimo', 'it:partire#form:passato_prossimo');
      expect(_many<TransformExercise>(const TransformTemplate(), it, f, n: 20), isNotEmpty);
      for (final e in _many<TransformExercise>(const TransformTemplate(), it, pp, n: 20)) {
        if (e.answers.first.contains('partito')) {
          expect(e.answers.any((a) => a.contains('partita')), isTrue);
        }
      }
    });

    test('sentence builder accepts a different elision tokenization', () {
      final f = _facet(it, 'cibo', 'it:acqua#prod');
      final e = _many<SentenceBuilderExercise>(const SentenceBuilderTemplate(), it, f).firstWhere((e) => e.sentenceId == 's:it5');
      final r = const SentenceBuilderTemplate().grade(e, const TextAnswer("La ragazza beve l'acqua"), elapsed: Duration.zero);
      expect(r.correct, isTrue);
    });

    test('skill exercise restrictions are respected by the selector', () {
      final selector = ExerciseSelector();
      for (final f in it.skillFacets('essere-avere')) {
        for (var i = 0; i < 10; i++) {
          final ctx = _ctx(it, seed: i, skill: 'essere-avere', states: {f.facetId: _stable(f.facetId, 30)});
          final e = selector.generate(f, ctx, focus: LessonFocus.grammar);
          expect(e?.type, isNot(ExerciseType.transform));
        }
      }
      final f = it.skillFacets('essere-avere').first;
      expect(selector.allowedTypes(f, _ctx(it, skill: 'essere-avere')), isNot(contains(ExerciseType.transform)));
      expect(selector.allowedTypes(f, _ctx(it, skill: 'essere-avere'), ignoreSkillRestriction: true),
          contains(ExerciseType.transform));
    });

    test('selector: fresh facets get recognition, stable facets production', () {
      final selector = ExerciseSelector();
      final counts = <FacetStage, Map<ExerciseType, int>>{};
      for (final stage in FacetStage.values) {
        final m = counts[stage] = {};
        for (final f in it.skillFacets('persone')) {
          for (var i = 0; i < 6; i++) {
            final states = switch (stage) {
              FacetStage.fresh => <String, FacetState>{},
              FacetStage.learning => {f.facetId: _stable(f.facetId, 2)},
              FacetStage.stable => {f.facetId: _stable(f.facetId, 30)},
            };
            final e = selector.generate(f, _ctx(it, seed: i, skill: 'persone', states: states))!;
            m[e.type] = (m[e.type] ?? 0) + 1;
          }
        }
      }
      int n(FacetStage s, ExerciseType t) => counts[s]![t] ?? 0;
      expect(n(FacetStage.fresh, ExerciseType.sentenceBuilder), 0);
      expect(n(FacetStage.fresh, ExerciseType.flashcard), greaterThan(n(FacetStage.stable, ExerciseType.flashcard)));
      expect(n(FacetStage.stable, ExerciseType.sentenceBuilder) + n(FacetStage.stable, ExerciseType.cloze),
          greaterThan(n(FacetStage.fresh, ExerciseType.sentenceBuilder) + n(FacetStage.fresh, ExerciseType.cloze)));
    });

    test('selector: a vocab-focus lesson on a grammar skill still generates', () {
      final selector = ExerciseSelector();
      final f = it.skillFacets('presente-are').first;
      final e = selector.generate(f, _ctx(it, skill: 'presente-are'), focus: LessonFocus.vocab);
      expect(e, isNotNull);
      for (var i = 0; i < 20; i++) {
        final g = selector.generate(f, _ctx(it, seed: i, skill: 'presente-are'), focus: LessonFocus.grammar)!;
        expect(FocusPresets.defaults.typesFor(LessonFocus.grammar), contains(g.type));
      }
    });
  });

  group('debug printer', () {
    test('prints samples for every type in both fixtures', () {
      final s = sampleExercises(it, perType: 2) + sampleExercises(nl, perType: 2);
      for (final t in ExerciseType.values) {
        expect(s, contains('[${t.id}]'), reason: t.id);
      }
      expect(sampleExercises(it, perType: 20, skillIds: ['presente-are']), contains('--- conj_pick: 20 example(s)'));
    });

    test('exercisePrompt joins a question instruction without a colon', () {
      const q = FlashcardExercise(id: 'x', facetId: 'it:ciao#rec', instruction: 'What does this mean?', front: 'ciao', back: 'hi', direction: Direction.recognize);
      expect(exercisePrompt(q), 'What does this mean? ciao');
      const t = FlashcardExercise(id: 'y', facetId: 'it:ciao#rec', instruction: 'Translate', front: 'ciao', back: 'hi', direction: Direction.recognize);
      expect(exercisePrompt(t), 'Translate: ciao');
    });

    test('exercisePrompt is non-empty for every type', () {
      for (final skill in it.skills) {
        for (final t in defaultTemplates()) {
          for (final f in it.skillFacets(skill.id).where(t.supports).take(2)) {
            final e = t.generate(f, _ctx(it, skill: skill.id));
            if (e != null) expect(exercisePrompt(e).trim(), isNotEmpty);
          }
        }
      }
    });
  });
}
