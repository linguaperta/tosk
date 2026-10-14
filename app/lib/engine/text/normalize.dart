/// Answer normalization: Unicode NFC, case, apostrophes, punctuation,
/// whitespace and (for lenient checking) diacritic folding.
///
/// Pure Dart, no dependencies. NFC is implemented for precomposed Latin
/// letters (see `unicode_table.dart`), which covers every script the engine
/// compares today (Latin with diacritics, including Sarnami's ṯ/ṟ/ã).
library;

import '../../core/interfaces/session.dart' show AccentStrictness;
import 'unicode_table.dart';

final Map<int, (int, int)> _decomp = () {
  final m = <int, (int, int)>{};
  for (var i = 0; i + 2 < kLatinDecompositions.length; i += 3) {
    m[kLatinDecompositions[i]] = (kLatinDecompositions[i + 1], kLatinDecompositions[i + 2]);
  }
  return m;
}();

final Map<int, int> _comp = () {
  final m = <int, int>{};
  _decomp.forEach((composed, pair) => m[_pairKey(pair.$1, pair.$2)] = composed);
  return m;
}();

int _pairKey(int base, int mark) => base * 0x10000 + mark;

bool _isMark(int cp) => cp >= 0x0300 && cp <= 0x036F;

/// Approximate canonical combining class for U+0300..U+036F.
int _ccc(int cp) {
  if (!_isMark(cp)) return 0;
  if (cp == 0x0327 || cp == 0x0328) return 202;
  if (cp == 0x031B) return 216;
  if ((cp >= 0x0316 && cp <= 0x0319) ||
      (cp >= 0x031C && cp <= 0x0326) ||
      (cp >= 0x0329 && cp <= 0x0333) ||
      (cp >= 0x0339 && cp <= 0x033C) ||
      (cp >= 0x0347 && cp <= 0x0349) ||
      cp == 0x034D ||
      cp == 0x034E ||
      (cp >= 0x0353 && cp <= 0x0356) ||
      cp == 0x0359 ||
      cp == 0x035A) {
    return 220;
  }
  return 230;
}

void _decomposeInto(int cp, List<int> out) {
  final d = _decomp[cp];
  if (d == null) {
    out.add(cp);
    return;
  }
  _decomposeInto(d.$1, out);
  out.add(d.$2);
}

