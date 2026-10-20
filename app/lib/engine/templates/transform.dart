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
  _Plan(this.occ, this.target, this.rendered, this.description,
      {required this.tenseSwap, required this.fromLabel, required this.toLabel});
  final FormOccurrence occ;
  final VerbForm target;
  final _Rendered rendered;
  final String description;
  final bool tenseSwap;

  /// The UI's "from → to" chip: tense labels, or person labels (with the
  /// tense when that changes too).
  final String fromLabel;
  final String toLabel;
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
      ctx.memo('transform/$distractorCount|${facet.facetId}|${ctx.lang}',
          () => _plans(facet, ctx).any((p) => _distractors(p, ctx, shuffle: false).isNotEmpty));

  List<_Plan> _plans(SkillFacet facet, GenContext ctx) {
    final tense = facet.tense;
    if (tense == null) return const [];
    // Grammar gating: the result shows the target tense (and the facet's
    // constructs, e.g. `aux:essere` or `irregular:futuro`), so the learner
    // must know them, like every feature of the source sentence.
    if (!ctx.featureKnown('tense:$tense')) return const [];
    if (!ctx.course.skillFeatures(facet.skillId).every(ctx.featureKnown)) return const [];
    final ix = ctx.index;
    final meta = ctx.course.meta;
    final forms = ctx.course.verbForms(facet.itemId);
    final out = <_Plan>[];
    final infinitive = forms['infinitive.$kNoPerson'];
    for (final o in ix.formOccurrences(facet.itemId)) {
      if (!ctx.sentenceOk(o.sentence)) continue;
      // Another finite verb would keep its tense or person (`Il dolore va e
      // viene` -> `va e è venuto`): only sentences with one finite verb.
      if (!_onlyFiniteVerb(o, ctx)) continue;
      // A finite form spelled like the infinitive (Dutch `vertellen`) may
      // really be an infinitive after a modal (`kan ik dat Tom niet
      // vertellen`): rewriting it is unreliable.
      if (infinitive != null && o.wordCount == 1 && ix.acceptedKeys(infinitive).contains(foldAnswer(o.matched))) {
        continue;
      }
      if (o.tense != tense && _tenseSwapOk(o, tense, ctx) && _adverbsAllow(o.sentence, tense, ctx)) {
        final target = forms['$tense.${o.person}'];
        // A form shared by another person (`sono`: io and loro) is only
        // rewritten when that person's target form is the same.
        final matched = foldAnswer(o.matched);
        final unsurePerson = ix.finiteForms(o.verbId, o.tense).any((c) =>
            c.person != o.person &&
            ix.acceptedKeys(c).contains(matched) &&
            forms['$tense.${c.person}']?.form != target?.form);
        if (target != null && !unsurePerson && !_unsureAgreement(o, target, ctx)) {
          final r = _construct(o, target.form, tense, ctx);
          if (r != null) {
            out.add(_Plan(o, target, r, '→ ${meta.tenseLabel(tense, ctx.lang)}',
                tenseSwap: true,
                fromLabel: meta.tenseLabel(o.tense, ctx.lang),
                toLabel: meta.tenseLabel(tense, ctx.lang)));
          }
        }
      }
      if (_personSwapOk(o, ctx)) {
        final ambiguous = ix.ambiguousPersons(o.person).toSet();
        for (final p in meta.persons) {
          if (p == o.person || ambiguous.contains(p) || !ix.dropsPronoun(p)) continue;
          // Singular <-> plural would leave an adjective unagreed (`Dice di
          // essere bravo` -> `Diciamo di essere bravo`).
          if (_plural(o.person, meta) != _plural(p, meta) && (_hasAgreeingWord(o, ctx) || _isCopula(o, ctx))) continue;
          final target = forms['$tense.$p'];
          if (target == null || _unsureAgreement(o, target, ctx)) continue;
          if (o.tense != tense && !_adverbsAllow(o.sentence, tense, ctx)) continue;
          final r = _construct(o, target.form, tense, ctx);
          if (r == null) continue;
          final desc = o.tense == tense
              ? '→ ${meta.personLabel(p, ctx.lang)}'
              : '→ ${meta.personLabel(p, ctx.lang)}, ${meta.tenseLabel(tense, ctx.lang)}';
          final sameTense = o.tense == tense;
          out.add(_Plan(o, target, r, desc,
              tenseSwap: false,
              fromLabel: sameTense
                  ? meta.personLabel(o.person, ctx.lang)
                  : '${meta.personLabel(o.person, ctx.lang)}, ${meta.tenseLabel(o.tense, ctx.lang)}',
              toLabel: sameTense
                  ? meta.personLabel(p, ctx.lang)
                  : '${meta.personLabel(p, ctx.lang)}, ${meta.tenseLabel(tense, ctx.lang)}'));
        }
      }
    }
    return out;
  }

  /// Whether [o] is the sentence's only finite verb (its auxiliary belongs to it).
  bool _onlyFiniteVerb(FormOccurrence o, GenContext ctx) {
    final s = o.sentence;
    final aux = ctx.index.auxiliaryPositions(s);
    for (var i = 0; i < s.tokens.length; i++) {
      final t = s.tokens[i];
      if (o.positions.contains(i) || aux.contains(i) || !t.isWord || t.lex == null) continue;
      // A verb whose person the alignment left open is finite too.
      if (t.form == null ? ctx.course.verbForms(t.lex!).isNotEmpty : t.person != kNoPerson) return false;
    }
    return true;
  }

  /// No time adverb of the sentence ties it to other tenses than [target]
  /// (`Adesso mangio` is never rewritten into a past tense, `Ieri ho
  /// mangiato` never into the present). The adverbs are course data
  /// ([CourseMeta.timeAdverbs], course.yaml `time_adverbs`).
  bool _adverbsAllow(Sentence s, String target, GenContext ctx) {
    for (final tenses in ctx.index.timeAdverbTenses(s)) {
      if (!tenses.contains(target)) return false;
    }
    return true;
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

  static final RegExp _itWords =
      RegExp(r"(^|[^\p{L}'])(it|it's|its|het|there)($|[^\p{L}'])", unicode: true, caseSensitive: false);

  /// Whether [person] is plural: the second half of a six-person list
  /// (`noi voi loro`, `wij jullie zij`); false for other person lists.
  static bool _plural(String person, CourseMeta meta) =>
      meta.persons.length == 6 && meta.persons.indexOf(person) >= 3;

  /// "to be": a number change would leave its predicate unagreed (`Non siamo
  /// parenti` -> `Non è parenti`).
  bool _isCopula(FormOccurrence o, GenContext ctx) =>
      ctx.course.item(o.verbId)?.tr['en']?.any((g) => g == 'to be' || g == 'be') ?? false;

  /// A target form whose gendered alternatives (`sono successi;sono
  /// successe`) depend on a third-person subject the sentence may name with a
  /// noun (`Le cose succedono`) or leave impersonal (`Come va?`: `è andata`).
  bool _unsureAgreement(FormOccurrence o, VerbForm target, GenContext ctx) {
    // Gendered: an alternative that differs only in the last letter
    // (not Dutch `heeft gelopen;is gelopen`).
    final w = splitWords(target.form);
    bool gendered(String alt) {
      final a = splitWords(alt);
      if (a.length != w.length || a.isEmpty) return false;
      for (var k = 0; k + 1 < a.length; k++) {
        if (a[k] != w[k]) return false;
      }
      final x = a.last, y = w.last;
      return x != y && x.length == y.length && x.substring(0, x.length - 1) == y.substring(0, y.length - 1);
    }

    if (!target.alts.any(gendered)) return false;
    final meta = ctx.course.meta;
    if (!(meta.persons.length == 6 && {2, 5}.contains(meta.persons.indexOf(target.person)))) return false;
    final s = o.sentence;
    return s.tr.values.any(_itWords.hasMatch) ||
        s.tokens.any((t) => t.isWord && t.lex != null && ctx.course.item(t.lex!)?.isNoun == true);
  }

  /// Whether a translation of [o]'s sentence contains a pronoun from [o]'s
  /// person label in that language. True when the labels name no pronouns.
  bool _translationNamesPerson(FormOccurrence o, GenContext ctx) {
    var labelled = false;
    for (final e in o.sentence.tr.entries) {
      final pronouns = ctx.index.translationPronouns(o.person, e.key);
      if (pronouns.isEmpty) continue;
      labelled = true;
      final words = e.value.toLowerCase().split(_nonLetters).toSet();
      if (pronouns.any(words.contains)) return true;
    }
    return !labelled;
  }

  static final RegExp _nonLetters = RegExp(r'[^\p{L}]+', unicode: true);

  /// An infinitive after the verb ([o]'s last word).
  bool _infinitiveAfter(FormOccurrence o) {
    final tokens = o.sentence.tokens;
    for (var i = o.positions.last + 1; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.isWord && t.lex != null && t.tense == 'infinitive') return true;
    }
    return false;
  }

  /// An adjective or participle that may agree with the subject.
  bool _hasAgreeingWord(FormOccurrence o, GenContext ctx) {
    for (var i = 0; i < o.sentence.tokens.length; i++) {
      final t = o.sentence.tokens[i];
      if (!t.isWord || t.lex == null || o.positions.contains(i)) continue;
      if (t.person == kNoPerson && t.tense == 'participle') return true;
      if (ctx.course.item(t.lex!)?.pos == 'adj') return true;
    }
    return false;
  }

  bool _personSwapOk(FormOccurrence o, GenContext ctx) {
    final ix = ctx.index;
    if (!ix.dropsPronoun(o.person)) return false;
    // A third person singular without a subject may be impersonal (`Sembra
    // ieri`: it seems like yesterday; `È ora di …`): not when a translation
    // says "it"/"there" (Dutch "het").
    final meta = ctx.course.meta;
    // A form shared by two persons (Italian `sono`: io and loro) may be
    // aligned to the wrong one (`Dove sono i vostri nipoti?`).
    final matched = foldAnswer(o.matched);
    for (final c in ix.finiteForms(o.verbId, o.tense)) {
      if (c.person != o.person && ix.acceptedKeys(c).contains(matched)) return false;
    }
    // Third persons (plural too: `Son las diez`, it's ten o'clock) whose
    // translation says "it"/"there" are impersonal.
    final thirdAny = meta.persons.length == 6 && {2, 5}.contains(meta.persons.indexOf(o.person));
    if (thirdAny && o.sentence.tr.values.any(_itWords.hasMatch)) return false;
    // "to be" + an infinitive is impersonal (`Es necesario estudiar`, `È
    // importante dormire`: it is necessary to ...), whatever the translation.
    if (thirdAny && _isCopula(o, ctx) && _infinitiveAfter(o)) return false;
    // A dropped third-person subject is a person: a translation names it
    // with a pronoun of the person's label (he/she/you, they). Otherwise the
    // verb is impersonal or has another subject (`Aún queda mucho por
    // hacer`: much remains to be done).
    if (thirdAny && !_translationNamesPerson(o, ctx)) return false;
    // A third person's subject may be a noun anywhere (`Dove sono i suoi
    // zii?`): only sentences without nouns.
    if (thirdAny &&
        o.sentence.tokens.any((t) => t.isWord && t.lex != null && ctx.course.item(t.lex!)?.isNoun == true)) {
      return false;
    }
    final s = o.sentence;
    final first = o.firstPos;
    final firstWord = s.tokens.indexWhere((t) => t.isWord);
    for (var i = 0; i < s.tokens.length; i++) {
      final t = s.tokens[i];
      if (!t.isWord || o.positions.contains(i)) continue;
      if (ix.isPronounToken(t, trustAlignment: true)) return false;
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
    // An elided word before a changed word must still be followed by a
    // vowel (`l'ha fatto` -> `l'faceva` would need `lo faceva`).
    for (final e in replace.entries) {
      final p = e.key;
      if (p == 0 || !tokens[p - 1].isWord || !normalizeApostrophes(tokens[p - 1].t).endsWith("'")) continue;
      final next = foldDiacritics(e.value.toLowerCase());
      if (next.isEmpty || !'aeiouh'.contains(next[0])) return null;
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
    Sentence sentence(_Plan p) => p.occ.sentence;
    final ordered = <_Plan>[
      ...ctx.prefer(
          tensePlans.isNotEmpty && (personPlans.isEmpty || ctx.random.nextDouble() < 0.7) ? tensePlans : personPlans,
          sentence,
          take: 6),
      ...ctx.prefer(plans, sentence, take: 6),
    ];
    for (final p in ordered.take(6)) {
      final d = _distractors(p, ctx);
      if (d.isEmpty) continue;
      final answers = _answers(p, ctx);
      ctx.useSentence(p.occ.sentence.id);
      return TransformExercise(
        id: ctx.nextId(),
        facetId: facet.facetId,
        skillId: ctx.skill?.id,
        instruction: instruction(p.tenseSwap ? 'transform.tense' : 'transform.person', ctx.lang),
        source: p.occ.sentence.text,
        targetDescription: p.description,
        change: p.tenseSwap ? TransformChange.tense : TransformChange.person,
        fromLabel: p.fromLabel,
        toLabel: p.toLabel,
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
