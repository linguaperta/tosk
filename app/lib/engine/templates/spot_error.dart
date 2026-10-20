import '../../core/models/course.dart';
import '../../core/models/exercise.dart';
import '../../core/models/facet.dart';
import '../../core/models/progress.dart';
import '../course_index.dart';
import '../gen_context.dart';
import '../grading/rating.dart';
import '../strings.dart';
import '../template.dart';
import '../text/normalize.dart';
import 'alterations.dart';
import 'inflection.dart';

/// One planned error in a sentence.
class _Plan {
  _Plan(this.sentenceId, this.translation, this.tokens, this.errorIndex, this.correction);
  final String sentenceId;
  final String? translation;
  final List<(String, String)> tokens;
  final int errorIndex;
  final String correction;
}

/// Tap the wrong word.
///
/// * `#form:{tense}`: one word of the verb form is replaced by the matching
///   word of another person's form in the same tense, only when that
///   form is not an accepted form of the cell nor of a person sharing its
///   pronoun (Italian `sono` io/loro, Dutch `eet` ik/jij/hij are never used).
/// * `#article`: the article before the noun is replaced by a wrong one.
///
/// Without an explicit subject a person swap can be grammatical on its own
/// (pro-drop: `Mangiate alle otto`), so the translation is always included:
/// the error is defined relative to it.
class SpotErrorTemplate extends ExerciseTemplate {
  const SpotErrorTemplate();

  @override
  ExerciseType get type => ExerciseType.spotError;

  @override
  Set<FacetKind> get kinds => const {FacetKind.form, FacetKind.article, FacetKind.infl};

  @override
  bool canGenerate(SkillFacet facet, GenContext ctx) =>
      supports(facet) &&
      ctx.memo('spot_error|${facet.facetId}|${ctx.lang}', () => _plans(facet, ctx, shuffle: false, limit: 1).isNotEmpty);

  List<_Plan> _plans(SkillFacet facet, GenContext ctx, {bool shuffle = true, int limit = 1 << 30}) {
    final ix = ctx.index;
    final out = <_Plan>[];
    // Only sentences the learner may meet; when generating, the best first.
    Iterable<T> order<T>(List<T> occ, Sentence Function(T) sentence) =>
        shuffle ? ctx.prefer(occ, sentence) : occ.where((o) => ctx.sentenceOk(sentence(o)));
    if (facet.kind == FacetKind.form && facet.tense != null) {
      final occ = ix.formOccurrencesIn(facet.itemId, facet.tense!);
      for (final o in order(occ, (o) => o.sentence)) {
        if (out.length >= limit) break;
        // Only other persons of the same tense: a swap to another tense
        // (`De leerlingen mogen` -> `mochten`) usually leaves a grammatical
        // sentence that is wrong only against the translation.
        // ... and not a person the translation may mean as well (English
        // "you": tú, usted, vosotros, ustedes) when the sentence names none.
        // Every person spelled like the new form counts (`hacía`: yo and
        // usted).
        final tr = o.sentence.translation(ctx.lang);
        final forms = ctx.course.verbForms(o.verbId).values.where((f) => f.tense == o.tense).toList();
        bool youToo(FormSwap s) {
          final key = foldAnswer(s.replacement.form);
          return forms.any((f) => foldAnswer(f.form) == key && ix.sharesTranslation(o, f.person, tr, ctx.lang));
        }

        final pool = [
          for (final s in formSwaps(ix, o))
            if (s.replacement.tense == o.tense && !youToo(s)) s,
        ];
        if (pool.isEmpty) continue;
        final sw = shuffle ? ctx.pick(pool) : pool.first;
        out.add(_Plan(
          o.sentence.id,
          o.sentence.translation(ctx.lang),
          sw.render(),
          sw.tokenPos,
          o.sentence.tokens[sw.tokenPos].t,
        ));
      }
    } else if (facet.kind == FacetKind.infl && facet.table != null) {
      // One inflected word replaced: another cell of an agreement table (`La
      // casa è bello`), or a wrong form that is no word (`twee katen`).
      final spec = inflTableOf(ctx, facet);
      final occ = [
        for (final o in inflOccurrences(ix, facet.itemId, facet.table!))
          if (inflAskable(spec, o.cell) && !(shuffle && ctx.shownRecently(o.sentence.id))) o,
      ];
      for (final o in order(occ, (o) => o.sentence)) {
        if (out.length >= limit) break;
        final pool = inflSentenceWrongs(ctx.course, o);
        if (pool.isEmpty) continue;
        final rep = shuffle ? ctx.pick(pool) : pool.first;
        out.add(_Plan(
          o.sentence.id,
          o.sentence.translation(ctx.lang),
          [
            for (var i = 0; i < o.sentence.tokens.length; i++)
              (o.sentence.tokens[i].pre, i == o.pos ? rep : o.sentence.tokens[i].t),
          ],
          o.pos,
          o.text,
        ));
      }
    } else if (facet.kind == FacetKind.article) {
      final noun = ctx.course.item(facet.itemId);
      if (noun == null) return out;
      final wrong = wrongArticles(ix, noun);
      if (wrong.isEmpty) return out;
      final occ = ix.articleOccurrences(facet.itemId);
      for (final o in order(occ, (o) => o.sentence)) {
        if (out.length >= limit) break;
        final rep = shuffle ? ctx.pick(wrong) : wrong.first;
        final idx = o.withinToken ? o.nounPos : o.articlePos;
        out.add(_Plan(
          o.sentence.id,
          o.sentence.translation(ctx.lang),
          renderArticleSwap(o, rep),
          idx,
          o.sentence.tokens[idx].t,
        ));
      }
    }
    return out;
  }

