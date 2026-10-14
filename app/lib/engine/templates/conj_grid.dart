import 'dart:math';

import '../../core/interfaces/session.dart' show AccentStrictness;
import '../../core/models/course.dart';
import '../../core/models/exercise.dart';
import '../../core/models/facet.dart';
import '../../core/models/progress.dart';
import '../gen_context.dart';
import '../grading/rating.dart';
import '../strings.dart';
import '../template.dart';
import '../text/normalize.dart';

/// Fill a whole tense table.
///
/// Tiles: one tile per asked cell (so a form shared by several cells, like
/// Dutch `werken` for wij/jullie/zij, appears once per cell; a UI that
/// consumes tiles works, and one that reuses them is fine too) plus
/// [distractorCount] plausible wrong forms that match no cell of the table.
///
/// Fresh facets get about half of the cells prefilled, learning facets about
/// a third, stable facets none.
class ConjGridTemplate extends ExerciseTemplate {
  const ConjGridTemplate({this.distractorCount = 3, this.minCells = 3});

  final int distractorCount;
  final int minCells;

  @override
  ExerciseType get type => ExerciseType.conjGrid;

  @override
  Set<FacetKind> get kinds => const {FacetKind.form};

  @override
  bool canGenerate(SkillFacet facet, GenContext ctx) {
    if (!supports(facet) || facet.tense == null) return false;
    return ctx.memo('conj_grid/$distractorCount/$minCells|${facet.facetId}', () {
      final cells = ctx.index.finiteForms(facet.itemId, facet.tense!);
      return cells.length >= minCells && _distractors(facet, cells, ctx, shuffle: false).isNotEmpty;
    });
  }

  List<String> _distractors(SkillFacet facet, List<VerbForm> cells, GenContext ctx, {bool shuffle = true}) {
    final forbidden = [for (final c in cells) ...c.accepted];
    final picker = OptionPicker(forbidden: forbidden, max: distractorCount);
    // The candidate groups depend only on the course and the facet.
    var groups = ctx.index.memo('conj_grid.groups|${facet.facetId}', () => _candidateGroups(facet, cells, ctx));
    if (ctx.gate != null) {
      // Group d (the verb's other tenses): only tenses the learner has met.
      final tenseOf = {for (final f in ctx.course.verbForms(facet.itemId).values) f.form: f.tense};
      groups = [
        groups[0],
        [for (final o in groups[1]) if (ctx.tenseShowable(tenseOf[o] ?? '')) o],
        ...groups.skip(2),
      ];
    }
    if (shuffle) {
      picker.addGroups(groups, ctx.random);
    } else {
      for (final g in groups) {
        for (final o in g) {
          if (picker.full) return picker.picked;
          picker.add(o);
        }
      }
    }
    return picker.picked;
  }

  /// Wrong-form candidates in priority groups (see the class comment).
  List<List<String>> _candidateGroups(SkillFacet facet, List<VerbForm> cells, GenContext ctx) {
    final course = ctx.course;
    final ix = ctx.index;
    final tense = facet.tense!;
    final verb = course.verb(facet.itemId);
    final wordCounts = [for (final c in cells) ix.wordsOf(c.form).length];
    final typicalWords = wordCounts.fold<Map<int, int>>({}, (m, n) => m..[n] = (m[n] ?? 0) + 1).entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    final others = [for (final v in ix.verbs) if (v.id != facet.itemId) v];
    final byPerson = {for (final c in cells) c.person: c};

    // a) Swap the person-dependent word of a compound form with the same
    //    person's word of another verb (`sono mangiato`), unless the verb
    //    takes several auxiliaries (both could be right).
    final a = <String>[];
    final auxAmbiguous = (verb?.auxiliary ?? '').contains('|');
    if (!auxAmbiguous && typicalWords > 1) {
      final varying = <int>{
        for (var k = 0; k < typicalWords; k++)
          if ({for (final c in cells) if (ix.wordsOf(c.form).length == typicalWords) foldAnswer(ix.wordsOf(c.form)[k])}.length > 1) k,
      };
      if (varying.isNotEmpty) {
        final k = varying.reduce(min);
        for (final v in others) {
          for (final f in ix.finiteForms(v.id, tense)) {
            final mine = byPerson[f.person];
            if (mine == null) continue;
            final w = ix.wordsOf(mine.form);
            final w2 = ix.wordsOf(f.form);
            if (w.length != typicalWords || w2.length != typicalWords) continue;
            if (foldAnswer(w[k]) == foldAnswer(w2[k])) continue;
            a.add((List.of(w)..[k] = w2[k]).join(' '));
          }
        }
      }
    }

    // b) A cell's stem with the same person's ending from a verb of another
    //    class (`mang` + `ete`), and c) with another person's ending (`maak` + `en`).
    final b = <String>[];
    final c = <String>[];
    for (final cell in cells) {
      if (!cell.hasSplit || cell.stem!.isEmpty) continue;
      for (final v in others) {
        if (verb?.verbClass != null && course.verb(v.id)?.verbClass == verb!.verbClass) continue;
        final f = course.verbForms(v.id)[cell.key];
        if (f != null && f.hasSplit && f.ending != cell.ending && stemsEndAlike(f.stem!, cell.stem!)) b.add(cell.stem! + f.ending!);
      }
      for (final other in cells) {
        if (other.person != cell.person && other.hasSplit) c.add(cell.stem! + other.ending!);
      }
    }

    // d) The verb's own forms in other tenses with the same word count.
    final d = [
      for (final f in course.verbForms(facet.itemId).values)
        if (f.tense != tense && f.person != kNoPerson && ix.wordsOf(f.form).length == typicalWords) f.form,
    ];

    // e) Other verbs' forms in this tense (irregular verbs prefer irregular ones).
    final irregular = verb?.irregular ?? false;
    final e1 = <String>[];
    final e2 = <String>[];
    for (final v in others) {
      final sameKind = (course.verb(v.id)?.irregular ?? false) == irregular;
      for (final f in ix.finiteForms(v.id, tense)) {
        if (ix.wordsOf(f.form).length != typicalWords) continue;
        (sameKind ? e1 : e2).add(f.form);
      }
    }

    return [
      [...a, ...b, ...c],
      d,
      e1,
      e2,
    ];
  }

