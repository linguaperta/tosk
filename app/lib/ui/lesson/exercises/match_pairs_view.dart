import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/core.dart';
import 'common.dart';
import 'match_board.dart';

export 'match_board.dart' show MatchBoard, MatchSide, MatchTap;

/// Tap a word, then its meaning (or the other way round). A wrong pair
/// flashes both cards as wrong and counts as missed for that word; when every
/// pair is matched the answer submits itself.
///
/// The board state lives in one [MatchBoard]; every tap is resolved
/// synchronously, and the flash timer only clears the marks of its own wrong
/// pair. With reduced motion there is no timer: the marks stay until the next
/// tap. After checking, both cards of every wrong pair stay marked and the
/// mix-ups are listed under the board.
class MatchPairsView extends ExerciseWidget<MatchPairsExercise> {
  const MatchPairsView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.onSubmit,
    super.onSelect,
    super.result,
    super.keys,
    super.reduceMotion,
  });

  /// How long a wrong pair stays marked (motion on).
  static const flashDuration = Duration(milliseconds: 600);

  @override
  State<MatchPairsView> createState() => _MatchPairsViewState();
}

class _MatchPairsViewState extends State<MatchPairsView> {
  late MatchBoard _board;
  final Map<int, Timer> _timers = {};
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _board = MatchBoard.of(widget.exercise);
  }

  @override
  void didUpdateWidget(covariant MatchPairsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exercise.id != widget.exercise.id) {
      _cancelTimers();
      _board = MatchBoard.of(widget.exercise);
      _submitted = false;
    }
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }

  void _tap(MatchSide side, int i) {
    if (widget.locked || _submitted) return;
    // Reduced motion: the last wrong pair stays marked until the next tap.
    if (widget.reduceMotion) _board.clearFlashes();
    final what = _board.tap(side, i);
    if (what == MatchTap.ignored) {
      setState(() {});
      return;
    }
    widget.onSelect?.call();
    if (what == MatchTap.wrong && !widget.reduceMotion) {
      final id = _board.lastFlashId;
      _timers[id] = Timer(MatchPairsView.flashDuration, () {
        _timers.remove(id);
        if (mounted && _board.endFlash(id)) setState(() {});
      });
    }
    setState(() {});
    if (_board.done && !_submitted) {
      _submitted = true;
      _cancelTimers();
      widget.onSubmit?.call(_board.answer());
    }
  }

  OptionState _state(MatchSide side, int i) {
    final b = _board;
    if (widget.locked) {
      if (!b.isMatched(side, i)) return OptionState.dimmed;
      final missed = side == MatchSide.left ? b.missedLeft : b.missedRight;
      // Both cards of every wrong pair are marked wrong.
      return missed.contains(i) ? OptionState.wrong : OptionState.correct;
    }
    if (b.isMatched(side, i)) return OptionState.correct;
    if (b.isSelected(side, i)) return OptionState.selected;
    if (b.isFlashing(side, i)) return OptionState.wrong;
    return OptionState.idle;
  }

  Widget _column(MatchSide side, List<String> labels) => Column(
    children: [
      for (var i = 0; i < labels.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OptionButton(
            key: ValueKey('match-${side.name}-$i'),
            label: labels[i],
            center: true,
            state: _state(side, i),
            onTap: () => _tap(side, i),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final wrong = _board.wrongPairs;
    final theme = Theme.of(context);
    final fb = FeedbackColors.of(context);
    return ExerciseLayout(
      prompt: InstructionText(e.instruction),
      controls: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _column(MatchSide.left, e.left)),
              const SizedBox(width: 10),
              Expanded(child: _column(MatchSide.right, e.right)),
            ],
          ),
          // After checking: which pairs were mixed up (both words, ✗).
          if (widget.locked && wrong.isNotEmpty)
            Padding(
              key: const ValueKey('match-mixups'),
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mixed up', style: theme.textTheme.labelLarge),
                  for (final (l, r) in {...wrong})
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.close, size: 18, color: fb.wrong),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${e.left[l]}  ≠  ${e.right[r]}',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                decoration: TextDecoration.lineThrough,
                                decorationColor: fb.wrong,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
