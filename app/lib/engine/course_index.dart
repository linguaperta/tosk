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

  late final Map<String, Set<String>> _personComponents = {
    for (final p in meta.persons)
      p: {for (final c in p.split('/')) if (foldAnswer(c).isNotEmpty) foldAnswer(c)},
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

  /// Folded glosses of [item] in [lang] (with fallback, as displayed).
  Set<String> glossKeysIn(Item item, String lang) => {
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

  /// Folded meanings (in [lang]) of [item] and of all its synonyms: every
  /// meaning a learner may reasonably give for [item].
  Set<String> meaningKeys(Item item, String lang) => {
        ...glossKeysIn(item, lang),
        for (final s in synonymsOf(item)) ...glossKeysIn(s, lang),
      };

  final Map<String, List<Item>> _synonyms = {};

  /// All items that [overlaps] with [item] (excluding itself).
  List<Item> synonymsOf(Item item) => _synonyms[item.id] ??= [
        for (final o in course.allItems)
          if (o.id != item.id && overlaps(item, o)) o,
      ];

  // ------------------------------------------------------------ pools

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
    final rest = [for (final o in course.allItems) if (ok(o)) o];
    return [tagged, near, rest];
  }

  /// Verb items that have conjugation tables.
  late final List<Item> verbs = [
    for (final i in course.allItems)
      if (course.verbForms(i.id).isNotEmpty) i,
  ];

  /// Folded keys of every accepted spelling of a form.
  Set<String> acceptedKeys(VerbForm f) => {for (final a in f.accepted) foldAnswer(a)}..remove('');

  /// Finite forms (person != '_') of [verbId] in [tense], in person order.
  List<VerbForm> finiteForms(String verbId, String tense) =>
      [for (final f in course.verbFormsInTense(verbId, tense)) if (f.person != kNoPerson) f];

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
                int? best;
                for (var q = 0; q < s.tokens.length; q++) {
                  final tq = s.tokens[q];
                  if (q == p || !tq.isWord || used.contains(q) || pos.contains(q)) continue;
                  if ((q - p).abs() > 6 || !_same(tq, w[j])) continue;
                  final lex = tq.lex;
                  if (lex != null && lex != verbId && course.verbForms(lex).isEmpty) continue;
                  if (best == null || (q - p).abs() < (best - p).abs()) best = q;
                }
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
    return out;
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

  /// Verb form occurrences of any verb inside [s].
  List<FormOccurrence> formOccurrencesInSentence(Sentence s) {
    final verbsHere = <String>{
      for (final t in s.tokens)
        if (t.lex != null && t.form != null) t.lex!,
    };
    return [
      for (final v in verbsHere)
        for (final o in formOccurrences(v))
          if (o.sentence.id == s.id) o,
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
        for (final o in articleOccurrences(n))
          if (o.sentence.id == s.id) o,
    ];
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

  /// Display text of a sentence's word tokens for tiles: the first word is
  /// lower-cased unless it looks like a proper noun (unaligned, or aligned to
  /// an item whose lemma is capitalized).
  List<String> tileWords(Sentence s) {
    final ws = words(s);
    final out = [for (final t in ws) t.t];
    if (out.isEmpty) return out;
    final first = ws.first;
    final lex = first.lex;
    final item = lex == null ? null : course.item(lex);
    final lowerOk = (item != null && item.lemma.isNotEmpty && item.lemma == lowerFirst(item.lemma)) ||
        articleKeys.contains(normalizeAnswer(first.t)) ||
        pronounKeys.contains(foldAnswer(first.t));
    if (lowerOk) out[0] = lowerFirst(out[0]);
    return out;
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
