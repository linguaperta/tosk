import '../../core/models/course.dart';
import '../../core/models/exercise.dart';
import '../../core/models/facet.dart';
import '../../core/models/progress.dart';
import '../gen_context.dart';
import '../grading/rating.dart';
import '../strings.dart';
import '../template.dart';
import '../text/normalize.dart';

/// Pair 5 target words with their meanings. Grades one `#rec` facet per pair.
///
/// The pairs come from the skill's other `#rec` facets (then other skills').
/// No two chosen items may overlap (shared gloss or spelling), so every word
/// has exactly one matching meaning on the board.
class MatchPairsTemplate extends ExerciseTemplate {
  const MatchPairsTemplate({this.pairs = 5});

  final int pairs;

  @override
  ExerciseType get type => ExerciseType.matchPairs;

  @override
  Set<FacetKind> get kinds => const {FacetKind.rec};

  @override
  bool canGenerate(SkillFacet facet, GenContext ctx) =>
      supports(facet) &&
      ctx.index.memo('match_pairs/$pairs|${facet.facetId}|${_skillId(facet, ctx)}|${ctx.lang}',
          () => _choose(facet, ctx, shuffle: false) != null);

  /// The skill whose facets fill the board.
  String _skillId(SkillFacet facet, GenContext ctx) => ctx.skill?.id ?? facet.skillId;

  List<(Item, SkillFacet)>? _choose(SkillFacet facet, GenContext ctx, {bool shuffle = true}) {
    final course = ctx.course;
    final anchor = course.item(facet.itemId);
    if (anchor == null || !_usable(anchor, ctx)) return null;
    final chosen = <(Item, SkillFacet)>[(anchor, facet)];
    final lemmaKeys = {foldAnswer(anchor.lemma)};
    final glossKeys = {foldAnswer(anchor.gloss(ctx.lang))};

    bool tryAdd(SkillFacet f) {
      if (f.kind != FacetKind.rec || chosen.any((c) => c.$1.id == f.itemId)) return false;
      final item = course.item(f.itemId);
      if (item == null || !_usable(item, ctx)) return false;
      if (chosen.any((c) => ctx.index.overlaps(c.$1, item))) return false;
      final lk = foldAnswer(item.lemma);
      final gk = foldAnswer(item.gloss(ctx.lang));
      if (lemmaKeys.contains(lk) || glossKeys.contains(gk)) return false;
      // The displayed meaning must not be a meaning of any other word on the
      // board, nor of one of its synonyms (and vice versa).
      for (final c in chosen) {
        if (ctx.index.meaningKeys(c.$1, ctx.lang).contains(gk)) return false;
        if (ctx.index.meaningKeys(item, ctx.lang).contains(foldAnswer(c.$1.gloss(ctx.lang)))) return false;
      }
      chosen.add((item, f));
      lemmaKeys.add(lk);
      glossKeys.add(gk);
      return true;
    }

    final own = course.skillFacets(_skillId(facet, ctx));
    for (final f in shuffle ? ctx.shuffled(own) : own) {
      if (chosen.length >= pairs) break;
      tryAdd(f);
    }
    if (chosen.length < pairs) {
      for (final s in course.skills) {
        final fs = course.skillFacets(s.id);
        for (final f in shuffle ? ctx.shuffled(fs) : fs) {
          if (chosen.length >= pairs) break;
          tryAdd(f);
        }
        if (chosen.length >= pairs) break;
      }
    }
    return chosen.length >= pairs ? chosen : null;
  }

  bool _usable(Item item, GenContext ctx) =>
      item.lemma.trim().isNotEmpty && item.gloss(ctx.lang).trim().isNotEmpty;

  @override
  Exercise? generate(SkillFacet facet, GenContext ctx) {
    if (!supports(facet)) return null;
    final chosen = _choose(facet, ctx);
    if (chosen == null) return null;
    final order = ctx.shuffled(chosen);
    final left = [for (final c in order) c.$1.lemma];
    final meanings = [for (final c in order) c.$1.gloss(ctx.lang)];
    final right = ctx.shuffled(meanings);
    return MatchPairsExercise(
      id: ctx.nextId(),
      facetId: facet.facetId,
      skillId: ctx.skill?.id,
      instruction: instruction('match', ctx.lang),
      left: left,
      right: right,
      solution: {for (var i = 0; i < left.length; i++) i: right.indexOf(meanings[i])},
      pairFacetIds: {for (var i = 0; i < order.length; i++) i: order[i].$2.facetId},
    );
  }

  @override
  Result grade(Exercise exercise, Answer answer, {required Duration elapsed, GradeOptions options = const GradeOptions()}) {
    final e = exercise as MatchPairsExercise;
    final expected = [for (var i = 0; i < e.left.length; i++) '${e.left[i]} = ${e.right[e.solution[i]!]}'].join('; ');
    if (answer is! MatchAnswer) {
      return Result(
        correct: false,
        expected: expected,
        given: answerText(answer),
        outcomes: [
          for (var i = 0; i < e.left.length; i++)
            rateOutcome(e.type, e.pairFacetIds[i]!, correct: false, elapsed: elapsed, options: options),
        ],
      );
    }
    final outcomes = <FacetOutcome>[];
    var all = true;
    for (var i = 0; i < e.left.length; i++) {
      final ok = answer.matches[i] == e.solution[i] && !answer.missed.contains(i);
      all &= ok;
      outcomes.add(rateOutcome(e.type, e.pairFacetIds[i]!, correct: ok, elapsed: elapsed, options: options));
    }
    String rightAt(int? j) => j == null || j < 0 || j >= e.right.length ? '?' : e.right[j];
    String leftAt(int i) => i < 0 || i >= e.left.length ? '?' : e.left[i];
    // The wrong pairs tried, when the board reports them (what the learner
    // actually answered wrong); else the final matches.
    final given = answer.wrongPairs.isNotEmpty
        ? [for (final (l, r) in answer.wrongPairs) '${leftAt(l)} = ${rightAt(r)}'].join('; ')
        : [for (var i = 0; i < e.left.length; i++) '${e.left[i]} = ${rightAt(answer.matches[i])}'].join('; ');
    return Result(correct: all, expected: expected, given: given, outcomes: outcomes);
  }
}
