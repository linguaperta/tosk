/// Reading any text ("Practice → Read"): split a pasted text into paragraphs,
/// sentences and words and look every word up in the course, by its written
/// form through the pack's lexicon, verb tables and inflection tables
/// (`andò` → `andare`, passato remoto, lui/lei), with elisions (`dell'acqua`,
/// French `l'eau`), multi-word forms and phrases (`ho mangiato`, `per
/// favore`), any script the course uses, and how much of it the learner
/// knows. Pure Dart. See docs/engine.md, "Reading".
library;

import '../core/core.dart';
import 'text/normalize.dart';

/// One reading of a written word: the course item, and the cell of its table
/// (`'{tense}.{person}'` for a verb form, `'infl:{table}.{cell}'` for an
/// inflected word; null for the lemma).
class WordAnalysis {
  const WordAnalysis(this.itemId, [this.form]);
  final String itemId;
  final String? form;

  @override
  bool operator ==(Object other) => other is WordAnalysis && other.itemId == itemId && other.form == form;

  @override
  int get hashCode => Object.hash(itemId, form);

  @override
  String toString() => form == null ? itemId : '$itemId ($form)';
}

/// The lookup key of a written form: lower case, NFC, straight apostrophes.
String readingKey(String s) => normalizeApostrophes(nfc(s.trim())).toLowerCase();

/// A word as the reader splits text: letters, marks and digits, with inner
/// apostrophes and hyphens (`dell'acqua`, `foto's`, `porta-finestra`) and a
/// final apostrophe (`po'`, `dell'`), any script.
final RegExp kReadingWord = RegExp(r"[\p{L}\p{M}\p{N}]+(?:['’ʼ\-][\p{L}\p{M}\p{N}]+)*['’ʼ]?", unicode: true);

const _vowels = ['a', 'e', 'i', 'o', 'u'];

/// Course words by written form, every reading of each (cached per course).
class ReadingLookup {
  ReadingLookup._(CourseData course) {
    final items = course.allItems.toList()..sort((a, b) => (a.freq ?? 1 << 30).compareTo(b.freq ?? 1 << 30));
    void put(String form, String itemId, String? key) {
      final parts = [for (final m in kReadingWord.allMatches(readingKey(form))) m.group(0)!];
      if (parts.isEmpty) return;
      final a = WordAnalysis(itemId, key);
      if (parts.length == 1) {
        final l = _forms.putIfAbsent(parts.single, () => []);
        if (!l.contains(a)) l.add(a);
      } else {
        final k = parts.join(' ');
        final l = _phrases.putIfAbsent(k, () => []);
        if (!l.contains(a)) l.add(a);
        if (parts.length > maxPhraseWords) maxPhraseWords = parts.length;
      }
    }

    // Lemmas and spellings first (a lemma beats an inflected form), the more
    // frequent item first.
    for (final i in items) {
      for (final s in i.spellings) {
        put(s, i.id, null);
      }
    }
    for (final i in items) {
      if (i.plural case final p?) put(p, i.id, null);
      for (final f in course.verbForms(i.id).values) {
        for (final a in f.accepted) {
          put(a, i.id, f.key);
        }
      }
      for (final f in course.inflections(i.id).values) {
        final key = '$kInflFormPrefix${f.table}.${f.cell}';
        put(f.form, i.id, key);
        for (final a in f.alts) {
          put(a, i.id, key);
        }
      }
    }
    // One reading per item where the word is the item's own lemma (`mercato`
    // is no "singular of mercato", `zijn` no "infinitive of zijn"); else its
    // table cells, not also the plain plural.
    for (final e in _forms.entries) {
      final list = e.value;
      final out = <WordAnalysis>[];
      final seen = <String>{};
      for (final a in list) {
        if (!seen.add(a.itemId)) continue;
        final mine = [for (final x in list) if (x.itemId == a.itemId) x];
        final item = course.item(a.itemId);
        final isLemma = item != null && item.spellings.any((s) => readingKey(s) == e.key);
        if (isLemma || mine.length == 1) {
          out.add(isLemma ? WordAnalysis(a.itemId) : a);
        } else {
          out.addAll(mine.where((x) => x.form != null));
        }
      }
      _forms[e.key] = out;
    }
  }

  static final Expando<ReadingLookup> _cache = Expando();

  static ReadingLookup of(CourseData course) => _cache[course] ??= ReadingLookup._(course);

