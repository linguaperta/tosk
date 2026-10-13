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

/// Pick the translation of a word or sentence, in either direction, or the
/// article of a noun.
///
/// * `#rec`: target word -> meanings, or target sentence -> translations.
/// * `#prod`: meaning -> target words, or translation -> target sentences
///   (wrong options are the same sentence with one verb form or article
///   swapped, then other sentences).
/// * `#article`: `___ ragazzo` -> the course's article list.
class MultipleChoiceTemplate extends ExerciseTemplate {
  const MultipleChoiceTemplate({this.sentenceShare = 0.35, this.optionCount = 4});

  /// Probability of the sentence variant for rec/prod facets that are not
  /// fresh (1.0 forces it, even for fresh facets; 0 disables it).
  final double sentenceShare;
  final int optionCount;

  @override
  ExerciseType get type => ExerciseType.multipleChoice;

  @override
  Set<FacetKind> get kinds => const {FacetKind.rec, FacetKind.prod, FacetKind.article};

  @override
  bool canGenerate(SkillFacet facet, GenContext ctx) => supports(facet) &&
      ctx.index.memo('multiple_choice/$sentenceShare/$optionCount|${facet.facetId}|${ctx.lang}', () => _can(facet, ctx));

  bool _can(SkillFacet facet, GenContext ctx) {
    final item = ctx.course.item(facet.itemId);
    if (item == null) return false;
    if (facet.kind == FacetKind.article) {
      return ctx.index.articlesOf(item).isNotEmpty && wrongArticles(ctx.index, item).isNotEmpty;
    }
    if (sentenceShare >= 1) return _sentences(item, ctx).isNotEmpty;
    return _wordDistractors(item, facet.kind == FacetKind.rec, ctx, shuffle: false).length >= 2;
  }

  @override
  Exercise? generate(SkillFacet facet, GenContext ctx) {
    if (!supports(facet)) return null;
    final item = ctx.course.item(facet.itemId);
    if (item == null) return null;
    if (facet.kind == FacetKind.article) return _article(facet, item, ctx);
    final rec = facet.kind == FacetKind.rec;
    final trySentence = sentenceShare >= 1 ||
        (sentenceShare > 0 && ctx.stage(facet.facetId) != FacetStage.fresh && ctx.random.nextDouble() < sentenceShare);
    if (trySentence) {
      final s = _sentence(facet, item, rec, ctx);
      if (s != null || sentenceShare >= 1) return s;
    }
    return _word(facet, item, rec, ctx);
  }

  // ---------------------------------------------------------------- word

  List<String> _wordDistractors(Item item, bool rec, GenContext ctx, {bool shuffle = true}) {
    final ix = ctx.index;
    // Recognize: no meaning of the target or of any synonym (a meaning of
    // "hallo" is also right for "dag"). Produce: no spelling of either.
    final forbidden = rec
        ? [...item.glosses(ctx.lang), for (final s in ix.synonymsOf(item)) ...s.glosses(ctx.lang)]
        : [...item.spellings, for (final s in ix.synonymsOf(item)) ...s.spellings];
    final picker = OptionPicker(forbidden: forbidden, max: optionCount - 1);
    final groups = ix.relatedItems(item);
    for (final g in groups) {
      final list = shuffle ? ctx.shuffled(g) : g;
      for (final o in list) {
        if (picker.full) break;
        final text = rec ? o.gloss(ctx.lang) : o.lemma;
        if (text.trim().isEmpty) continue;
        // A gloss that is also a meaning of the target is never wrong.
        if (rec && ix.glossKeysIn(item, ctx.lang).contains(foldAnswer(text))) continue;
        picker.add(text);
      }
    }
    return picker.picked;
  }

  Exercise? _word(SkillFacet facet, Item item, bool rec, GenContext ctx) {
    final correct = rec ? item.gloss(ctx.lang) : item.lemma;
    final prompt = rec ? item.lemma : item.gloss(ctx.lang);
    if (correct.trim().isEmpty || prompt.trim().isEmpty) return null;
    final distractors = _wordDistractors(item, rec, ctx);
    if (distractors.length < 2) return null;
    final (options, idx) = placeOptions(correct, distractors, ctx.random);
    return MultipleChoiceExercise(
      id: ctx.nextId(),
      facetId: facet.facetId,
      skillId: ctx.skill?.id,
      instruction: instruction(rec ? 'mc.rec' : 'mc.prod', ctx.lang),
      prompt: prompt,
      options: options,
      correctIndex: idx,
      direction: rec ? Direction.recognize : Direction.produce,
      hint: rec && item.isNoun ? ctx.index.withArticle(item) : null,
    );
  }

