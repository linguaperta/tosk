/// Derived, cached lookups over a [CourseData] used by the templates:
/// verb-form occurrences in sentences (including multi-word and split
/// compound forms), article occurrences, synonyms and distractor pools.
library;

import '../core/interfaces/course_data.dart';
import '../core/models/course.dart';
import 'text/normalize.dart';

/// A verb form found in a sentence.
///
/// [positions] are indices into `sentence.tokens`, one per word of [matched],
/// in the order of the words of the form (not necessarily sentence order: a
/// Dutch subordinate clause has `gegeten heb` for the form `heb gegeten`).
class FormOccurrence {
  FormOccurrence(this.sentence, this.verbId, this.cell, this.matched, this.positions);

  final Sentence sentence;
  final String verbId;
  final VerbForm cell;

  /// The accepted form (canonical or alternative) that matched the tokens.
  final String matched;
  final List<int> positions;

  String get tense => cell.tense;
  String get person => cell.person;
  List<String> get words => splitWords(matched);
  int get wordCount => positions.length;

  /// Surface text of each form word as written in the sentence.
  List<String> get surface => [for (final p in positions) sentence.tokens[p].t];

  /// True when the form's words are adjacent and in form order.
  bool get contiguous {
    for (var i = 0; i + 1 < positions.length; i++) {
      if (positions[i + 1] != positions[i] + 1) return false;
    }
    return true;
  }

  int get firstPos => positions.reduce((a, b) => a < b ? a : b);
  int get lastPos => positions.reduce((a, b) => a > b ? a : b);
}

/// A definite article directly before its noun.
class ArticleOccurrence {
  ArticleOccurrence({
    required this.sentence,
    required this.nounId,
    required this.articlePos,
    required this.nounPos,
    required this.article,
    required this.withinToken,
  });

  final Sentence sentence;
  final String nounId;

  /// Token holding the article (== [nounPos] when [withinToken]).
  final int articlePos;
  final int nounPos;

  /// The article as written in the sentence (e.g. `Il`, `l'`).
  final String article;

  /// Elided article and noun in one token, e.g. `l'acqua`.
  final bool withinToken;

  /// The noun as written (without the article for [withinToken]).
  String get nounText {
    final t = sentence.tokens[nounPos].t;
    return withinToken ? t.substring(article.length) : t;
  }
}

/// A non-verb item in a sentence written as its lemma/variant or plural.
class WordOccurrence {
  WordOccurrence(this.sentence, this.itemId, this.pos, {required this.plural});
  final Sentence sentence;
  final String itemId;
  final int pos;
  final bool plural;
}

class CourseIndex {
  CourseIndex._(this.course);

  static final Expando<CourseIndex> _cache = Expando('CourseIndex');

  /// The (cached) index of [course].
  static CourseIndex of(CourseData course) => _cache[course] ??= CourseIndex._(course);

  final CourseData course;

  CourseMeta get meta => course.meta;

  // ------------------------------------------------------------ persons

  /// Subject pronouns of each person: the parts of the person key (`hij/zij`)
  /// and of its labels outside parentheses (`jij/je (you)` adds `je`), so
  /// `Je werkt` counts as having its pronoun.
  late final Map<String, Set<String>> _personComponents = {
    for (final p in meta.persons)
      p: {
        for (final c in p.split('/')) foldAnswer(c),
        for (final label in (meta.personLabels[p] ?? const <String, String>{}).values)
          for (final c in label.replaceAll(_parens, ' ').split('/')) foldAnswer(c),
      }..remove(''),
  };

  /// Persons other than [person] that share a pronoun with it, e.g. Dutch
  /// `hij/zij` and `zij`. Swapping between them may still be correct in
  /// context, so they are never used as wrong options for each other.
  List<String> ambiguousPersons(String person) {
    final mine = _personComponents[person] ?? const <String>{};
    return [
      for (final p in meta.persons)
        if (p != person && (_personComponents[p] ?? const <String>{}).any(mine.contains)) p,
    ];
  }

