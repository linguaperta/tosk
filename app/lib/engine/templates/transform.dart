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

/// A rewritten sentence: (pre, text, isWord) per displayed token.
typedef _Rendered = List<(String, String, bool)>;

class _Plan {
  _Plan(this.occ, this.target, this.rendered, this.description, {required this.tenseSwap});
  final FormOccurrence occ;
  final VerbForm target;
  final _Rendered rendered;
  final String description;
  final bool tenseSwap;
}

/// Rebuild a sentence in another tense (or person) from tiles. Trains the
/// `#form:{tense}` facet of the target tense.
///
/// Generated only when the result is reliably constructible:
/// * same number of words (`mangio` -> `mangiavo`, `heb … gegeten` ->
///   `had … gegeten`): words are replaced in place, wherever they stand;
/// * compound -> single word (`ho mangiato` -> `mangio`, Dutch
///   `heb brood gegeten` -> `eet brood`): the finite (first) word is replaced
///   and the rest removed;
/// * single word -> compound: only when the course's sentences show that
///   tense's compound forms written contiguously (Italian), or the verb ends
///   the sentence (Dutch `Ik werk.` -> `Ik heb gewerkt.`), and no clitic
///   pronoun precedes the verb (`lo mangio` -> `l'ho mangiato` is not built).
/// * a person change only in pro-drop sentences (`Mangiamo alle otto.`):
///   the course's sentences usually omit the subject pronoun for both
///   persons ([CourseIndex.dropsPronoun]; never true for Dutch), nothing but
///   adverbs/conjunctions/prepositions precedes the verb, and the sentence
///   contains no pronoun at all.
/// Otherwise [canGenerate] is false.
class TransformTemplate extends ExerciseTemplate {
  const TransformTemplate({this.distractorCount = 3});

  final int distractorCount;

  static const Set<String> _adverbialPos = {'adv', 'conj', 'prep', 'intj'};

  @override
  ExerciseType get type => ExerciseType.transform;

  @override
  Set<FacetKind> get kinds => const {FacetKind.form};

  @override
  bool canGenerate(SkillFacet facet, GenContext ctx) =>
      supports(facet) &&
      ctx.index.memo('transform/$distractorCount|${facet.facetId}|${ctx.lang}',
          () => _plans(facet, ctx).any((p) => _distractors(p, ctx, shuffle: false).isNotEmpty));

  List<_Plan> _plans(SkillFacet facet, GenContext ctx) {
    final tense = facet.tense;
    if (tense == null) return const [];
    final ix = ctx.index;
    final meta = ctx.course.meta;
    final forms = ctx.course.verbForms(facet.itemId);
    final out = <_Plan>[];
    final infinitive = forms['infinitive.$kNoPerson'];
    for (final o in ix.formOccurrences(facet.itemId)) {
      // A finite form spelled like the infinitive (Dutch `vertellen`) may
      // really be an infinitive after a modal (`kan ik dat Tom niet
      // vertellen`): rewriting it is unreliable.
      if (infinitive != null && o.wordCount == 1 && ix.acceptedKeys(infinitive).contains(foldAnswer(o.matched))) {
        continue;
      }
      if (o.tense != tense && _tenseSwapOk(o, tense, ctx)) {
        final target = forms['$tense.${o.person}'];
        if (target != null) {
          final r = _construct(o, target.form, tense, ctx);
          if (r != null) out.add(_Plan(o, target, r, '→ ${meta.tenseLabel(tense, ctx.lang)}', tenseSwap: true));
        }
      }
      if (_personSwapOk(o, ctx)) {
        final ambiguous = ix.ambiguousPersons(o.person).toSet();
        for (final p in meta.persons) {
          if (p == o.person || ambiguous.contains(p) || !ix.dropsPronoun(p)) continue;
          final target = forms['$tense.$p'];
          if (target == null) continue;
          final r = _construct(o, target.form, tense, ctx);
          if (r == null) continue;
          final desc = o.tense == tense
              ? '→ ${meta.personLabel(p, ctx.lang)}'
              : '→ ${meta.personLabel(p, ctx.lang)}, ${meta.tenseLabel(tense, ctx.lang)}';
          out.add(_Plan(o, target, r, desc, tenseSwap: false));
        }
      }
    }
    return out;
  }