  // ---------------------------------------------------------------- sentence

  List<Sentence> _sentences(Item item, GenContext ctx) => [
        for (final s in ctx.course.sentencesFor(item.id))
          if ((s.translation(ctx.lang) ?? '').trim().isNotEmpty) s,
      ];

  Exercise? _sentence(SkillFacet facet, Item item, bool rec, GenContext ctx) {
    final pool = _sentences(item, ctx);
    if (pool.isEmpty) return null;
    final ix = ctx.index;
    for (final s in ctx.shuffled(pool).take(4)) {
      final translation = s.translation(ctx.lang)!;
      final shuffled = ctx.shuffled(ix.allSentences);
      // Prefer sentences that share a word with [s]. Filtered lazily: only a
      // few candidates are needed.
      final lexes = {for (final t in s.tokens) if (t.lex != null) t.lex};
      bool related(Sentence t) => t.tokens.any((x) => x.lex != null && lexes.contains(x.lex));
      bool usable(Sentence t) => (t.translation(ctx.lang) ?? '').trim().isNotEmpty && !ix.equivalent(s, t);
      final ordered = shuffled
          .where((t) => related(t) && usable(t))
          .followedBy(shuffled.where((t) => !related(t) && usable(t)));

      final List<String> distractors;
      if (rec) {
        final picker = OptionPicker(forbidden: [translation], max: optionCount - 1);
        for (final t in ordered) {
          if (picker.full) break;
          picker.add(t.translation(ctx.lang)!);
        }
        distractors = picker.picked;
      } else {
        // Every course sentence with the same translation is right too (an
        // altered person can be one: `Riesce …` next to `Riesci …` for "Can you …").
        final picker = OptionPicker(forbidden: [
          s.text,
          for (final t in ix.sentencesWithTranslation(ctx.lang, translation)) t.text,
        ], max: optionCount - 1);
        final altered = <String>[
          for (final o in ix.formOccurrencesInSentence(s))
            for (final sw in formSwaps(ix, o)) renderPairs(sw.render()),
          for (final o in ix.articleOccurrencesInSentence(s))
            for (final a in wrongArticles(ix, ctx.course.item(o.nounId)!)) renderPairs(renderArticleSwap(o, a)),
        ];
        final alt = ctx.shuffled(altered);
        // At most two altered versions, then other sentences.
        for (final a in alt.take(2)) {
          picker.add(a);
        }
        for (final t in ordered) {
          if (picker.full) break;
          picker.add(t.text);
        }
        for (final a in alt) {
          picker.add(a);
        }
        distractors = picker.picked;
      }
      if (distractors.length < 2) continue;
      final correct = rec ? translation : s.text;
      final (options, idx) = placeOptions(correct, distractors, ctx.random);
      return MultipleChoiceExercise(
        id: ctx.nextId(),
        facetId: facet.facetId,
        skillId: ctx.skill?.id,
        instruction: instruction(rec ? 'mc.sentence.rec' : 'mc.sentence.prod', ctx.lang),
        prompt: rec ? s.text : translation,
        options: options,
        correctIndex: idx,
        direction: rec ? Direction.recognize : Direction.produce,
        isSentence: true,
      );
    }
    return null;
  }

  // ---------------------------------------------------------------- article

  Exercise? _article(SkillFacet facet, Item noun, GenContext ctx) {
    final ix = ctx.index;
    final valid = ix.articlesOf(noun);
    if (valid.isEmpty) return null;
    final picker = OptionPicker(forbidden: valid, max: optionCount - 1);
    picker.addGroups([wrongArticles(ix, noun)], ctx.random);
    if (picker.picked.isEmpty) return null;
    final (options, idx) = placeOptions(valid.first, picker.picked, ctx.random);
    return MultipleChoiceExercise(
      id: ctx.nextId(),
      facetId: facet.facetId,
      skillId: ctx.skill?.id,
      instruction: instruction('mc.article', ctx.lang),
      prompt: '___ ${noun.lemma}',
      options: options,
      correctIndex: idx,
      direction: Direction.produce,
      hint: noun.gloss(ctx.lang),
    );
  }

  @override
  Result grade(Exercise exercise, Answer answer, {required Duration elapsed, GradeOptions options = const GradeOptions()}) {
    final e = exercise as MultipleChoiceExercise;
    return gradeChoice(e, answer, e.options, e.correctIndex, elapsed: elapsed, grade: options);
  }
}
