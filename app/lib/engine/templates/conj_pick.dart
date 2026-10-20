import '../../core/models/course.dart';
import '../../core/models/exercise.dart';
import '../../core/models/facet.dart';
import '../../core/models/progress.dart';
import '../gen_context.dart';
import '../grading/rating.dart';
import '../strings.dart';
import '../template.dart';
import '../text/normalize.dart';
import 'inflection.dart';

/// How an empty ending (Dutch `ik werk` = `werk` + '') is shown as an option.
const String kNoEnding = '–';

/// The stem is shown; pick the ending for a person and tense (`mang___`, noi).
///
/// Only cells with a stem/ending split and a single-word form qualify.
/// Wrong endings, in priority order: other persons in the same tense, other
/// tenses of the verb, the same tense of verbs of the same class, any verb.
/// An ending is never offered when stem + ending is an accepted form of the
/// asked cell (homographs, alternative spellings).
class ConjPickTemplate extends ExerciseTemplate {
  const ConjPickTemplate({this.optionCount = 4});

  final int optionCount;

  @override
  ExerciseType get type => ExerciseType.conjPick;

  @override
  Set<FacetKind> get kinds => const {FacetKind.form, FacetKind.infl};

  List<VerbForm> _cells(SkillFacet facet, GenContext ctx) {
    final tense = facet.tense;
    if (tense == null || ctx.course.item(facet.itemId) == null) return const [];
    return [
      for (final f in ctx.index.finiteForms(facet.itemId, tense))
        if (f.hasSplit && f.stem!.isNotEmpty && splitWords(f.form).length == 1) f,
    ];
  }

  String? _endingFor(VerbForm f, String stem) {
    if (splitWords(f.form).length != 1) return null;
    if (f.hasSplit) return f.ending;
    final lf = f.form.toLowerCase();
    final ls = stem.toLowerCase();
    return lf.startsWith(ls) ? f.form.substring(stem.length) : null;
  }

  List<String> _distractors(SkillFacet facet, VerbForm cell, GenContext ctx, {bool shuffle = true}) {
    final course = ctx.course;
    final ix = ctx.index;
    final stem = cell.stem!;
    final accepted = ix.acceptedKeys(cell);
    final seen = <String>{_endingKey(cell.ending!)};
    final out = <String>[];
    final verb = course.verb(facet.itemId);

    void addGroup(Iterable<VerbForm> forms) {
      final list = shuffle ? ctx.shuffled(forms) : forms.toList();
      for (final f in list) {
        if (out.length >= optionCount - 1) return;
        final e = _endingFor(f, stem);
        if (e == null) continue;
        if (accepted.contains(foldAnswer(stem + e))) continue;
        if (!seen.add(_endingKey(e))) continue;
        out.add(e);
      }
    }

    final own = course.verbForms(facet.itemId).values.where((f) => f.person != kNoPerson);
    addGroup(own.where((f) => f.tense == cell.tense && f.person != cell.person));
    addGroup(own.where((f) => f.tense != cell.tense && ctx.tenseShowable(f.tense)));
    final others = [for (final v in ix.verbs) if (v.id != facet.itemId) v];
    final sameClass = [
      for (final v in others)
        if (verb?.verbClass != null && course.verb(v.id)?.verbClass == verb!.verbClass) v,
    ];
    addGroup([
      for (final v in sameClass)
        for (final f in ix.finiteForms(v.id, cell.tense))
          if (f.hasSplit && stemsEndAlike(f.stem!, cell.stem!)) f,
    ]);
    addGroup([
      for (final v in others)
        for (final f in ix.finiteForms(v.id, cell.tense))
          if (f.hasSplit && stemsEndAlike(f.stem!, cell.stem!)) f,
    ]);
    return out;
  }

  static String _endingKey(String e) => foldDiacritics(e.toLowerCase());

  /// A typed ending (typing mode): `stem + ending` must be an accepted form
  /// (with the accent setting). `-` or `–` alone means the empty ending, a
  /// leading hyphen is ignored, and typing the whole form is accepted too.
  Result _gradeTyped(ConjPickExercise e, TextAnswer a, {required Duration elapsed, required GradeOptions options}) {
    String ending(String t) {
      var x = t.trim();
      if (x == kNoEnding || x == '-') return '';
      if (x.startsWith('-') || x.startsWith(kNoEnding)) x = x.substring(1).trim();
      return x;
    }

    final forms = e.accepted.isEmpty ? [e.fullForm] : e.accepted;
    final typed = [a.text, ...a.candidates].map(ending).toList();
    final given = e.stem + typed.first;
    final m = matchAnswer(
      given,
      forms,
      options.accents,
      candidates: [for (final t in typed.skip(1)) e.stem + t, ...typed],
    );
    return Result(
      correct: m.correct,
      expected: e.fullForm,
      given: given,
      accentSlip: m.accentSlip,
      outcomes: [
        rateOutcome(e.type, e.facetId, correct: m.correct, elapsed: elapsed, options: options, accentSlip: m.accentSlip),
      ],
    );
  }