  final Map<String, List<WordAnalysis>> _forms = {};
  final Map<String, List<WordAnalysis>> _phrases = {};

  /// The longest phrase or multi-word form, in words (at most 6 are tried).
  int maxPhraseWords = 1;

  /// Every reading of the single word [word] (empty when the course doesn't
  /// have it). An elided word (`dell'`, `l'`, `qu'`: a short word ending in
  /// a consonant and an apostrophe) that isn't listed as such is read as its
  /// full forms with a vowel (`della`, `dello`, `que`).
  List<WordAnalysis> lookup(String word) {
    final k = readingKey(word);
    final hit = _forms[k];
    if (hit != null) return hit;
    if (k.endsWith("'") && k.length > 1 && k.length <= 6 && _elides(k.substring(0, k.length - 1))) {
      final base = k.substring(0, k.length - 1);
      final out = <WordAnalysis>[];
      for (final v in _vowels) {
        for (final a in _forms['$base$v'] ?? const <WordAnalysis>[]) {
          if (!out.any((x) => x.itemId == a.itemId)) out.add(a);
        }
      }
      if (out.isNotEmpty) return out.take(3).toList();
    }
    return const [];
  }

  /// Whether [base] (a word before an apostrophe) can be a word with its
  /// final vowel elided: it ends in a consonant (`l`, `dell`, `d`, `c`) or
  /// in `qu` / `gu` (French `qu'`, `lorsqu'`); `po'` (Italian *poco*) is no
  /// such case.
  static bool _elides(String base) {
    if (base.isEmpty) return false;
    final last = base[base.length - 1];
    if (!_vowels.contains(last)) return true;
    return last == 'u' && base.length >= 2 && 'qg'.contains(base[base.length - 2]);
  }

  /// The readings of the words [words] (lower case, as split) as one phrase
  /// or multi-word form, or null.
  List<WordAnalysis>? phrase(List<String> words) => _phrases[words.map(readingKey).join(' ')];
}

/// One token of a paragraph: a word or the punctuation between words.
/// [start]..[end] are offsets in [ReadingParagraph.text].
class ReadingToken {
  const ReadingToken({
    required this.start,
    required this.end,
    required this.text,
    this.isWord = true,
    this.isNumber = false,
    this.isName = false,
    this.analyses = const [],
    this.phrase,
  });

  final int start;
  final int end;
  final String text;
  final bool isWord;

  /// Digits only: neither looked up nor counted.
  final bool isNumber;

  /// Not in the course and capitalized inside a sentence: probably a name
  /// (not counted in the share of known words).
  final bool isName;

  /// The word's readings in the course, the likeliest first (empty: not in the course).
  final List<WordAnalysis> analyses;

  /// The phrase ([ReadingParagraph.phrases]) this word belongs to.
  final int? phrase;

  bool get inCourse => analyses.isNotEmpty;

  /// Counted in the share of known words.
  bool get counts => isWord && !isNumber && !isName;
}

/// Words read together: a phrase of the lexicon or a multi-word form
/// (`ho mangiato` → `mangiare`, passato prossimo, io).
class ReadingPhrase {
  const ReadingPhrase({required this.from, required this.to, required this.text, required this.analyses});

  /// First and last token index.
  final int from;
  final int to;

  /// The words as written (`ho mangiato`).
  final String text;
  final List<WordAnalysis> analyses;
}

/// One line of the text (long lines are cut into pieces at sentence ends).
class ReadingParagraph {
  ReadingParagraph({required this.text, required this.tokens, required this.phrases, required this.sentences, this.continued = false});

  final String text;
  final List<ReadingToken> tokens;
  final List<ReadingPhrase> phrases;

  /// Sentence ranges (start, end) in [text], in order; together they cover
  /// every word.
  final List<(int, int)> sentences;

  /// The piece of a long line that continues the previous piece.
  final bool continued;

  bool get isBlank => tokens.every((t) => !t.isWord);

  /// The index of the token at [offset] (a text position), or null when it
  /// falls on spacing.
  int? tokenAt(int offset) {
    var lo = 0, hi = tokens.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final t = tokens[mid];
      if (offset < t.start) {
        hi = mid - 1;
      } else if (offset >= t.end) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return null;
  }

  /// The sentence (index in [sentences]) containing [offset].
  int sentenceAt(int offset) {
    for (var i = 0; i < sentences.length; i++) {
      if (offset < sentences[i].$2) return i;
    }
    return sentences.isEmpty ? 0 : sentences.length - 1;
  }

