import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/core.dart';
import 'common.dart';

/// Tap a word, then its meaning. A wrong pair flashes red and counts as missed
/// for that word; when every pair is matched the answer submits itself.
class MatchPairsView extends ExerciseWidget<MatchPairsExercise> {
  const MatchPairsView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.onSubmit,
    super.result,
    super.keys,
    super.reduceMotion,
  });

  /// How long a wrong pair stays red.
  static const flashDuration = Duration(milliseconds: 450);

  @override
  State<MatchPairsView> createState() => _MatchPairsViewState();
}

class _MatchPairsViewState extends State<MatchPairsView> {
  int? _left;
  int? _right;
  final Map<int, int> _matches = {};
  final Set<int> _missed = {};
  (int, int)? _flash;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  bool get _done => _matches.length == widget.exercise.left.length;

  void _tapLeft(int i) {
    if (widget.locked || _matches.containsKey(i)) return;
    setState(() => _left = _left == i ? null : i);
    _tryPair();
  }

  void _tapRight(int j) {
    if (widget.locked || _matches.containsValue(j)) return;
    setState(() => _right = _right == j ? null : j);
    _tryPair();
  }

  void _tryPair() {
    final l = _left, r = _right;
    if (l == null || r == null) return;
    final e = widget.exercise;
    setState(() {
      _left = null;
      _right = null;
      if (e.solution[l] == r) {
        _matches[l] = r;
      } else {
        _missed.add(l);
        _flash = (l, r);
        _flashTimer?.cancel();
        _flashTimer = Timer(MatchPairsView.flashDuration, () {
          if (mounted) setState(() => _flash = null);
        });
      }
    });
    if (_done) {
      widget.onSubmit?.call(MatchAnswer(Map.of(_matches), missed: Set.of(_missed)));
    }
  }

  OptionState _leftState(int i) {
    if (_flash?.$1 == i) return OptionState.wrong;
    if (_matches.containsKey(i)) return _missed.contains(i) && widget.locked ? OptionState.wrong : OptionState.correct;
    return _left == i ? OptionState.selected : OptionState.idle;
  }

  OptionState _rightState(int j) {
    if (_flash?.$2 == j) return OptionState.wrong;
    if (_matches.containsValue(j)) return OptionState.correct;
    return _right == j ? OptionState.selected : OptionState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    return ExerciseLayout(
      prompt: InstructionText(e.instruction),
      controls: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < e.left.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OptionButton(
                      key: ValueKey('match-left-$i'),
                      label: e.left[i],
                      center: true,
                      state: _leftState(i),
                      onTap: () => _tapLeft(i),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                for (var j = 0; j < e.right.length; j++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OptionButton(
                      key: ValueKey('match-right-$j'),
                      label: e.right[j],
                      center: true,
                      state: _rightState(j),
                      onTap: () => _tapRight(j),
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
