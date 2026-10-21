/// Word-level diff of a sentence answer against accepted answers
/// (docs/engine.md, "Partly right sentence answers").
///
/// Words are compared by the answer keys of [normalizeAnswer] (strict) or
/// [foldAnswer] (lenient), so case, punctuation, apostrophe variants and
/// (lenient) accents never make a word wrong. Elided words are their own
/// tokens (`l'acqua` = `l'` + `acqua`), so `l' acqua` and `l'acqua` agree.
/// The alignment is a longest common subsequence; unmatched words that
/// appear on both sides are "moved", the rest of each run between matches
/// pairs up as wrong words (learner) and corrections (accepted answer), with
/// leftovers extra or missing.
library;

import '../../core/interfaces/session.dart' show AccentStrictness;
import '../../core/models/exercise.dart';
import 'normalize.dart';

final RegExp _space = RegExp(r'\s+', unicode: true);

/// `l'acqua` -> `l'` + `acqua` (letters, an apostrophe, then a letter).
final RegExp _elided = RegExp("^(\\p{L}+['’‘ʼ])(\\p{L}.*)\$", unicode: true);

/// Splits [text] into display tokens: words and punctuation, with the
/// whitespace before each, elisions split off. `renderTokenRefs` of the
/// result gives [text] back (leading and trailing whitespace trimmed).
List<TokenRef> textTokens(String text) {
  final s = text.trim();
  final out = <TokenRef>[];
  var i = 0;
  for (final m in RegExp(r'\S+').allMatches(s)) {
    var pre = s.substring(i, m.start).replaceAll(_space, ' ');
    i = m.end;
    var word = m[0]!;
    while (true) {
      final e = _elided.firstMatch(word);
      // A single consonant after the apostrophe is no elision but one Dutch word: plurals
      // and genitives (foto's, baby's), contractions (m'n, z'n, zo'n). Italian c'è splits.
      if (e == null || (e[2]!.length == 1 && !'aeiouàáèéìíòóùú'.contains(e[2]!.toLowerCase()))) break;
      out.add(_tok(e[1]!, pre));
      pre = '';
      word = e[2]!;
    }
    out.add(_tok(word, pre));
  }
  return out;
}

TokenRef _tok(String text, String pre, {String? itemId, String? form}) =>
    TokenRef(text, pre: pre, itemId: itemId, form: form, isWord: normalizeAnswer(text).isNotEmpty);

/// Re-tokenizes aligned tokens (a sentence's `TokenRef`s) the way
/// [textTokens] splits text, keeping each token's alignment.
List<TokenRef> alignedTokens(List<TokenRef> tokens) => [
      for (var k = 0; k < tokens.length; k++)
        for (final (j, t) in textTokens(tokens[k].text).indexed)
          TokenRef(
            t.text,
            pre: j == 0 ? (k == 0 ? '' : tokens[k].pre) : t.pre,
            itemId: tokens[k].itemId,
            form: tokens[k].form,
            isWord: t.isWord,
          ),
    ];