  /// Folded subject pronouns from the person keys plus lemmas of pronoun items.
  late final Set<String> pronounKeys = {
    for (final cs in _personComponents.values) ...cs,
    for (final i in course.allItems)
      if (i.pos == 'pron') ...i.spellings.map(foldAnswer),
  }..remove('');

  late final Map<String, (int, int)> _pronounUse = () {
    final m = <String, (int, int)>{};
    for (final v in verbs) {
      for (final o in formOccurrences(v.id)) {
        final comps = _personComponents[o.person] ?? const <String>{};
        final present = o.sentence.tokens.any((t) => t.isWord && comps.contains(foldAnswer(t.t)));
        final (p, n) = m[o.person] ?? (0, 0);
        m[o.person] = (p + (present ? 1 : 0), n + 1);
      }
    }
    return m;
  }();

  /// Whether this course's sentences usually omit the subject pronoun of
  /// [person] (pro-drop, as in Italian `Mangiamo`), judged from the aligned
  /// verb forms: at least 3 samples and the pronoun present in under half.
  /// Dutch `ik`/`wij` sentences always have the pronoun, so this is false there.
  bool dropsPronoun(String person) {
    final (p, n) = _pronounUse[person] ?? (0, 0);
    return n >= 3 && p / n < 0.5;
  }

  late final Set<String> subjectPronounKeys = {
    for (final cs in _personComponents.values) ...cs,
  };

  bool isPronounToken(Token t) {
    final lex = t.lex;
    if (lex != null && course.item(lex)?.pos == 'pron') return true;
    return pronounKeys.contains(foldAnswer(t.t));
  }

  // ------------------------------------------------------------ articles

  late final Set<String> articleKeys = {for (final a in meta.articles) normalizeAnswer(a)}..remove('');

  /// Valid articles of a noun (the data may hold several separated by `|` or `/`).
  List<String> articlesOf(Item noun) {
    final a = noun.article;
    if (a == null || a.trim().isEmpty) return const [];
    return [for (final x in a.split(RegExp(r'[|/]'))) if (x.trim().isNotEmpty) x.trim()];
  }

  /// `il ragazzo`, `l'acqua`, `het huis`; the bare lemma when there is no article.
  String withArticle(Item item) {
    final arts = articlesOf(item);
    if (arts.isEmpty) return item.lemma;
    final a = arts.first;
    return normalizeApostrophes(a).endsWith("'") ? '$a${item.lemma}' : '$a ${item.lemma}';
  }

  // ------------------------------------------------------------ synonyms

  static final RegExp _parens = RegExp(r'\([^)]*\)');

  final Map<String, Set<String>> _glossKeys = {};

  /// Folded glosses of [item] in every language (with and without parenthesized parts).
  Set<String> glossKeys(Item item) => _glossKeys[item.id] ??= {
        for (final gs in item.tr.values)
          for (final g in gs) ...[foldAnswer(g), foldAnswer(g.replaceAll(_parens, ' '))],
      }..remove('');

  final Map<String, Set<String>> _glossKeysIn = {};

  /// Folded glosses of [item] in [lang] (with fallback, as displayed).
  Set<String> glossKeysIn(Item item, String lang) => _glossKeysIn['$lang\u0000${item.id}'] ??= {
        for (final g in item.glosses(lang)) ...[foldAnswer(g), foldAnswer(g.replaceAll(_parens, ' '))],
      }..remove('');

  /// Folded lemma + variants (+ article form).
  Set<String> spellingKeys(Item item) => {
        for (final s in item.spellings) foldAnswer(s),
        foldAnswer(withArticle(item)),
      }..remove('');