  /// A tense change keeps the sentence coherent only when every other finite
  /// verb is in the source or the target tense (`Wie was de filosoof die ooit
  /// geleefd heeft?` -> present would mix past and present), and a simple form
  /// does not become compound next to a participle (`gezegd werd` is a
  /// passive: `gezegd is geworden` is wrong).
  bool _tenseSwapOk(FormOccurrence o, String target, GenContext ctx) {
    final s = o.sentence;
    final aux = ctx.index.auxiliaryPositions(s);
    final tf = ctx.course.verbForms(o.verbId)['$target.${o.person}'];
    final toCompound = o.wordCount == 1 && tf != null && ctx.index.wordsOf(tf.form).length > 1;
    // An auxiliary next to a participle (`als ik nee had gezegd`) is a tense
    // of the other verb: `heb gezegd` is not the present of `had`.
    final lemma = ctx.course.item(o.verbId)?.lemma;
    final isAuxiliary = o.wordCount == 1 && lemma != null && ctx.index.auxiliaryLemmas.contains(lemma);
    for (var i = 0; i < s.tokens.length; i++) {
      final t = s.tokens[i];
      if (o.positions.contains(i) || aux.contains(i) || !t.isWord || t.lex == null) continue;
      // A verb whose form the alignment left open (`Wat wil je dat ik doe?`)
      // has an unknown tense.
      if (t.form == null) {
        if (ctx.course.verbForms(t.lex!).isNotEmpty) return false;
        continue;
      }
      final tense = t.tense;
      if (t.person == kNoPerson) {
        if (tense == 'participle' && (toCompound || isAuxiliary)) return false;
        continue;
      }
      if (tense != o.tense && tense != target) return false;
    }
    return true;
  }

  bool _personSwapOk(FormOccurrence o, GenContext ctx) {
    final ix = ctx.index;
    if (!ix.dropsPronoun(o.person)) return false;
    final s = o.sentence;
    final first = o.firstPos;
    final firstWord = s.tokens.indexWhere((t) => t.isWord);
    for (var i = 0; i < s.tokens.length; i++) {
      final t = s.tokens[i];
      if (!t.isWord || o.positions.contains(i)) continue;
      if (ix.isPronounToken(t)) return false;
      // A name anywhere may be the subject (`Heeft Tom … gezien?`).
      if (i != firstWord && t.t != lowerFirst(t.t)) return false;
      if (i < first) {
        final lex = t.lex;
        final item = lex == null ? null : ctx.course.item(lex);
        if (item == null || !_adverbialPos.contains(item.pos)) return false;
      }
    }
    return true;
  }

  /// The sentence with [o] replaced by [targetForm], or null when that is not
  /// reliably a valid sentence.
  _Rendered? _construct(FormOccurrence o, String targetForm, String targetTense, GenContext ctx) {
    final ix = ctx.index;
    final s = o.sentence;
    final tokens = s.tokens;
    final wt = splitWords(targetForm);
    final n = o.wordCount;
    if (wt.isEmpty) return null;
    final replace = <int, String>{};
    final delete = <int>{};
    if (wt.length == n) {
      // A form written out of order (Dutch subordinate `opgestaan ben`) only
      // keeps a valid order when the new form has the same shape: `sta op`
      // would become `op sta` (instead of `opsta`).
      if (n > 1 && targetTense != o.tense) {
        for (var k = 0; k + 1 < n; k++) {
          if (o.positions[k + 1] < o.positions[k]) return null;
        }
      }
      for (var k = 0; k < n; k++) {
        replace[o.positions[k]] = matchCase(wt[k], tokens[o.positions[k]].t);
      }
    } else if (n > 1 && wt.length == 1) {
      final firstWord = tokens.indexWhere((t) => t.isWord);
      for (final p in o.positions.skip(1)) {
        if (p == firstWord) return null; // would lose sentence-initial capitalization
        delete.add(p);
      }
      replace[o.positions[0]] = matchCase(wt[0], tokens[o.positions[0]].t);
    } else if (n == 1 && wt.length > 1) {
      final p = o.positions.single;
      final lastWord = tokens.lastIndexWhere((t) => t.isWord);
      if (!ix.contiguousTense(targetTense) && p != lastWord) {
        return null;
      }
      // No clitic pronoun (or short unknown word) directly before the verb.
      final prev = p - 1;
      if (prev >= 0 && tokens[prev].isWord) {
        final t = tokens[prev];
        final key = foldAnswer(t.t);
        final subject = ix.subjectPronounKeys.contains(key);
        if (!subject && (ix.isPronounToken(t) || (t.lex == null && key.length <= 2))) return null;
      }
      replace[p] = [matchCase(wt[0], tokens[p].t), ...wt.skip(1)].join(' ');
    } else {
      return null;
    }
    final out = <(String, String, bool)>[];
    for (var i = 0; i < tokens.length; i++) {
      if (delete.contains(i)) continue;
      out.add((tokens[i].pre, replace[i] ?? tokens[i].t, tokens[i].isWord));
    }
    if (normalizeAnswer(_text(out)) == normalizeAnswer(s.text)) return null;
    return out;
  }

