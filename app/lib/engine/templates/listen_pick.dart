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

/// Listen and pick (v0.5): the UI speaks a target-language sentence (or, for
/// fresh facets and items without a usable sentence, the word) with on-device
/// text-to-speech; the learner picks what they heard among target-language
/// options. Trains `#rec`.
///
/// * Only generated when [SessionOptions.listening] says the device has a
///   voice for the course language (Sarnami: never).
/// * The spoken sentence follows grammar gating like every sentence template
///   ([GenContext.sentenceOk], [GenContext.prefer]); wrong sentences are other
///   sentences whose grammar the learner knows (their words may be new), of a
///   similar length, sharing a word first, plus at most one copy of the
///   sentence with one verb form or article swapped (a tense only when
///   [GenContext.tenseShowable]).
/// * No two options may sound alike: options are compared by [soundKey]
///   (diacritics, case, punctuation, silent `h`, doubled letters, final
///   `d`/`t` and spaces folded), so `ha`/`a`, `è`/`e` or Dutch `wordt`/`word`
///   never stand side by side.
class ListenPickTemplate extends ExerciseTemplate {
  const ListenPickTemplate({this.optionCount = 4, this.sentenceShare = 0.75});

  final int optionCount;

  /// Probability of the sentence variant for facets that are not fresh
  /// (1.0 forces it, even for fresh facets; 0 disables it).
  final double sentenceShare;

  @override
  ExerciseType get type => ExerciseType.listenPick;

  @override
  Set<FacetKind> get kinds => const {FacetKind.rec};

  @override
  bool canGenerate(SkillFacet facet, GenContext ctx) =>
      supports(facet) &&
      ctx.options.listening &&
      ctx.memo('listen_pick/$sentenceShare/$optionCount|${facet.facetId}|${ctx.lang}', () => _can(facet, ctx));

  bool _can(SkillFacet facet, GenContext ctx) {
    final item = ctx.course.item(facet.itemId);
    if (item == null) return false;
    if (sentenceShare >= 1) return _sentences(item, ctx).isNotEmpty;
    return _wordDistractors(item, ctx, shuffle: false).length >= 2 || _sentences(item, ctx).isNotEmpty;
  }

  @override
  Exercise? generate(SkillFacet facet, GenContext ctx) {
    if (!supports(facet) || !ctx.options.listening) return null;
    final item = ctx.course.item(facet.itemId);
    if (item == null) return null;
    final trySentence = sentenceShare >= 1 ||
        (sentenceShare > 0 && ctx.stage(facet.facetId) != FacetStage.fresh && ctx.random.nextDouble() < sentenceShare);
    if (trySentence) {
      final s = _sentence(facet, item, ctx);
      if (s != null || sentenceShare >= 1) return s;
    }
    return _word(facet, item, ctx) ?? (sentenceShare > 0 ? _sentence(facet, item, ctx) : null);
  }

  // ---------------------------------------------------------------- word

  /// Other words (lemmas) that look, and so probably sound, alike: same POS
  /// groups first ([CourseIndex.relatedItems]), then any item; a word of
  /// similar length sharing the first letter or the last two is preferred.
  List<String> _wordDistractors(Item item, GenContext ctx, {bool shuffle = true}) {
    final ix = ctx.index;
    final picker = _SoundPicker(
      forbidden: [...item.spellings, for (final s in ix.synonymsOf(item)) ...s.spellings],
      max: optionCount - 1,
    );
    final target = foldAnswer(item.lemma);
    bool alike(Item o) {
      final w = foldAnswer(o.lemma);
      if (w.isEmpty || target.isEmpty) return false;
      if ((w.length - target.length).abs() > 2) return false;
      return w[0] == target[0] ||
          (w.length >= 2 && target.length >= 2 && w.substring(w.length - 2) == target.substring(target.length - 2));
    }

    final groups = ix.relatedItems(item);
    final pool = [for (final g in groups) ...(shuffle ? ctx.shuffled(g) : g)];
    for (final o in pool.where(alike).followedBy(pool)) {
      if (picker.full) break;
      if (o.lemma.trim().isEmpty || o.lemma.contains(' ') != item.lemma.contains(' ')) continue;
      picker.add(o.lemma);
    }
    return picker.picked;
  }

  Exercise? _word(SkillFacet facet, Item item, GenContext ctx) {
    final text = item.lemma.trim();
    if (text.isEmpty) return null;
    final distractors = _wordDistractors(item, ctx);
    if (distractors.length < 2) return null;
    final (options, idx) = placeOptions(text, distractors, ctx.random);
    final gloss = item.gloss(ctx.lang);
    return ListenPickExercise(
      id: ctx.nextId(),
      facetId: facet.facetId,
      skillId: ctx.skill?.id,
      instruction: instruction('listen_pick.word', ctx.lang),
      text: text,
      languageCode: ctx.course.meta.target,
      options: options,
      correctIndex: idx,
      isSentence: false,
      translation: gloss.trim().isEmpty ? null : gloss,
    );
  }

  // ---------------------------------------------------------------- sentence