  /// Items that mean (partly) the same, or are spelled the same: never a
  /// wrong option for each other.
  bool overlaps(Item a, Item b) {
    if (a.id == b.id) return true;
    final ga = glossKeys(a);
    if (glossKeys(b).any(ga.contains)) return true;
    final sa = {for (final s in a.spellings) foldAnswer(s)};
    return b.spellings.any((s) => sa.contains(foldAnswer(s)));
  }

  final Map<String, Set<String>> _meaningKeys = {};

  /// Folded meanings (in [lang]) of [item] and of all its synonyms: every
  /// meaning a learner may reasonably give for [item].
  Set<String> meaningKeys(Item item, String lang) => _meaningKeys['$lang\u0000${item.id}'] ??= {
        ...glossKeysIn(item, lang),
        for (final s in synonymsOf(item)) ...glossKeysIn(s, lang),
      };

  /// Position of each item in [CourseData.allItems] (the order of every list
  /// derived from it).
  late final Map<String, int> _itemOrder = {
    for (final (i, item) in course.allItems.indexed) item.id: i,
  };

  /// Inverted indexes for [synonymsOf]: folded gloss (any language) and
  /// folded spelling -> items.
  late final Map<String, List<Item>> _byGlossKey = () {
    final m = <String, List<Item>>{};
    for (final i in course.allItems) {
      for (final k in glossKeys(i)) {
        (m[k] ??= []).add(i);
      }
    }
    return m;
  }();

  late final Map<String, List<Item>> _bySpellingKey = () {
    final m = <String, List<Item>>{};
    for (final i in course.allItems) {
      for (final k in {for (final s in i.spellings) foldAnswer(s)}) {
        (m[k] ??= []).add(i);
      }
    }
    return m;
  }();

  final Map<String, List<Item>> _synonyms = {};

  /// All items that [overlaps] with [item] (excluding itself), in
  /// [CourseData.allItems] order.
  List<Item> synonymsOf(Item item) => _synonyms[item.id] ??= () {
        final found = <String, Item>{};
        for (final k in glossKeys(item)) {
          for (final o in _byGlossKey[k] ?? const <Item>[]) {
            found[o.id] = o;
          }
        }
        for (final s in item.spellings) {
          for (final o in _bySpellingKey[foldAnswer(s)] ?? const <Item>[]) {
            found[o.id] = o;
          }
        }
        found.remove(item.id);
        return found.values.toList()..sort((a, b) => (_itemOrder[a.id] ?? 0).compareTo(_itemOrder[b.id] ?? 0));
      }();

  // ------------------------------------------------------------ pools

  /// Items of one part of speech, in [CourseData.allItems] order.
  late final Map<String, List<Item>> _itemsByPos = () {
    final m = <String, List<Item>>{};
    for (final i in course.allItems) {
      (m[i.pos] ??= []).add(i);
    }
    return m;
  }();

  /// Candidate distractor items for [item], in priority groups: same POS and
  /// a shared tag; same POS near in frequency; any other item of the same POS.
  /// Synonyms and [item] itself are excluded. Callers shuffle within groups.
  List<List<Item>> relatedItems(Item item, {String? pos}) {
    final p = pos ?? item.pos;
    final seen = <String>{item.id};
    final syn = {for (final s in synonymsOf(item)) s.id};
    bool ok(Item o) => o.pos == p && !syn.contains(o.id) && seen.add(o.id);
    final tagged = [
      for (final t in item.tags)
        for (final o in course.itemsByTag(t))
          if (ok(o)) o,
    ];
    final near = [for (final o in course.itemsNearFreq(p, item.freq, limit: 40)) if (ok(o)) o];
    final rest = [for (final o in _itemsByPos[p] ?? const <Item>[]) if (ok(o)) o];
    return [tagged, near, rest];
  }

  /// Verb items that have conjugation tables.
  late final List<Item> verbs = [
    for (final i in course.allItems)
      if (course.verbForms(i.id).isNotEmpty) i,
  ];

