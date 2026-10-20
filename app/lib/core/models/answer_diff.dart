/// A word-level comparison of a wrong sentence answer with the closest
/// accepted answer, for feedback that marks exactly the places that are
/// wrong (docs/engine.md, "Partly right sentence answers"). The engine
/// computes it ([Result.diff]); the UI renders it.
library;

import 'package:meta/meta.dart';

/// How one word of a [AnswerDiff] line compares with the other line.
enum DiffMark {
  /// The same word in the same place (after answer normalization and the
  /// accent rule).
  same,

  /// Learner line: a word typed or placed instead of the right one.
  /// Correct line: the right word for that place (the correction).
  wrong,

  /// Learner line only: a word that does not belong in the answer.
  extra,

  /// Correct line: a word the learner left out. Learner line: a marker
  /// (empty [DiffToken.text]) where the missing words belong.
  missing,

  /// A right word in the wrong place (both lines).
  moved,
}

/// One displayed token of a diff line.
@immutable
class DiffToken {
  const DiffToken(
    this.text, {
    this.pre = '',
    this.mark = DiffMark.same,
    this.isWord = true,
    this.source,
    this.itemId,
    this.form,
  });

  /// The token as written (punctuation and case kept). Empty for a
  /// [DiffMark.missing] marker in the learner line.
  final String text;

  /// Whitespace before the token.
  final String pre;
  final DiffMark mark;

  /// False for punctuation: shown, never compared or marked.
  final bool isWord;

  /// Learner line: the index of the tile (or typed word) the token came
  /// from, so a tile answer can mark its tiles. Null for markers.
  final int? source;

  /// Correct line: the token's alignment (`TokenRef.itemId` / `form`), when
  /// the accepted answer carries one (the facet mapping of partial credit).
  final String? itemId;
  final String? form;

  bool get isError => isWord && mark != DiffMark.same;
}

/// The learner's answer and the closest accepted answer, word by word.
@immutable
class AnswerDiff {
  const AnswerDiff({required this.given, required this.expected, this.answerIndex = 0});

  /// The learner's answer: [DiffMark.same], [DiffMark.wrong],
  /// [DiffMark.extra], [DiffMark.moved], and [DiffMark.missing] markers.
  final List<DiffToken> given;

  /// The accepted answer it was compared with: [DiffMark.same],
  /// [DiffMark.wrong] (corrections), [DiffMark.missing] and [DiffMark.moved].
  final List<DiffToken> expected;

  /// Which accepted answer (index into the exercise's answers) was closest.
  final int answerIndex;

  /// Words of the accepted answer.
  int get expectedWords => expected.where((t) => t.isWord).length;

  /// Words of the accepted answer the learner has in the same place.
  int get matched => expected.where((t) => t.isWord && t.mark == DiffMark.same).length;

  /// Right words in the wrong place.
  int get moved => expected.where((t) => t.isWord && t.mark == DiffMark.moved).length;

  /// Places to fix: each wrong word, extra word, missing word and moved word.
  int get errors =>
      expected.where((t) => t.isWord && (t.mark == DiffMark.wrong || t.mark == DiffMark.missing)).length +
      given.where((t) => t.isWord && (t.mark == DiffMark.extra || t.mark == DiffMark.moved)).length;

  /// Wrong in only one or a few places: at least one word right in place,
  /// at least half of the words right (in place or moved), and at most
  /// `min(4, max(1, words ~/ 2))` places to fix. Only then does the UI mark
  /// the places and the engine give per-facet credit.
  bool get partial {
    final words = expectedWords;
    final e = errors;
    if (words == 0 || e == 0 || matched == 0) return false;
    if ((matched + moved) * 2 < words) return false;
    final cap = (words ~/ 2).clamp(1, 4);
    return e <= cap;
  }

  /// Renders a line back to text (markers left out).
  static String render(List<DiffToken> line) => line.where((t) => t.text.isNotEmpty).map((t) => '${t.pre}${t.text}').join();
}