  static String _text(_Rendered r) => renderPairs([for (final x in r) (x.$1, x.$2)]);

  List<String> _words(_Rendered r, FormOccurrence o, GenContext ctx) {
    final out = <String>[];
    for (final (_, text, isWord) in r) {
      if (isWord) out.addAll(splitWords(text));
    }
    if (out.isEmpty) return out;
    // Lower-case the first tile like the sentence builder does.
    final original = ctx.index.tileWords(o.sentence);
    final firstTok = o.sentence.tokens.firstWhere((t) => t.isWord);
    final wasLowered = original.isNotEmpty && original.first != firstTok.t;
    final verbFirst = o.positions.contains(o.sentence.tokens.indexOf(firstTok));
    if (wasLowered || verbFirst) out[0] = lowerFirst(out[0]);
    return out;
  }

  List<List<String>> _answers(_Plan p, GenContext ctx) {
    final canonical = _words(p.rendered, p.occ, ctx);
    final out = <List<String>>[canonical];
    final seen = {normalizeAnswer(canonical.join(' '))};
    for (final alt in p.target.alts) {
      final r = _construct(p.occ, alt, p.target.tense, ctx);
      if (r == null) continue;
      final w = _words(r, p.occ, ctx);
      if (seen.add(normalizeAnswer(w.join(' ')))) out.add(w);
    }
    return out;
  }

  List<String> _distractors(_Plan p, GenContext ctx, {bool shuffle = true}) {
    final ix = ctx.index;
    final answers = _answers(p, ctx);
    final forms = ctx.course.verbForms(p.occ.verbId);
    final ambiguous = ix.ambiguousPersons(p.target.person);
    final forbidden = <String>[
      for (final a in answers) ...a,
      for (final a in p.target.accepted) ...splitWords(a),
      for (final q in ambiguous)
        if (forms['${p.target.tense}.$q'] != null)
          for (final a in forms['${p.target.tense}.$q']!.accepted) ...splitWords(a),
    ];
    final picker = OptionPicker(forbidden: forbidden, max: distractorCount);
    final source = [for (final w in p.occ.surface) lowerFirst(w)];
    final others = [
      for (final f in ix.finiteForms(p.occ.verbId, p.target.tense))
        if (f.person != p.target.person) ...splitWords(f.form),
    ];
    if (shuffle) {
      picker.addGroups([source, others], ctx.random);
    } else {
      for (final w in [...source, ...others]) {
        picker.add(w);
      }
    }
    return picker.picked;
  }

  @override
  Exercise? generate(SkillFacet facet, GenContext ctx) {
    if (!supports(facet)) return null;
    final plans = _plans(facet, ctx);
    if (plans.isEmpty) return null;
    final tensePlans = [for (final p in plans) if (p.tenseSwap) p];
    final personPlans = [for (final p in plans) if (!p.tenseSwap) p];
    final ordered = <_Plan>[
      ...ctx.shuffled(tensePlans.isNotEmpty && (personPlans.isEmpty || ctx.random.nextDouble() < 0.7) ? tensePlans : personPlans),
      ...ctx.shuffled(plans),
    ];
    for (final p in ordered.take(6)) {
      final d = _distractors(p, ctx);
      if (d.isEmpty) continue;
      final answers = _answers(p, ctx);
      return TransformExercise(
        id: ctx.nextId(),
        facetId: facet.facetId,
        skillId: ctx.skill?.id,
        instruction: instruction('transform', ctx.lang),
        source: p.occ.sentence.text,
        targetDescription: p.description,
        tiles: ctx.shuffled([...answers.first, ...d]),
        answers: answers,
        sentenceId: p.occ.sentence.id,
        translation: p.occ.sentence.translation(ctx.lang),
        sourceTokens: tokenRefsOf(p.occ.sentence),
      );
    }
    return null;
  }

  @override
  Result grade(Exercise exercise, Answer answer, {required Duration elapsed, GradeOptions options = const GradeOptions()}) {
    final e = exercise as TransformExercise;
    return gradeTiles(e, answer, e.answers, elapsed: elapsed, grade: options);
  }
}