  /// Lemmas of the perfect auxiliaries named by the verbs (`avere`, `essere`;
  /// `hebben`, `zijn`).
  late final Set<String> auxiliaryLemmas = {
    for (final v in verbs)
      for (final a in (course.verb(v.id)?.auxiliary ?? '').split('|'))
        if (a.trim().isNotEmpty) a.trim(),
  };

  final Map<VerbForm, Set<String>> _acceptedKeys = Map.identity();

  /// Folded keys of every accepted spelling of a form.
  Set<String> acceptedKeys(VerbForm f) =>
      _acceptedKeys[f] ??= {for (final a in f.accepted) foldAnswer(a)}..remove('');

  final Map<String, List<VerbForm>> _finite = {};

  /// Finite forms (person != '_') of [verbId] in [tense], in person order.
  List<VerbForm> finiteForms(String verbId, String tense) => _finite['$tense\u0000$verbId'] ??= List.unmodifiable(
      [for (final f in course.verbFormsInTense(verbId, tense)) if (f.person != kNoPerson) f]);

  final Map<String, List<String>> _words = {};

  /// [splitWords], cached (verb forms are split over and over).
  List<String> wordsOf(String s) => _words[s] ??= List.unmodifiable(splitWords(s));

  // ------------------------------------------------------------ memo

  final Map<String, Object?> _memo = {};

  /// Memoizes a deterministic, course-derived value under [key] (templates
  /// cache their `canGenerate` answers here; the key must contain everything
  /// the value depends on).
  T memo<T>(String key, T Function() compute) {
    if (_memo.containsKey(key)) return _memo[key] as T;
    final v = compute();
    _memo[key] = v;
    return v;
  }

  // ------------------------------------------------------------ translations

  final Map<String, Map<String, List<Sentence>>> _byTranslation = {};

  /// Sentences whose translation in [lang] (with the usual fallback) equals
  /// [translation] after [normalizeAnswer].
  List<Sentence> sentencesWithTranslation(String lang, String translation) {
    final m = _byTranslation[lang] ??= () {
      final out = <String, List<Sentence>>{};
      for (final s in allSentences) {
        final t = s.translation(lang);
        if (t != null) (out[normalizeAnswer(t)] ??= []).add(s);
      }
      return out;
    }();
    return m[normalizeAnswer(translation)] ?? const [];
  }

  // ------------------------------------------------------------ occurrences

  final Map<String, List<FormOccurrence>> _formOcc = {};

  /// Every verb form of [verbId] found in a sentence, matched against the
  /// conjugation table. Tokens whose text does not match an accepted form of
  /// their aligned cell (e.g. Dutch inverted `werk jij` aligned to
  /// `jij: werkt`) are skipped, so templates never rely on them.
  List<FormOccurrence> formOccurrences(String verbId) => _formOcc[verbId] ??= _computeFormOcc(verbId);

  List<FormOccurrence> formOccurrencesIn(String verbId, String tense) =>
      [for (final o in formOccurrences(verbId)) if (o.tense == tense) o];

  bool _same(Token t, String w) => normalizeAnswer(t.t) == normalizeAnswer(w);