/// Whether [a] and [b] have the same words (by [foldAnswer]).
bool sameWords(List<TokenRef> a, List<TokenRef> b) {
  final x = [for (final t in a) if (t.isWord) foldAnswer(t.text)];
  final y = [for (final t in b) if (t.isWord) foldAnswer(t.text)];
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

/// The learner's answer as tokens: each tile (or the typed text) split like
/// [textTokens], with the tile index as [DiffToken.source].
List<(TokenRef, int)> _givenTokens(List<String> parts) {
  final out = <(TokenRef, int)>[];
  for (var k = 0; k < parts.length; k++) {
    final ts = textTokens(parts[k]);
    for (var j = 0; j < ts.length; j++) {
      final t = ts[j];
      final pre = j == 0 ? (out.isEmpty ? '' : ' ') : t.pre;
      out.add((TokenRef(t.text, pre: pre, isWord: t.isWord), k));
    }
  }
  return out;
}

/// Compares [given] (the tiles in order, or one typed text) with [expected]
/// (an accepted answer's tokens, from [textTokens] or [alignedTokens]).
AnswerDiff diffAnswer(List<String> given, List<TokenRef> expected, AccentStrictness strictness, {int answerIndex = 0}) {
  String key(String s) => answerKey(s, strictness);
  final g = _givenTokens(given);
  final gw = [for (var i = 0; i < g.length; i++) if (g[i].$1.isWord) i];
  final ew = [for (var j = 0; j < expected.length; j++) if (expected[j].isWord) j];
  final gk = [for (final i in gw) key(g[i].$1.text)];
  final ek = [for (final j in ew) key(expected[j].text)];
  final n = gk.length, m = ek.length;

  // LCS table over the words.
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var a = n - 1; a >= 0; a--) {
    for (var b = m - 1; b >= 0; b--) {
      lcs[a][b] = gk[a] == ek[b] ? lcs[a + 1][b + 1] + 1 : (lcs[a + 1][b] >= lcs[a][b + 1] ? lcs[a + 1][b] : lcs[a][b + 1]);
    }
  }
  final gMark = List<DiffMark?>.filled(n, null);
  final eMark = List<DiffMark?>.filled(m, null);
  // Runs between matches: (given word indices, expected word indices).
  final runs = <(List<int>, List<int>)>[];
  // Where (in given words) each run starts: the missing marker goes there.
  final runAt = <int>[];
  var curG = <int>[], curE = <int>[];
  var a = 0, b = 0;
  void close() {
    if (curG.isNotEmpty || curE.isNotEmpty) {
      runs.add((curG, curE));
      runAt.add(a - curG.length);
    }
    curG = [];
    curE = [];
  }

  while (a < n || b < m) {
    if (a < n && b < m && gk[a] == ek[b]) {
      close();
      gMark[a] = DiffMark.same;
      eMark[b] = DiffMark.same;
      a++;
      b++;
    } else if (b >= m || (a < n && lcs[a + 1][b] >= lcs[a][b + 1])) {
      curG.add(a++);
    } else {
      curE.add(b++);
    }
  }
  close();

  // Moved: an unmatched word the accepted answer has elsewhere.
  final freeE = <String, List<int>>{};
  for (final (_, es) in runs) {
    for (final e in es) {
      (freeE[ek[e]] ??= []).add(e);
    }
  }
  for (final (gs, _) in runs) {
    for (final x in gs) {
      final list = freeE[gk[x]];
      if (list == null || list.isEmpty) continue;
      final e = list.removeAt(0);
      gMark[x] = DiffMark.moved;
      eMark[e] = DiffMark.moved;
    }
  }
  // Within each run: wrong words pair up with corrections in order.
  final missingAt = <int, int>{}; // given word index (or n) -> missing words before it
  for (var r = 0; r < runs.length; r++) {
    final gs = [for (final x in runs[r].$1) if (gMark[x] == null) x];
    final es = [for (final e in runs[r].$2) if (eMark[e] == null) e];
    final pairs = gs.length < es.length ? gs.length : es.length;
    for (var k = 0; k < pairs; k++) {
      gMark[gs[k]] = DiffMark.wrong;
      eMark[es[k]] = DiffMark.wrong;
    }
    for (var k = pairs; k < gs.length; k++) {
      gMark[gs[k]] = DiffMark.extra;
    }
    if (es.length > pairs) {
      for (var k = pairs; k < es.length; k++) {
        eMark[es[k]] = DiffMark.missing;
      }
      final at = runAt[r] + runs[r].$1.length;
      missingAt[at] = (missingAt[at] ?? 0) + es.length - pairs;
    }
  }

  final givenLine = <DiffToken>[];
  void marker(int at) {
    if ((missingAt[at] ?? 0) == 0) return;
    givenLine.add(DiffToken('', pre: givenLine.isEmpty ? '' : ' ', mark: DiffMark.missing));
  }

  var w = 0;
  for (var i = 0; i < g.length; i++) {
    final (t, src) = g[i];
    if (t.isWord) {
      marker(w);
      givenLine.add(DiffToken(t.text, pre: t.pre, mark: gMark[w]!, source: src));
      w++;
    } else {
      givenLine.add(DiffToken(t.text, pre: t.pre, isWord: false, source: src));
    }
  }
  marker(n);

  var v = 0;
  final expectedLine = [
    for (final t in expected)
      DiffToken(
        t.text,
        pre: t.pre,
        mark: t.isWord ? eMark[v++]! : DiffMark.same,
        isWord: t.isWord,
        itemId: t.itemId,
        form: t.form,
      ),
  ];
  return AnswerDiff(given: givenLine, expected: expectedLine, answerIndex: answerIndex);
}

/// The diff against the closest of [accepted] (fewest places to fix, then
/// most words in place, then the earliest answer).
AnswerDiff? bestAnswerDiff(List<String> given, List<List<TokenRef>> accepted, AccentStrictness strictness) {
  AnswerDiff? best;
  for (var i = 0; i < accepted.length; i++) {
    if (accepted[i].isEmpty) continue;
    final d = diffAnswer(given, accepted[i], strictness, answerIndex: i);
    if (best == null || d.errors < best.errors || (d.errors == best.errors && d.matched > best.matched)) best = d;
  }
  return best;
}

/// The facet a word of a sentence trains, from its alignment: a verb form
/// (`'{tense}.{person}'`) its tense's `#form`, an inflected word
/// (`'infl:{table}.{cell}'`) its table's `#infl`, any other word `#prod`.
String? facetOfToken(String? itemId, String? form) {
  if (itemId == null) return null;
  if (form == null || form.isEmpty) return '$itemId#prod';
  if (form.startsWith('infl:')) {
    final rest = form.substring(5);
    final dot = rest.indexOf('.');
    return '$itemId#infl:${dot < 0 ? rest : rest.substring(0, dot)}';
  }
  final dot = form.indexOf('.');
  return '$itemId#form:${dot < 0 ? form : form.substring(0, dot)}';
}

/// Indices of [b]'s words that are not in a longest common subsequence with
/// [a]'s words: what a transform changed (compared by [foldAnswer]).
Set<int> changedWords(List<TokenRef> a, List<TokenRef> b) {
  final aw = [for (final t in a) if (t.isWord) foldAnswer(t.text)];
  final bi = [for (var j = 0; j < b.length; j++) if (b[j].isWord) j];
  final bw = [for (final j in bi) foldAnswer(b[j].text)];
  final n = aw.length, m = bw.length;
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var x = n - 1; x >= 0; x--) {
    for (var y = m - 1; y >= 0; y--) {
      lcs[x][y] = aw[x] == bw[y] ? lcs[x + 1][y + 1] + 1 : (lcs[x + 1][y] >= lcs[x][y + 1] ? lcs[x + 1][y] : lcs[x][y + 1]);
    }
  }
  final changed = <int>{};
  var x = 0, y = 0;
  while (y < m) {
    if (x < n && aw[x] == bw[y]) {
      x++;
      y++;
    } else if (x < n && lcs[x + 1][y] >= lcs[x][y + 1]) {
      x++;
    } else {
      changed.add(bi[y]);
      y++;
    }
  }
  return changed;
}