  /// Sentences of [item] the learner may meet (grammar gating).
  List<Sentence> _sentences(Item item, GenContext ctx) => [
        for (final s in ctx.course.sentencesFor(item.id))
          if (s.text.trim().isNotEmpty && ctx.sentenceOk(s)) s,
      ];

  static int _words(String s) => splitWords(s).length;

  /// Whether token [pos] follows an elided word (`c'è`): swapping it would
  /// read `c'siamo`.
  static bool _afterElision(Sentence s, int pos) =>
      pos > 0 && s.tokens[pos].pre.isEmpty && normalizeApostrophes(s.tokens[pos - 1].t).endsWith("'");

  Exercise? _sentence(SkillFacet facet, Item item, GenContext ctx) {
    final pool = _sentences(item, ctx);
    if (pool.isEmpty) return null;
    final ix = ctx.index;
    for (final s in ctx.prefer(pool, (s) => s, take: 4)) {
      final n = _words(s.text);
      final len = s.text.length;
      final lexes = {for (final t in s.tokens) if (t.lex != null) t.lex};
      bool related(Sentence t) => t.tokens.any((x) => x.lex != null && lexes.contains(x.lex));
      // Shown as text: only grammar the learner knows (words may be new).
      bool usable(Sentence t) {
        if (ctx.gate != null && !ctx.gate!.featuresKnown(t.id)) return false;
        final m = _words(t.text);
        if ((m - n).abs() > 2) return false;
        final ratio = t.text.length / (len == 0 ? 1 : len);
        if (ratio < 0.6 || ratio > 1.6) return false;
        return !ix.equivalent(s, t);
      }

      final shuffled = ctx.shuffled(ix.allSentences);
      final ordered = shuffled
          .where((t) => related(t) && usable(t))
          .followedBy(shuffled.where((t) => !related(t) && usable(t)));
      final picker = _SoundPicker(forbidden: [s.text], max: optionCount - 1);
      // One altered copy (a swapped verb form or article): the most
      // similar-sounding wrong option there is.
      final altered = <String>[
        for (final o in ix.formOccurrencesInSentence(s))
          for (final sw in formSwaps(ix, o))
            if ((sw.replacement.tense == o.tense || ctx.tenseShowable(sw.replacement.tense)) && !_afterElision(s, sw.tokenPos))
              renderPairs(sw.render()),
        for (final o in ix.articleOccurrencesInSentence(s))
          for (final a in wrongArticles(ix, ctx.course.item(o.nounId)!)) renderPairs(renderArticleSwap(o, a)),
      ];
      for (final a in ctx.shuffled(altered)) {
        if (picker.add(a)) break;
      }
      for (final t in ordered) {
        if (picker.full) break;
        picker.add(t.text);
      }
      if (picker.picked.length < 2) continue;
      final (options, idx) = placeOptions(s.text, picker.picked, ctx.random);
      ctx.useSentence(s.id);
      return ListenPickExercise(
        id: ctx.nextId(),
        facetId: facet.facetId,
        skillId: ctx.skill?.id,
        instruction: instruction('listen_pick', ctx.lang),
        text: s.text,
        languageCode: ctx.course.meta.target,
        options: options,
        correctIndex: idx,
        translation: s.translation(ctx.lang),
        sentenceId: s.id,
        tokens: tokenRefsOf(s),
      );
    }
    return null;
  }

  @override
  Result grade(Exercise exercise, Answer answer, {required Duration elapsed, GradeOptions options = const GradeOptions()}) {
    final e = exercise as ListenPickExercise;
    return gradeChoice(e, answer, e.options, e.correctIndex, elapsed: elapsed, grade: options);
  }
}

/// [OptionPicker] that also rejects options sounding like the forbidden text
/// or like an option already picked ([soundKey]).
class _SoundPicker extends OptionPicker {
  _SoundPicker({required List<String> forbidden, required super.max})
      : _sounds = {for (final f in forbidden) soundKey(f)},
        super(forbidden: forbidden);

  final Set<String> _sounds;

  @override
  bool add(String option) {
    if (full) return false;
    final k = soundKey(option);
    if (k.isEmpty || _sounds.contains(k)) return false;
    if (!super.add(option)) return false;
    _sounds.add(k);
    return true;
  }
}

final RegExp _doubled = RegExp(r'(.)\1+');
final RegExp _finalD = RegExp(r'(dt|d)$');

/// A crude "sounds like" key for listening options: [foldAnswer] (case,
/// punctuation, apostrophes, diacritics), then per word a silent `h` dropped,
/// a final `d`/`dt` read as `t` (Dutch final devoicing: `word`/`wordt`,
/// `gebeurd`/`gebeurt`), `ij`/`y` read as `ei`/`i`, doubled letters
/// collapsed, and the words joined without spaces (liaison: `l'acqua`).
/// Two options with the same key are never offered together.
String soundKey(String s) {
  final words = splitWords(foldAnswer(s).replaceAll("'", ' '));
  final b = StringBuffer();
  for (var w in words) {
    w = w.replaceAll('h', '').replaceAll('ij', 'ei').replaceAll('y', 'i');
    w = w.replaceAll(_finalD, 't').replaceAllMapped(_doubled, (m) => m[1]!);
    b.write(w);
  }
  return b.toString().replaceAllMapped(_doubled, (m) => m[1]!);
}