  List<FormOccurrence> _computeFormOcc(String verbId) {
    final forms = course.verbForms(verbId);
    if (forms.isEmpty) return const [];
    final out = <FormOccurrence>[];
    for (final s in course.sentencesFor(verbId)) {
      final aux = auxiliaryPositions(s);
      final byKey = <String, List<int>>{};
      for (var i = 0; i < s.tokens.length; i++) {
        final t = s.tokens[i];
        if (t.lex == verbId && t.form != null && t.isWord) (byKey[t.form!] ??= []).add(i);
      }
      for (final e in byKey.entries) {
        final cell = forms[e.key];
        if (cell == null) continue;
        final used = <int>{};
        for (final a in cell.accepted) {
          final w = splitWords(a);
          if (w.isEmpty) continue;
          final free = [for (final p in e.value) if (!used.contains(p)) p];
          if (w.length == 1) {
            for (final p in free) {
              // The auxiliary of another word's compound form (`ho` in `ho
              // mangiato`, `Zijn` in `Zijn jullie … geweest?`) is part of that
              // form, not an instance of its own present tense.
              if (aux.contains(p)) continue;
              if (_same(s.tokens[p], w[0])) {
                out.add(FormOccurrence(s, verbId, cell, a, [p]));
                used.add(p);
              }
            }
          } else if (free.length >= w.length) {
            var start = 0;
            while (start + w.length <= free.length) {
              final chunk = free.sublist(start, start + w.length);
              final assigned = _assign(s, chunk, w);
              if (assigned != null) {
                out.add(FormOccurrence(s, verbId, cell, a, assigned));
                used.addAll(chunk);
                start += w.length;
              } else {
                start++;
              }
            }
          } else {
            // Only part of a multi-word form is aligned (e.g. the participle):
            // find the remaining words nearby.
            for (final p in free) {
              final k = w.indexWhere((x) => _same(s.tokens[p], x));
              if (k < 0) continue;
              final pos = List<int?>.filled(w.length, null)..[k] = p;
              var ok = true;
              for (var j = 0; j < w.length && ok; j++) {
                if (j == k) continue;
                final best = _nearestWord(s, p, w[j], {...used, ...pos.nonNulls}, verbId);
                if (best == null) ok = false;
                pos[j] = best;
              }
              if (ok) {
                final positions = pos.cast<int>();
                out.add(FormOccurrence(s, verbId, cell, a, positions));
                used.addAll(positions);
              }
            }
          }
        }
      }
    }
    // A later word of a compound form right after a determiner is a noun or
    // an adjective, not a participle (`Hebben dieren een geweten?`: conscience).
    out.removeWhere((o) => o.positions.skip(1).any((p) => _afterDeterminer(o.sentence, p)));
    return out;
  }

  bool _afterDeterminer(Sentence s, int p) {
    if (p == 0) return false;
    final prev = s.tokens[p - 1];
    if (!prev.isWord) return false;
    final lex = prev.lex;
    return lex != null && course.item(lex)?.pos == 'det';
  }

  final Map<String, Set<int>> _auxPos = {};

  /// Token positions in [s] that are the other words of a compound form
  /// aligned on a single token: the pipeline aligns the participle of `ho
  /// mangiato` to `passato_prossimo.io` and the auxiliary `ho` separately to
  /// `avere`'s present. Such an auxiliary belongs to the compound form; it is
  /// never an occurrence of the auxiliary verb's own (present) facet.
  Set<int> auxiliaryPositions(Sentence s) => _auxPos[s.id] ??= () {
        final out = <int>{};
        final tokens = s.tokens;
        for (var j = 0; j < tokens.length; j++) {
          final t = tokens[j];
          final lex = t.lex;
          final key = t.form;
          if (!t.isWord || lex == null || key == null) continue;
          final cell = course.verbForms(lex)[key];
          if (cell == null) continue;
          for (final a in cell.accepted) {
            final w = splitWords(a);
            if (w.length < 2) continue;
            final k = w.indexWhere((x) => _same(t, x));
            if (k < 0) continue;
            // Only when this token is the form's only aligned word.
            if (tokens.where((x) => x.lex == lex && x.form == key).length > 1) break;
            // The first accepted spelling whose other words are all found
            // (`heeft gezien` / `is gezien`).
            final taken = <int>{j};
            var all = true;
            for (var m = 0; m < w.length && all; m++) {
              if (m == k) continue;
              final q = _nearestWord(s, j, w[m], taken, lex);
              if (q == null) {
                all = false;
              } else {
                taken.add(q);
              }
            }
            if (!all) continue;
            out.addAll(taken..remove(j));
            break;
          }
        }
        return out;
      }();

