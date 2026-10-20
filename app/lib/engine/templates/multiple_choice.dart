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

  /// `#form` only for recognition-only facets (docs/engine.md, "Recognition-only skills").
  @override
  Set<FacetKind> get kinds => const {FacetKind.rec, FacetKind.prod, FacetKind.article, FacetKind.form};

  @override
  bool canGenerate(SkillFacet facet, GenContext ctx) => supports(facet) &&
      (facet.kind != FacetKind.form || ctx.index.recognitionOnly(facet)) &&
      ctx.memo('multiple_choice/$sentenceShare/$optionCount|${facet.facetId}|${ctx.lang}', () => _can(facet, ctx));

  bool _can(SkillFacet facet, GenContext ctx) {
    final item = ctx.course.item(facet.itemId);
    if (item == null) return false;
    if (facet.kind == FacetKind.form) {
      return facet.tense != null && ctx.index.finiteForms(facet.itemId, facet.tense!).length >= 3;
    }
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
    if (facet.kind == FacetKind.form) return _form(facet, item, ctx);
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
    // Every meaning (any language) of the target and of its synonyms: an
    // item sharing one of them is no wrong option, whichever of its glosses
    // is displayed (`hello` for `ciao`, once a synonym says `hi` and `hello`).
    final accepted = rec
        ? {...ix.glossKeys(item), for (final s in ix.synonymsOf(item)) ...ix.glossKeys(s)}
        : const <String>{};
    final groups = ix.relatedItems(item);
    // Meanings in the language the right answer is shown in: a pack may lack
    // some glosses in the learner's language (the app then shows English), and
    // one English option among Dutch ones would give the answer away.
    final gl = glossLanguage(item, ctx.lang);
    for (final g in groups) {
      final list = shuffle ? ctx.shuffled(g) : g;
      for (final o in list) {
        if (picker.full) break;
        final text = rec ? ((o.tr[gl]?.isNotEmpty ?? false) ? o.tr[gl]!.first : '') : o.lemma;
        if (text.trim().isEmpty) continue;
        // A gloss that is also a meaning of the target is never wrong.
        if (rec && ix.glossKeysIn(item, ctx.lang).contains(foldAnswer(text))) continue;
        if (rec && ix.glossKeys(o).any(accepted.contains)) continue;
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

  /// Sentences of [item] the learner may meet (grammar gating).
  List<Sentence> _sentences(Item item, GenContext ctx) => [
        for (final s in ctx.course.sentencesFor(item.id))
          if ((s.translation(ctx.lang) ?? '').trim().isNotEmpty && ctx.sentenceOk(s)) s,
      ];

  // ---------------------------------------------------------------- recognition of forms

  /// A recognition-only `#form` facet (the passato remoto): a sentence with
  /// the form -> its translation, the form -> the same person's form in the
  /// skill's equivalent tense (`andò` -> `è andato`), or the form -> its
  /// person. The learner never produces a form of the tense.
  Exercise? _form(SkillFacet facet, Item item, GenContext ctx) {
    final ix = ctx.index;
    final tense = facet.tense;
    if (tense == null) return null;
    final cells = ix.finiteForms(item.id, tense);
    if (cells.length < 3) return null;
    final r = ctx.random.nextDouble();
    final attempts = <Exercise? Function()>[
      if (r < 0.4) () => _formSentence(facet, item, tense, ctx),
      if (r < 0.75) () => _formEquivalent(facet, item, cells, ctx),
      () => _formPerson(facet, item, cells, ctx),
      () => _formSentence(facet, item, tense, ctx),
      () => _formEquivalent(facet, item, cells, ctx),
    ];
    for (final a in attempts) {
      final e = a();
      if (e != null) return e;
    }
    return null;
  }

  Exercise? _formSentence(SkillFacet facet, Item item, String tense, GenContext ctx) {
    final pool = <Sentence>{
      for (final o in ctx.index.formOccurrencesIn(item.id, tense))
        if ((o.sentence.translation(ctx.lang) ?? '').trim().isNotEmpty && ctx.sentenceOk(o.sentence)) o.sentence,
    }.toList();
    return pool.isEmpty ? null : _sentence(facet, item, true, ctx, pool: pool);
  }

  /// Cells of [tense] spelled like [form] (several persons may share one).
  List<VerbForm> _sameSpelling(GenContext ctx, String itemId, String tense, String form) {
    final key = foldAnswer(form);
    return [
      for (final c in ctx.index.finiteForms(itemId, tense))
        if (c.accepted.any((a) => foldAnswer(a) == key)) c,
    ];
  }

  Exercise? _formEquivalent(SkillFacet facet, Item item, List<VerbForm> cells, GenContext ctx) {
    final eq = ctx.index.equivalentTense(facet);
    if (eq == null || !ctx.tenseShowable(eq)) return null;
    final forms = ctx.course.verbForms(item.id);
    final cell = ctx.pick(cells);
    final target = forms['$eq.${cell.person}'];
    if (target == null) return null;
    final same = _sameSpelling(ctx, item.id, cell.tense, cell.form);
    final forbidden = [
      for (final s in same)
        if (forms['$eq.${s.person}'] case final f?) ...f.accepted,
    ];
    final picker = OptionPicker(forbidden: forbidden, max: optionCount - 1);
    picker.addGroups([
      [for (final f in forms.values) if (f.tense == eq && f.person != kNoPerson) f.form],
    ], ctx.random);
    if (picker.picked.length < 2) return null;
    final (options, idx) = placeOptions(target.form, picker.picked, ctx.random);
    return MultipleChoiceExercise(
      id: ctx.nextId(),
      facetId: facet.facetId,
      skillId: ctx.skill?.id,
      instruction: instruction('mc.form.equivalent', ctx.lang),
      prompt: cell.form,
      options: options,
      correctIndex: idx,
      direction: Direction.recognize,
      hint: '${item.lemma} · ${ctx.course.meta.tenseLabel(eq, ctx.lang)}',
    );
  }

  Exercise? _formPerson(SkillFacet facet, Item item, List<VerbForm> cells, GenContext ctx) {
    final meta = ctx.course.meta;
    final cell = ctx.pick(cells);
    String label(String p) => meta.personLabel(p, ctx.lang, tense: cell.tense);
    final same = _sameSpelling(ctx, item.id, cell.tense, cell.form);
    final picker = OptionPicker(forbidden: [for (final s in same) label(s.person)], max: optionCount - 1);
    picker.addGroups([
      [for (final c in cells) label(c.person)],
    ], ctx.random);
    if (picker.picked.length < 2) return null;
    final (options, idx) = placeOptions(label(cell.person), picker.picked, ctx.random);
    return MultipleChoiceExercise(
      id: ctx.nextId(),
      facetId: facet.facetId,
      skillId: ctx.skill?.id,
      instruction: instruction('mc.form.person', ctx.lang),
      prompt: cell.form,
      options: options,
      correctIndex: idx,
      direction: Direction.recognize,
      hint: '${item.lemma} · ${meta.tenseLabel(cell.tense, ctx.lang)}',
    );
  }

  Exercise? _sentence(SkillFacet facet, Item item, bool rec, GenContext ctx, {List<Sentence>? pool}) {
    pool ??= _sentences(item, ctx);
    if (pool.isEmpty) return null;
    final ix = ctx.index;
    for (final s in ctx.prefer(pool, (s) => s, take: 4)) {
      final translation = s.translation(ctx.lang)!;
      final shuffled = ctx.shuffled(ix.allSentences);
      // Prefer sentences that share a word with [s]. Filtered lazily: only a
      // few candidates are needed.
      final lexes = {for (final t in s.tokens) if (t.lex != null) t.lex};
      bool related(Sentence t) => t.tokens.any((x) => x.lex != null && lexes.contains(x.lex));
      // Wrong target-language options are shown too: only sentences whose
      // grammar the learner knows (their words may be new: they are wrong anyway).
      bool usable(Sentence t) =>
          (t.translation(ctx.lang) ?? '').trim().isNotEmpty &&
          (rec || ctx.gate == null || ctx.gate!.featuresKnown(t.id)) &&
          !ix.equivalent(s, t);
      final ordered = shuffled
          .where((t) => related(t) && usable(t))
          .followedBy(shuffled.where((t) => !related(t) && usable(t)));

      final List<String> distractors;
      if (rec) {
        // Translations in the language the right one is shown in (see glossLanguage).
        final tl = s.tr.containsKey(ctx.lang) ? ctx.lang : 'en';
        final picker = OptionPicker(forbidden: [translation], max: optionCount - 1);
        for (final t in ordered) {
          if (picker.full) break;
          if (t.tr[tl] != null) picker.add(t.tr[tl]!);
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
            for (final sw in formSwaps(ix, o))
              if (sw.replacement.tense == o.tense || ctx.tenseShowable(sw.replacement.tense)) renderPairs(sw.render()),
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
      ctx.useSentence(s.id);
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
        sentenceTokens: tokenRefsOf(s),
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