/// Full canonical decomposition with canonical ordering of combining marks.
List<int> _nfd(String s) {
  final out = <int>[];
  for (final cp in s.runes) {
    _decomposeInto(cp, out);
  }
  // Canonical ordering: stable-sort each run of marks by combining class.
  var i = 0;
  while (i < out.length) {
    if (!_isMark(out[i])) {
      i++;
      continue;
    }
    var j = i;
    while (j < out.length && _isMark(out[j])) {
      j++;
    }
    if (j - i > 1) {
      final run = out.sublist(i, j);
      final indexed = [for (var k = 0; k < run.length; k++) (k, run[k])];
      indexed.sort((a, b) {
        final c = _ccc(a.$2).compareTo(_ccc(b.$2));
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
      for (var k = 0; k < indexed.length; k++) {
        out[i + k] = indexed[k].$2;
      }
    }
    i = j;
  }
  return out;
}

/// Unicode NFC for Latin text (other characters pass through unchanged).
String nfc(String s) {
  if (s.isEmpty) return s;
  final d = _nfd(s);
  final out = <int>[];
  var starter = -1; // index in out of the last starter
  var lastCcc = 0;
  for (final cp in d) {
    final ccc = _ccc(cp);
    if (starter >= 0 && ccc != 0 && (lastCcc < ccc || out.length - 1 == starter)) {
      final composed = _comp[_pairKey(out[starter], cp)];
      if (composed != null) {
        out[starter] = composed;
        continue;
      }
    }
    if (ccc == 0) {
      starter = out.length;
      lastCcc = 0;
    } else {
      lastCcc = ccc;
    }
    out.add(cp);
  }
  return String.fromCharCodes(out);
}

const Map<int, String> _extraFold = {
  0x00F8: 'o', // ø
  0x00D8: 'O', // Ø
  0x0142: 'l', // ł
  0x0141: 'L', // Ł
  0x0111: 'd', // đ
  0x0110: 'D', // Đ
  0x0131: 'i', // dotless i
};

/// Removes diacritics: 'città' -> 'citta', 'ṯ' -> 't'.
String foldDiacritics(String s) {
  final b = StringBuffer();
  for (final cp in _nfd(s)) {
    if (_isMark(cp)) continue;
    final extra = _extraFold[cp];
    if (extra != null) {
      b.write(extra);
    } else {
      b.writeCharCode(cp);
    }
  }
  return b.toString();
}

final RegExp _apostrophes = RegExp('[’‘ʼ´`′ʹ＇]');
final RegExp _punctOrSymbol = RegExp(r'[\p{P}\p{S}]', unicode: true);
final RegExp _letter = RegExp(r'\p{L}', unicode: true);
final RegExp _spaces = RegExp(r'\s+', unicode: true);
final RegExp _elisionSpace = RegExp(r"(\p{L})' +", unicode: true);

/// Maps typographic apostrophes and look-alikes to ASCII `'`.
String normalizeApostrophes(String s) => s.replaceAll(_apostrophes, "'");

/// Strict comparison key: NFC, lower case, ASCII apostrophes, punctuation
/// removed (apostrophes and word-internal hyphens kept), whitespace collapsed,
/// and the space after an elided word removed (`l' acqua` == `l'acqua`).
/// Diacritics are kept.
String normalizeAnswer(String s) => _memo(_normCache, s, _normalizeAnswer);

/// Lenient comparison key: [normalizeAnswer] with diacritics folded.
String foldAnswer(String s) => _memo(_foldCache, s, (x) => foldDiacritics(normalizeAnswer(x)));

// Both keys are pure functions of the input, and the engine computes them for
// the same words (verb forms, tokens, glosses) over and over, so they are
// memoized in bounded caches (cleared when full).
const int _kMemoMax = 50000;
final Map<String, String> _normCache = {};
final Map<String, String> _foldCache = {};

String _memo(Map<String, String> cache, String s, String Function(String) f) {
  final hit = cache[s];
  if (hit != null) return hit;
  if (cache.length >= _kMemoMax) cache.clear();
  return cache[s] = f(s);
}

String _normalizeAnswer(String s) {
  final t = normalizeApostrophes(nfc(s)).toLowerCase();
  final chars = t.runes.toList();
  final b = StringBuffer();
  for (var i = 0; i < chars.length; i++) {
    final cp = chars[i];
    final ch = String.fromCharCode(cp);
    if (ch == "'") {
      b.write(ch);
      continue;
    }
    if (ch == '-') {
      final prev = i > 0 ? String.fromCharCode(chars[i - 1]) : '';
      final next = i + 1 < chars.length ? String.fromCharCode(chars[i + 1]) : '';
      b.write(_letter.hasMatch(prev) && _letter.hasMatch(next) ? '-' : ' ');
      continue;
    }
    b.write(_punctOrSymbol.hasMatch(ch) ? ' ' : ch);
  }
  return b
      .toString()
      .replaceAll(_spaces, ' ')
      .trim()
      .replaceAllMapped(_elisionSpace, (m) => "${m[1]}'");
}

/// Comparison key for the given strictness.
String answerKey(String s, AccentStrictness strictness) =>
    strictness == AccentStrictness.strict ? normalizeAnswer(s) : foldAnswer(s);

/// Outcome of checking a free-text answer against the accepted forms.
class AnswerMatch {
  const AnswerMatch({required this.correct, this.accentSlip = false, this.matched});
  static const AnswerMatch wrong = AnswerMatch(correct: false);

  final bool correct;

  /// Accepted only because diacritics were folded (lenient mode): "watch the accent".
  final bool accentSlip;

  /// The accepted form that matched.
  final String? matched;
}

/// Checks [given] (plus optional recognizer [candidates], best first) against
/// every string in [accepted].
///
/// * strict: exact diacritics (case, punctuation, whitespace, apostrophes and
///   NFC are still normalized).
/// * lenient: an exact match wins; otherwise a match with diacritics folded is
///   accepted with [AnswerMatch.accentSlip] set.
AnswerMatch matchAnswer(
  String given,
  Iterable<String> accepted,
  AccentStrictness strictness, {
  List<String> candidates = const [],
}) {
  final inputs = [given, ...candidates].map(normalizeAnswer).where((s) => s.isNotEmpty).toList();
  if (inputs.isEmpty) return AnswerMatch.wrong;
  final acc = accepted.toList();
  for (final a in acc) {
    final key = normalizeAnswer(a);
    if (key.isEmpty) continue;
    if (inputs.contains(key)) return AnswerMatch(correct: true, matched: a);
  }
  if (strictness == AccentStrictness.lenient) {
    final folded = inputs.map(foldDiacritics).toSet();
    for (final a in acc) {
      final key = foldAnswer(a);
      if (key.isEmpty) continue;
      if (folded.contains(key)) return AnswerMatch(correct: true, accentSlip: true, matched: a);
    }
  }
  return AnswerMatch.wrong;
}

/// Splits a (possibly multi-word) form into words.
List<String> splitWords(String s) =>
    s.trim().split(_spaces).where((w) => w.isNotEmpty).toList();

/// Capitalizes [s] like [model]: if [model] starts with an upper-case letter
/// and [s] with a lower-case one, the first letter of [s] is upper-cased.
String matchCase(String s, String model) {
  if (s.isEmpty || model.isEmpty) return s;
  final m = String.fromCharCode(model.runes.first);
  final f = String.fromCharCode(s.runes.first);
  if (m != m.toLowerCase() && m == m.toUpperCase() && f != f.toUpperCase()) {
    return f.toUpperCase() + s.substring(f.length);
  }
  return s;
}

/// Lower-cases the first letter of [s].
String lowerFirst(String s) {
  if (s.isEmpty) return s;
  final f = String.fromCharCode(s.runes.first);
  return f.toLowerCase() + s.substring(f.length);
}