  /// The word token nearest to [p] (within 6 tokens) that reads [word], is not
  /// in [exclude], and is unaligned or aligned to a verb.
  int? _nearestWord(Sentence s, int p, String word, Set<int> exclude, String verbId) {
    int? best;
    for (var q = 0; q < s.tokens.length; q++) {
      final tq = s.tokens[q];
      if (q == p || !tq.isWord || exclude.contains(q)) continue;
      if ((q - p).abs() > 6 || !_same(tq, word)) continue;
      final lex = tq.lex;
      if (lex != null && lex != verbId && course.verbForms(lex).isEmpty) continue;
      if (best == null || (q - p).abs() < (best - p).abs()) best = q;
    }
    return best;
  }

  List<int>? _assign(Sentence s, List<int> chunk, List<String> words) {
    final left = List.of(chunk);
    final out = <int>[];
    for (final w in words) {
      final i = left.indexWhere((p) => _same(s.tokens[p], w));
      if (i < 0) return null;
      out.add(left.removeAt(i));
    }
    return out;
  }

  late final Map<String, (int, int)> _contiguity = () {
    final m = <String, (int, int)>{};
    for (final v in verbs) {
      for (final o in formOccurrences(v.id)) {
        if (o.wordCount < 2) continue;
        final (c, n) = m[o.tense] ?? (0, 0);
        m[o.tense] = (c + (o.contiguous ? 1 : 0), n + 1);
      }
    }
    return m;
  }();

  /// Whether multi-word forms of [tense] are (nearly) always written as one
  /// contiguous group in this course's sentences, so inserting one in place
  /// of a single-word form keeps a valid word order.
  bool contiguousTense(String tense) {
    final (c, n) = _contiguity[tense] ?? (0, 0);
    return n >= 2 && c / n >= 0.9;
  }

  final Map<String, List<ArticleOccurrence>> _artOcc = {};

  /// Occurrences of the noun [nounId] (as its lemma) directly after one of its
  /// valid articles, or as one elided token (`l'acqua`).
  List<ArticleOccurrence> articleOccurrences(String nounId) => _artOcc[nounId] ??= () {
        final noun = course.item(nounId);
        if (noun == null) return const <ArticleOccurrence>[];
        final arts = articlesOf(noun);
        if (arts.isEmpty) return const <ArticleOccurrence>[];
        final artKeys = {for (final a in arts) normalizeAnswer(a)};
        final lemmaKeys = {for (final s in noun.spellings) normalizeAnswer(s)};
        final out = <ArticleOccurrence>[];
        for (final s in course.sentencesFor(nounId)) {
          for (var i = 0; i < s.tokens.length; i++) {
            final t = s.tokens[i];
            if (t.lex != nounId || !t.isWord) continue;
            final key = normalizeAnswer(t.t);
            if (lemmaKeys.contains(key)) {
              if (i > 0 && s.tokens[i - 1].isWord && artKeys.contains(normalizeAnswer(s.tokens[i - 1].t))) {
                out.add(ArticleOccurrence(
                  sentence: s,
                  nounId: nounId,
                  articlePos: i - 1,
                  nounPos: i,
                  article: s.tokens[i - 1].t,
                  withinToken: false,
                ));
              }
              continue;
            }
            final text = normalizeApostrophes(t.t);
            for (final a in arts) {
              final na = normalizeApostrophes(a);
              if (!na.endsWith("'")) continue;
              if (text.length > na.length &&
                  text.substring(0, na.length).toLowerCase() == na.toLowerCase() &&
                  lemmaKeys.contains(normalizeAnswer(text.substring(na.length)))) {
                out.add(ArticleOccurrence(
                  sentence: s,
                  nounId: nounId,
                  articlePos: i,
                  nounPos: i,
                  article: t.t.substring(0, na.length),
                  withinToken: true,
                ));
                break;
              }
            }
          }
        }
        return out;
      }();

  final Map<String, List<WordOccurrence>> _wordOcc = {};

