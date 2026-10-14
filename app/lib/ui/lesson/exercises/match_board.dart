/// The match-pairs board as a pure state machine: the single source of truth
/// for [MatchPairsView] (no Flutter, so it can be stress-tested directly).
library;

import '../../../core/core.dart';

/// Which column a card is in.
enum MatchSide { left, right }

/// What a tap did.
enum MatchTap {
  /// Nothing: a matched card, a finished board or an index off the board.
  ignored,

  /// The card is now selected (waiting for its partner).
  selected,

  /// The selected card was tapped again and is no longer selected.
  deselected,

  /// The card completed a correct pair.
  matched,

  /// The card completed a wrong pair: both cards flash as wrong and are
  /// deselected; the left word counts as missed.
  wrong,
}

/// Rules:
///
/// * A pair is formed by one left and one right card, in either order. It is
///   resolved the moment the second card is tapped, synchronously, so no
///   timer or animation can ever clear or change a selection.
/// * Tapping the other card of the same column replaces the selection;
///   tapping the selected card again deselects it.
/// * Matched cards ignore taps.
/// * A wrong pair is recorded ([wrongPairs]) and both its cards flash. A flash
///   is only a mark: the cards are free again immediately, and tapping one
///   ends its flash. [endFlash] (the view's timer) clears only the cards of
///   that one flash, never a newer selection or a newer flash.
class MatchBoard {
  MatchBoard({required this.solution, required this.size});

  /// The board of [e].
  factory MatchBoard.of(MatchPairsExercise e) => MatchBoard(solution: e.solution, size: e.left.length);

  /// left index -> right index.
  final Map<int, int> solution;

  /// Number of pairs (cards per column).
  final int size;

  int? _left;
  int? _right;
  final Map<int, int> _matches = {};
  final Set<int> _matchedRight = {};
  final List<(int, int)> _wrong = [];
  final Map<int, int> _flashLeft = {};
  final Map<int, int> _flashRight = {};
  int _flashSeq = 0;

  int? get selectedLeft => _left;
  int? get selectedRight => _right;

  /// left -> right, as matched so far (always correct pairs).
  Map<int, int> get matches => Map.unmodifiable(_matches);

  /// Every wrong pair tried, in order (left, right).
  List<(int, int)> get wrongPairs => List.unmodifiable(_wrong);

  /// Left cards that were part of a wrong pair (their facets count as missed).
  Set<int> get missedLeft => {for (final p in _wrong) p.$1};

  /// Right cards that were part of a wrong pair.
  Set<int> get missedRight => {for (final p in _wrong) p.$2};

  bool get done => _matches.length >= size;

  bool isMatched(MatchSide side, int i) => side == MatchSide.left ? _matches.containsKey(i) : _matchedRight.contains(i);

  bool isSelected(MatchSide side, int i) => (side == MatchSide.left ? _left : _right) == i;

  bool isFlashing(MatchSide side, int i) => (side == MatchSide.left ? _flashLeft : _flashRight).containsKey(i);

  /// Whether any card is flashing.
  bool get flashing => _flashLeft.isNotEmpty || _flashRight.isNotEmpty;

  /// The id of the flash started by the last wrong pair.
  int get lastFlashId => _flashSeq;

  MatchTap tap(MatchSide side, int i) {
    if (done || i < 0 || i >= size || isMatched(side, i)) return MatchTap.ignored;
    // A tapped card is no longer marked wrong: it shows its selection.
    (side == MatchSide.left ? _flashLeft : _flashRight).remove(i);
    if (side == MatchSide.left) {
      if (_left == i) {
        _left = null;
        return MatchTap.deselected;
      }
      _left = i;
    } else {
      if (_right == i) {
        _right = null;
        return MatchTap.deselected;
      }
      _right = i;
    }
    final l = _left, r = _right;
    if (l == null || r == null) return MatchTap.selected;
    _left = null;
    _right = null;
    if (solution[l] == r) {
      _matches[l] = r;
      _matchedRight.add(r);
      return MatchTap.matched;
    }
    _wrong.add((l, r));
    final id = ++_flashSeq;
    _flashLeft[l] = id;
    _flashRight[r] = id;
    return MatchTap.wrong;
  }

  /// Ends flash [id]: un-marks the cards still flashing from that wrong pair.
  /// Returns whether anything changed.
  bool endFlash(int id) {
    final before = _flashLeft.length + _flashRight.length;
    _flashLeft.removeWhere((_, v) => v == id);
    _flashRight.removeWhere((_, v) => v == id);
    return before != _flashLeft.length + _flashRight.length;
  }

  /// Ends every flash (reduced motion: marks stay until the next tap).
  bool clearFlashes() {
    if (!flashing) return false;
    _flashLeft.clear();
    _flashRight.clear();
    return true;
  }

  /// The answer to submit (complete once [done]).
  MatchAnswer answer() => MatchAnswer(Map.of(_matches), missed: missedLeft, wrongPairs: List.of(_wrong));
}