  /// The text of sentence [i].
  String sentenceText(int i) => text.substring(sentences[i].$1, sentences[i].$2).trim();
}

/// A sentence of the text, for reading aloud: paragraph and sentence index.
typedef ReadingSentenceRef = ({int paragraph, int sentence});

/// How much of a text the learner knows: words counted (not numbers or
/// names), known words, and the distinct words.
class ReadingCoverage {
  const ReadingCoverage({required this.words, required this.known, required this.distinct, required this.distinctKnown});
  final int words;
  final int known;
  final int distinct;
  final int distinctKnown;

  /// Known words in percent, rounded down (0 for a text without words).
  int get percent => words == 0 ? 0 : (known * 100) ~/ words;
}

/// A text split and looked up for reading.
class ReadingText {
  ReadingText._(this.paragraphs);

  final List<ReadingParagraph> paragraphs;

  /// Long lines are cut into pieces of about this many characters (at
  /// sentence ends), so the reader lays out only what is on screen.
  static const pieceLength = 1200;

  /// Splits and looks up [text] in [course].
  factory ReadingText.analyze(String text, CourseData course) {
    final lookup = ReadingLookup.of(course);
    final out = <ReadingParagraph>[];
    for (final line in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      final pieces = _cut(line);
      for (var i = 0; i < pieces.length; i++) {
        out.add(_paragraph(pieces[i], lookup, continued: i > 0));
      }
    }
    // No blank lines at the start or the end.
    while (out.isNotEmpty && out.first.isBlank) {
      out.removeAt(0);
    }
    while (out.isNotEmpty && out.last.isBlank) {
      out.removeLast();
    }
    return ReadingText._(out);
  }

  /// Every word token, in order.
  Iterable<ReadingToken> get words sync* {
    for (final p in paragraphs) {
      for (final t in p.tokens) {
        if (t.isWord) yield t;
      }
    }
  }

  int get wordCount => words.where((t) => t.counts).length;

  /// Every sentence in reading order.
  List<ReadingSentenceRef> get sentences => [
    for (var p = 0; p < paragraphs.length; p++)
      for (var s = 0; s < paragraphs[p].sentences.length; s++) (paragraph: p, sentence: s),
  ];

  String sentenceText(ReadingSentenceRef r) => paragraphs[r.paragraph].sentenceText(r.sentence);

  /// The share of known words: [known] decides per counted word token.
  ReadingCoverage coverage(bool Function(ReadingToken token) known) {
    var words = 0, k = 0;
    final distinct = <String>{};
    final distinctKnown = <String>{};
    for (final t in this.words) {
      if (!t.counts) continue;
      words++;
      final key = readingKey(t.text);
      distinct.add(key);
      if (known(t)) {
        k++;
        distinctKnown.add(key);
      }
    }
    return ReadingCoverage(words: words, known: k, distinct: distinct.length, distinctKnown: distinctKnown.length);
  }

  /// [line] in pieces of about [pieceLength] characters, cut after a sentence end.
  static List<String> _cut(String line) {
    if (line.length <= pieceLength * 1.5) return [line];
    final out = <String>[];
    var start = 0;
    while (line.length - start > pieceLength * 1.5) {
      var cut = -1;
      for (final m in _sentenceEnd.allMatches(line, start + pieceLength ~/ 2)) {
        cut = m.end;
        if (cut - start >= pieceLength) break;
      }
      if (cut <= start || cut - start > pieceLength * 2) {
        // No sentence end: cut at a space.
        cut = line.lastIndexOf(' ', start + pieceLength);
        if (cut <= start) cut = start + pieceLength;
      }
      out.add(line.substring(start, cut));
      start = cut;
    }
    out.add(line.substring(start));
    return out;
  }

  static final RegExp _sentenceEnd = RegExp(r'''[.!?…]+["'”’»)\]]*(?=\s|$)''');