  /// Occurrences of a non-verb item written as its lemma/variant or its plural.
  List<WordOccurrence> wordOccurrences(String itemId) => _wordOcc[itemId] ??= () {
        final item = course.item(itemId);
        if (item == null) return const <WordOccurrence>[];
        final lemmaKeys = {for (final s in item.spellings) normalizeAnswer(s)};
        final plural = item.plural == null ? null : normalizeAnswer(item.plural!);
        final out = <WordOccurrence>[];
        for (final s in course.sentencesFor(itemId)) {
          for (var i = 0; i < s.tokens.length; i++) {
            final t = s.tokens[i];
            if (t.lex != itemId || !t.isWord) continue;
            final key = normalizeAnswer(t.t);
            if (lemmaKeys.contains(key)) {
              out.add(WordOccurrence(s, itemId, i, plural: false));
            } else if (plural != null && key == plural) {
              out.add(WordOccurrence(s, itemId, i, plural: true));
            }
          }
        }
        return out;
      }();

  /// Every sentence reachable from an item (CourseData has no sentence list).
  late final List<Sentence> allSentences = () {
    final seen = <String>{};
    return [
      for (final i in course.allItems)
        for (final s in course.sentencesFor(i.id))
          if (seen.add(s.id)) s,
    ];
  }();

  final Map<String, Map<String, List<FormOccurrence>>> _formOccBySentence = {};
  final Map<String, Map<String, List<ArticleOccurrence>>> _artOccBySentence = {};

  /// Verb form occurrences of any verb inside [s].
  List<FormOccurrence> formOccurrencesInSentence(Sentence s) {
    final verbsHere = <String>{
      for (final t in s.tokens)
        if (t.lex != null && t.form != null) t.lex!,
    };
    return [
      for (final v in verbsHere)
        ...?(_formOccBySentence[v] ??= _groupBySentence(formOccurrences(v), (o) => o.sentence.id))[s.id],
    ];
  }

  /// Article occurrences of any noun inside [s].
  List<ArticleOccurrence> articleOccurrencesInSentence(Sentence s) {
    final nouns = <String>{
      for (final t in s.tokens)
        if (t.lex != null && course.item(t.lex!)?.isNoun == true) t.lex!,
    };
    return [
      for (final n in nouns)
        ...?(_artOccBySentence[n] ??= _groupBySentence(articleOccurrences(n), (o) => o.sentence.id))[s.id],
    ];
  }

  static Map<String, List<T>> _groupBySentence<T>(List<T> list, String Function(T) id) {
    final m = <String, List<T>>{};
    for (final x in list) {
      (m[id(x)] ??= []).add(x);
    }
    return m;
  }

  /// Whether two sentences say the same thing as far as the alignment shows:
  /// the same aligned items (or synonyms) in the same forms. Such a sentence
  /// is never a wrong option for the other.
  bool equivalent(Sentence a, Sentence b) {
    if (a.id == b.id) return true;
    if (normalizeAnswer(a.text) == normalizeAnswer(b.text)) return true;
    List<(String, String?)> sig(Sentence s) => [
          for (final t in s.tokens)
            if (t.isWord && t.lex != null) (t.lex!, t.form),
        ];
    final sa = sig(a);
    final sb = sig(b);
    if (sa.length != sb.length) return false;
    final left = List.of(sb);
    for (final (lex, form) in sa) {
      final i = left.indexWhere((x) {
        if (x.$2 != form) return false;
        if (x.$1 == lex) return true;
        final ia = course.item(lex);
        final ib = course.item(x.$1);
        return ia != null && ib != null && overlaps(ia, ib);
      });
      if (i < 0) return false;
      left.removeAt(i);
    }
    return true;
  }

  /// Word tokens of a sentence (no punctuation).
  static List<Token> words(Sentence s) => [for (final t in s.tokens) if (t.isWord) t];