  @override
  bool canGenerate(SkillFacet facet, GenContext ctx) {
    if (!supports(facet)) return false;
    if (facet.kind == FacetKind.infl) {
      return ctx.memo('conj_pick/$optionCount|${facet.facetId}',
          () => inflPickCells(ctx, facet).any((c) => _inflDistractors(facet, c, ctx, shuffle: false).length >= 2));
    }
    return ctx.memo('conj_pick/$optionCount|${facet.facetId}',
        () => _cells(facet, ctx).any((c) => _distractors(facet, c, ctx, shuffle: false).length >= 2));
  }

  /// Wrong endings for an inflection cell (see [inflPickGroups]).
  List<String> _inflDistractors(SkillFacet facet, InflectionForm cell, GenContext ctx, {bool shuffle = true}) {
    final accepted = inflAcceptedKeys(cell);
    final seen = <String>{_endingKey(cell.ending!)};
    final out = <String>[];
    for (final g in inflPickGroups(ctx, facet, cell)) {
      for (final e in shuffle ? ctx.shuffled(g) : g) {
        if (out.length >= optionCount - 1) return out;
        if (accepted.contains(foldAnswer(cell.stem! + e))) continue;
        if (!seen.add(_endingKey(e))) continue;
        out.add(e);
      }
    }
    return out;
  }

  Exercise? _generateInfl(SkillFacet facet, GenContext ctx) {
    final item = ctx.course.item(facet.itemId);
    final spec = inflTableOf(ctx, facet);
    if (item == null || spec == null) return null;
    for (final cell in ctx.shuffled(inflPickCells(ctx, facet))) {
      final d = _inflDistractors(facet, cell, ctx);
      if (d.length < 2) continue;
      final shown = [for (final e in d) e.isEmpty ? kNoEnding : e];
      final correct = cell.ending!.isEmpty ? kNoEnding : cell.ending!;
      final (options, idx) = placeOptions(correct, shown, ctx.random);
      return ConjPickExercise(
        id: ctx.nextId(),
        facetId: facet.facetId,
        skillId: ctx.skill?.id,
        instruction: instruction('conj_pick', ctx.lang),
        lemma: item.lemma,
        gloss: item.gloss(ctx.lang),
        tense: spec.name,
        tenseLabel: spec.titleIn(ctx.lang),
        person: cell.cell,
        personLabel: spec.cellLabel(cell.cell, ctx.lang),
        stem: cell.stem!,
        endings: options,
        correctIndex: idx,
        fullForm: cell.form,
        accepted: cell.accepted,
        inflection: true,
      );
    }
    return null;
  }

  @override
  Exercise? generate(SkillFacet facet, GenContext ctx) {
    if (!supports(facet)) return null;
    if (facet.kind == FacetKind.infl) return _generateInfl(facet, ctx);
    final verb = ctx.course.item(facet.itemId);
    if (verb == null) return null;
    for (final cell in ctx.shuffled(_cells(facet, ctx))) {
      final d = _distractors(facet, cell, ctx);
      if (d.length < 2) continue;
      final shown = [for (final e in d) e.isEmpty ? kNoEnding : e];
      final correct = cell.ending!.isEmpty ? kNoEnding : cell.ending!;
      final (options, idx) = placeOptions(correct, shown, ctx.random);
      final meta = ctx.course.meta;
      return ConjPickExercise(
        id: ctx.nextId(),
        facetId: facet.facetId,
        skillId: ctx.skill?.id,
        instruction: instruction('conj_pick', ctx.lang),
        lemma: verb.lemma,
        gloss: verb.gloss(ctx.lang),
        tense: cell.tense,
        tenseLabel: meta.tenseLabel(cell.tense, ctx.lang),
        person: cell.person,
        personLabel: meta.personLabel(cell.person, ctx.lang, tense: cell.tense),
        stem: cell.stem!,
        endings: options,
        correctIndex: idx,
        fullForm: cell.form,
        accepted: {cell.form, ...cell.accepted}.toList(),
      );
    }
    return null;
  }

  @override
  Result grade(Exercise exercise, Answer answer, {required Duration elapsed, GradeOptions options = const GradeOptions()}) {
    final e = exercise as ConjPickExercise;
    if (answer is TextAnswer) return _gradeTyped(e, answer, elapsed: elapsed, options: options);
    final r = gradeChoice(e, answer, e.endings, e.correctIndex, elapsed: elapsed, grade: options);
    String full(String ending) => e.stem + (ending == kNoEnding ? '' : ending);
    final idx = answer is ChoiceAnswer ? answer.index : -1;
    return Result(
      correct: r.correct,
      expected: e.fullForm,
      given: idx >= 0 && idx < e.endings.length ? full(e.endings[idx]) : r.given,
      outcomes: r.outcomes,
    );
  }
}