  static ReadingParagraph _paragraph(String text, ReadingLookup lookup, {required bool continued}) {
    final tokens = <ReadingToken>[];
    var pos = 0;
    void punct(int from, int to) {
      // Punctuation between words (spacing is left out: it is never tapped).
      final between = text.substring(from, to);
      for (final m in RegExp(r'\S+').allMatches(between)) {
        tokens.add(ReadingToken(start: from + m.start, end: from + m.end, text: m.group(0)!, isWord: false));
      }
    }

    void word(int start, String w) {
      final digits = RegExp(r'^\p{N}+$', unicode: true).hasMatch(w);
      tokens.add(ReadingToken(
        start: start,
        end: start + w.length,
        text: w,
        isNumber: digits,
        analyses: digits ? const [] : lookup.lookup(w),
      ));
    }

    for (final m in kReadingWord.allMatches(text)) {
      punct(pos, m.start);
      final raw = m.group(0)!;
      final start = m.start;
      pos = m.end;
      if (lookup.lookup(raw).isNotEmpty) {
        word(start, raw);
        continue;
      }
      // A closing quote is no elision: `'ciao'`.
      final trailing = raw.length > 1 && "'’ʼ".contains(raw[raw.length - 1]);
      if (trailing && lookup.lookup(raw.substring(0, raw.length - 1)).isNotEmpty) {
        word(start, raw.substring(0, raw.length - 1));
        punct(start + raw.length - 1, start + raw.length);
        continue;
      }
      // Split after inner apostrophes (`dell'` + `acqua`) and at hyphens.
      final parts = RegExp(r"[^'’ʼ\-]+['’ʼ]?|-").allMatches(raw).toList();
      if (parts.length <= 1) {
        if (trailing && !_looksElided(raw)) {
          word(start, raw.substring(0, raw.length - 1));
          punct(start + raw.length - 1, start + raw.length);
        } else {
          word(start, raw);
        }
        continue;
      }
      for (final p in parts) {
        final t = p.group(0)!;
        if (t == '-') {
          tokens.add(ReadingToken(start: start + p.start, end: start + p.end, text: t, isWord: false));
        } else {
          word(start + p.start, t);
        }
      }
    }
    punct(pos, text.length);

    // Sentences: up to and including each sentence end.
    final sentences = <(int, int)>[];
    var s = 0;
    for (final m in _sentenceEnd.allMatches(text)) {
      if (text.substring(s, m.end).trim().isEmpty) continue;
      sentences.add((s, m.end));
      s = m.end;
    }
    if (text.substring(s).trim().isNotEmpty) sentences.add((s, text.length));

    // Names: capitalized words the course doesn't know, not at a sentence start.
    final starts = <int>{};
    for (final (from, _) in sentences) {
      final first = tokens.indexWhere((t) => t.isWord && t.start >= from);
      if (first >= 0) starts.add(first);
    }
    if (!continued) {
      final first = tokens.indexWhere((t) => t.isWord);
      if (first >= 0) starts.add(first);
    }
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (!t.isWord || t.inCourse || t.isNumber || starts.contains(i)) continue;
      if (t.text[0] != t.text[0].toLowerCase()) {
        tokens[i] = ReadingToken(start: t.start, end: t.end, text: t.text, isName: true);
      }
    }

    // Phrases and multi-word forms: the longest match wins, left to right.
    final phrases = <ReadingPhrase>[];
    final maxN = lookup.maxPhraseWords.clamp(1, 6);
    if (maxN > 1) {
      var i = 0;
      while (i < tokens.length) {
        if (!tokens[i].isWord) {
          i++;
          continue;
        }
        var matched = 0;
        for (var n = maxN; n >= 2 && matched == 0; n--) {
          final idx = <int>[];
          var j = i;
          while (idx.length < n && j < tokens.length && tokens[j].isWord) {
            // Words of one phrase are separated by spacing only.
            if (idx.isNotEmpty && text.substring(tokens[idx.last].end, tokens[j].start).trim().isNotEmpty) break;
            idx.add(j);
            j++;
          }
          if (idx.length < n) continue;
          final hit = lookup.phrase([for (final k in idx) tokens[k].text]);
          if (hit == null) continue;
          final p = phrases.length;
          phrases.add(ReadingPhrase(
            from: idx.first,
            to: idx.last,
            text: text.substring(tokens[idx.first].start, tokens[idx.last].end),
            analyses: hit,
          ));
          for (final k in idx) {
            final t = tokens[k];
            tokens[k] = ReadingToken(start: t.start, end: t.end, text: t.text, analyses: t.analyses, phrase: p);
          }
          matched = n;
        }
        i += matched == 0 ? 1 : matched;
      }
    }
    return ReadingParagraph(text: text, tokens: tokens, phrases: phrases, sentences: sentences, continued: continued);
  }

  /// Ends like an elided article or preposition (`l'`, `dell'`, `qu'`): a
  /// short word, kept with its apostrophe.
  static bool _looksElided(String w) => w.length <= 6;
}