  /// Spellings of unaligned capitalized words seen inside a sentence (not as
  /// its first word) anywhere in the course: names (`Tom`, `Napels`). A
  /// sentence-initial unaligned word counts as a name only when it is one
  /// of these (`Tom è qui` yes, `Comprai il pane` no).
  late final Set<String> properNames = () {
    final out = <String>{};
    for (final s in allSentences) {
      var first = true;
      for (final t in s.tokens) {
        if (!t.isWord) continue;
        if (!first && t.lex == null && t.t.isNotEmpty && t.t != lowerFirst(t.t)) out.add(t.t);
        first = false;
      }
    }
    return out;
  }();

  /// [CourseMeta.timeAdverbs] with folded keys.
  late final Map<String, Set<String>> _timeAdverbs = {
    for (final e in meta.timeAdverbs.entries)
      if (foldAnswer(e.key).isNotEmpty) foldAnswer(e.key): e.value.toSet(),
  };

  final Map<String, List<Set<String>>> _adverbsIn = {};

  /// For each time adverb in [s] ([CourseMeta.timeAdverbs], matched as whole
  /// words after folding), the tenses it fits.
  List<Set<String>> timeAdverbTenses(Sentence s) {
    if (_timeAdverbs.isEmpty) return const [];
    return _adverbsIn[s.id] ??= () {
      final text = ' ${foldAnswer(s.text)} ';
      return [
        for (final e in _timeAdverbs.entries)
          if (text.contains(' ${e.key} ')) e.value,
      ];
    }();
  }

  static final RegExp _digit = RegExp(r'^[0-9]');

  /// Whether an unaligned word token is a name or a number (known to every
  /// learner): a capitalized word inside the sentence, a sentence-initial
  /// word in [properNames], or a word starting with a digit.
  bool isNameOrNumber(Token t, {required bool first}) {
    if (_digit.hasMatch(t.t)) return true;
    if (t.t.isEmpty || t.t == lowerFirst(t.t)) return false;
    return !first || properNames.contains(t.t);
  }

  /// Display text of a sentence's word tokens for tiles: the first word is
  /// lower-cased unless it looks like a proper noun (unaligned, or aligned to
  /// an item whose lemma is capitalized).
  ///
  /// The same goes for a word that starts a later sentence of the text
  /// (`"Was Bill in Japan?" "Ja, inderdaad."`): capitals would give the
  /// sentence boundaries away.
  List<String> tileWords(Sentence s) {
    final out = <String>[];
    var start = true;
    for (final t in s.tokens) {
      if (!t.isWord) {
        if (_sentenceEnd.hasMatch(t.t)) start = true;
        continue;
      }
      out.add(start && _lowerOk(t) ? lowerFirst(t.t) : t.t);
      start = false;
    }
    return out;
  }

  static final RegExp _sentenceEnd = RegExp(r'[.!?…]');

  bool _lowerOk(Token t) {
    final lex = t.lex;
    final item = lex == null ? null : course.item(lex);
    return (item != null && item.lemma.isNotEmpty && item.lemma == lowerFirst(item.lemma)) ||
        articleKeys.contains(normalizeAnswer(t.t)) ||
        pronounKeys.contains(foldAnswer(t.t));
  }
}

/// Renders (pre, text) pairs.
String renderPairs(Iterable<(String, String)> pairs) {
  final b = StringBuffer();
  for (final (pre, t) in pairs) {
    b
      ..write(pre)
      ..write(t);
  }
  return b.toString();
}

/// Renders tokens from list position [from] (inclusive) to [to] (exclusive).
String renderRange(Sentence s, int from, int to, {bool includeFirstPre = true}) {
  final b = StringBuffer();
  for (var i = from; i < to && i < s.tokens.length; i++) {
    if (i != from || includeFirstPre) b.write(s.tokens[i].pre);
    b.write(s.tokens[i].t);
  }
  return b.toString();
}
