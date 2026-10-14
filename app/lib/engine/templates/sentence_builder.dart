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

/// Translate a source-language sentence by ordering target-word tiles.
/// Trains `#prod` of an item that appears in the sentence.
///
/// Distractor tiles: other persons' forms of the sentence's verbs, wrong
/// articles, and related words; never a word of the sentence, a spelling of a
/// synonym of one of its words, or an accepted form of one of its verb cells.
///
/// Accepted answers: the sentence's words, plus every other sentence with the
/// same translation whose words fit the tiles. Grading joins words, so an
/// elision split differently (`l'` + `acqua` vs `l'acqua`) is still accepted.
class SentenceBuilderTemplate extends ExerciseTemplate {
  const SentenceBuilderTemplate({this.maxWords = 12, this.distractorCount = 3});

  final int maxWords;
  final int distractorCount;

  @override
  ExerciseType get type => ExerciseType.sentenceBuilder;

  @override
  Set<FacetKind> get kinds => const {FacetKind.prod};

  List<Sentence> _pool(SkillFacet facet, GenContext ctx) => [
        for (final s in ctx.course.sentencesFor(facet.itemId))
          if ((s.translation(ctx.lang) ?? '').trim().isNotEmpty &&
              CourseIndex.words(s).length >= 2 &&
              CourseIndex.words(s).length <= maxWords)
            s,
      ];

  @override
  bool canGenerate(SkillFacet facet, GenContext ctx) =>
      supports(facet) &&
      ctx.index.memo('sentence_builder/$maxWords/$distractorCount|${facet.facetId}|${ctx.lang}',
          () => _pool(facet, ctx).any((s) => _distractors(s, ctx, shuffle: false).isNotEmpty));

  List<String> _distractors(Sentence s, GenContext ctx, {bool shuffle = true}) {
    final ix = ctx.index;
    final course = ctx.course;
    // The words of every sentence with the same translation: those may be
    // accepted answers too (`Come stai?` / `Come sta?` for "How are you?").
    final words = [
      for (final x in [s, ...ix.sentencesWithTranslation(ctx.lang, s.translation(ctx.lang) ?? '')])
        ...CourseIndex.words(x),
    ];
    final aligned = <Item>[
      for (final t in words)
        if (t.lex != null && course.item(t.lex!) != null) course.item(t.lex!)!,
    ];
    final forbidden = <String>[
      for (final t in words) t.t,
      for (final i in aligned)
        for (final syn in ix.synonymsOf(i)) ...syn.spellings,
      for (final t in words)
        if (t.lex != null && t.form != null && course.verbForms(t.lex!)[t.form!] != null)
          ...course.verbForms(t.lex!)[t.form!]!.accepted.expand(splitWords),
    ];
    final picker = OptionPicker(forbidden: forbidden, max: distractorCount);

    // Other persons' forms of the verbs (the word that differs).
    final verbSwaps = <String>[
      for (final o in ix.formOccurrencesInSentence(s))
        for (final sw in formSwaps(ix, o)) lowerFirst(sw.newWord),
    ];
    // Wrong articles, when the sentence uses one.
    final usesArticle = words.any((t) => ix.articleKeys.contains(normalizeAnswer(t.t)));
    final articles = <String>[
      if (usesArticle)
        for (final a in ctx.course.meta.articles)
          if (!normalizeApostrophes(a).endsWith("'")) a,
    ];
    // Related words of the same part of speech (single-word lemmas).
    final related = <String>[
      for (final i in aligned)
        if (i.pos != 'det' && i.pos != 'pron')
          for (final g in ix.relatedItems(i).take(2))
            for (final o in g.take(6))
              if (splitWords(o.lemma).length == 1) o.lemma,
    ];
    if (shuffle) {
      picker.addGroups([verbSwaps, articles, related], ctx.random);
    } else {
      for (final o in [...verbSwaps, ...articles, ...related]) {
        picker.add(o);
      }
    }
    return picker.picked;
  }

  @override
  Exercise? generate(SkillFacet facet, GenContext ctx) {
    if (!supports(facet)) return null;
    final ix = ctx.index;
    for (final s in ctx.shuffled(_pool(facet, ctx)).take(4)) {
      final distractors = _distractors(s, ctx);
      if (distractors.isEmpty) continue;
      final words = ix.tileWords(s);
      final tiles = ctx.shuffled([...words, ...distractors]);
      final translation = s.translation(ctx.lang)!;
      final answers = <List<String>>[words];
      final tileBag = _bag(tiles);
      for (final t in ix.sentencesWithTranslation(ctx.lang, translation)) {
        if (t.id == s.id) continue;
        final tw = ix.tileWords(t);
        if (_fits(_bag(tw), tileBag)) answers.add(tw);
      }
      return SentenceBuilderExercise(
        id: ctx.nextId(),
        facetId: facet.facetId,
        skillId: ctx.skill?.id,
        instruction: instruction('sentence_builder', ctx.lang),
        prompt: translation,
        tiles: tiles,
        answers: answers,
        sentenceId: s.id,
      );
    }
    return null;
  }

  static Map<String, int> _bag(List<String> words) {
    final m = <String, int>{};
    for (final w in words) {
      final k = normalizeAnswer(w);
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  static bool _fits(Map<String, int> need, Map<String, int> have) =>
      need.entries.every((e) => (have[e.key] ?? 0) >= e.value);

  @override
  Result grade(Exercise exercise, Answer answer, {required Duration elapsed, GradeOptions options = const GradeOptions()}) {
    final e = exercise as SentenceBuilderExercise;
    return gradeTiles(e, answer, e.answers, elapsed: elapsed, grade: options);
  }
}