  @override
  Exercise? generate(SkillFacet facet, GenContext ctx) {
    if (!supports(facet) || facet.tense == null) return null;
    final verb = ctx.course.item(facet.itemId);
    if (verb == null) return null;
    final forms = ctx.index.finiteForms(facet.itemId, facet.tense!);
    if (forms.length < minCells) return null;
    final distractors = _distractors(facet, forms, ctx);
    if (distractors.isEmpty) return null;

    final stage = ctx.stage(facet.facetId);
    final n = forms.length;
    var prefill = switch (stage) {
      FacetStage.fresh => n ~/ 2,
      FacetStage.learning => n ~/ 3,
      FacetStage.stable => 0,
    };
    prefill = min(prefill, n - 2);
    final prefilled = (ctx.shuffled(List.generate(n, (i) => i)).take(max(0, prefill))).toSet();
    final meta = ctx.course.meta;
    final cells = [
      for (var i = 0; i < n; i++)
        GridCell(
          person: forms[i].person,
          personLabel: meta.personLabel(forms[i].person, ctx.lang),
          expected: forms[i].form,
          accepted: forms[i].accepted,
          prefilled: prefilled.contains(i),
        ),
    ];
    final tiles = ctx.shuffled([
      for (final c in cells)
        if (!c.prefilled) c.expected,
      ...distractors,
    ]);
    return ConjGridExercise(
      id: ctx.nextId(),
      facetId: facet.facetId,
      skillId: ctx.skill?.id,
      instruction: instruction(prefilled.isEmpty ? 'conj_grid' : 'conj_grid.partial', ctx.lang),
      lemma: verb.lemma,
      gloss: verb.gloss(ctx.lang),
      tense: facet.tense!,
      tenseLabel: meta.tenseLabel(facet.tense!, ctx.lang),
      cells: cells,
      tiles: tiles,
    );
  }

  @override
  Result grade(Exercise exercise, Answer answer, {required Duration elapsed, GradeOptions options = const GradeOptions()}) {
    final e = exercise as ConjGridExercise;
    final expected = [for (final c in e.cells) '${c.personLabel}: ${c.expected}'].join(', ');
    if (answer is! GridAnswer || answer.cells.length != e.cells.length) {
      return wrongKind(e, answer, expected);
    }
    final strictness = answer.inputMode == InputMode.tap ? AccentStrictness.strict : options.accents;
    var all = true;
    var slip = false;
    final perCell = <bool>[];
    for (var i = 0; i < e.cells.length; i++) {
      final c = e.cells[i];
      if (c.prefilled) {
        perCell.add(true);
        continue;
      }
      // Ink: the cell is right when any recognizer candidate matches.
      final alts = i < answer.candidates.length ? answer.candidates[i] : const <String>[];
      final m = matchAnswer(answer.cells[i], c.accepted.isEmpty ? [c.expected] : c.accepted, strictness, candidates: alts);
      perCell.add(m.correct);
      all &= m.correct;
      slip |= m.accentSlip;
    }
    return Result(
      correct: all,
      expected: expected,
      given: answer.cells.join(', '),
      cellCorrect: perCell,
      accentSlip: all && slip,
      outcomes: [
        rateOutcome(e.type, e.facetId, correct: all, elapsed: elapsed, options: options, accentSlip: slip),
      ],
    );
  }
}