  @override
  Exercise? generate(SkillFacet facet, GenContext ctx) {
    if (!supports(facet)) return null;
    final plans = _plans(facet, ctx, limit: 1);
    if (plans.isEmpty) return null;
    final p = plans.first;
    final sentence = ctx.course.sentence(p.sentenceId)!;
    ctx.useSentence(p.sentenceId);
    return SpotErrorExercise(
      id: ctx.nextId(),
      facetId: facet.facetId,
      skillId: ctx.skill?.id,
      instruction: instruction('spot_error', ctx.lang),
      tokens: [for (final t in p.tokens) t.$2],
      tokenPre: [for (final t in p.tokens) t.$1],
      tokenIsWord: [for (final t in sentence.tokens) t.isWord],
      errorIndex: p.errorIndex,
      correction: p.correction,
      translation: p.translation,
      sentenceId: p.sentenceId,
      tokenRefs: [
        for (var i = 0; i < p.tokens.length; i++)
          TokenRef(
            p.tokens[i].$2,
            pre: p.tokens[i].$1,
            itemId: i < sentence.tokens.length ? sentence.tokens[i].lex : null,
            form: i < sentence.tokens.length ? sentence.tokens[i].form : null,
            isWord: i < sentence.tokens.length ? sentence.tokens[i].isWord : true,
          ),
      ],
    );
  }

  @override
  Result grade(Exercise exercise, Answer answer, {required Duration elapsed, GradeOptions options = const GradeOptions()}) {
    final e = exercise as SpotErrorExercise;
    final idx = answer is TokenAnswer ? answer.index : -1;
    final correct = idx == e.errorIndex;
    return Result(
      correct: correct,
      expected: '${e.tokens[e.errorIndex]} → ${e.correction}',
      given: idx >= 0 && idx < e.tokens.length ? e.tokens[idx] : answerText(answer),
      outcomes: [rateOutcome(e.type, e.facetId, correct: correct, elapsed: elapsed, options: options)],
    );
  }
}

/// Renders a spot-error exercise's tokens (with [SpotErrorExercise.tokenPre]).
String renderSpotError(SpotErrorExercise e, {Map<int, String> replace = const {}}) => renderPairs([
      for (var i = 0; i < e.tokens.length; i++)
        (e.tokenPre == null ? (i == 0 ? '' : ' ') : e.tokenPre![i], replace[i] ?? e.tokens[i]),
    ]);
