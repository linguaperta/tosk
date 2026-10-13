import 'package:flutter/material.dart';

import '../../../core/core.dart';
import 'common.dart';

/// Tap the wrong word in a sentence.
class SpotErrorView extends ExerciseWidget<SpotErrorExercise> {
  const SpotErrorView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.result,
    super.keys,
    super.reduceMotion,
  });

  @override
  State<SpotErrorView> createState() => _SpotErrorViewState();
}

/// Groups tokens so punctuation sticks to its word: leading punctuation (¿, «)
/// joins the next word, trailing punctuation the previous one.
List<List<int>> groupTokens(List<String> tokens, List<bool> isWord) {
  final groups = <List<int>>[];
  final pending = <int>[];
  for (var i = 0; i < tokens.length; i++) {
    final word = i < isWord.length ? isWord[i] : true;
    if (word) {
      groups.add([...pending, i]);
      pending.clear();
    } else if (groups.isEmpty || _isOpening(tokens[i])) {
      pending.add(i);
    } else {
      groups.last.add(i);
    }
  }
  if (pending.isNotEmpty) groups.add(List.of(pending));
  return groups;
}

bool _isOpening(String t) => const {'¿', '¡', '«', '(', '“', '"', "'"}.contains(t);

class _SpotErrorViewState extends State<SpotErrorView> {
  int? _selected;

  void _tap(int i) {
    if (widget.locked) return;
    setState(() => _selected = i);
    widget.onChanged(TokenAnswer(i));
  }

  OptionState _state(int i) {
    final e = widget.exercise;
    if (widget.result == null) return _selected == i ? OptionState.selected : OptionState.idle;
    if (i == e.errorIndex) return OptionState.wrong;
    return OptionState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final theme = Theme.of(context);
    final fb = FeedbackColors.of(context);
    final groups = groupTokens(e.tokens, e.tokenIsWord);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InstructionText(e.instruction),
        Wrap(
          spacing: 6,
          runSpacing: 10,
          children: [
            for (final g in groups)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final i in g)
                    if (i < e.tokenIsWord.length && !e.tokenIsWord[i])
                      Text(e.tokens[i], style: theme.textTheme.titleLarge)
                    else
                      WordTile(
                        key: ValueKey('token-$i'),
                        label: e.tokens[i],
                        state: _state(i),
                        onTap: widget.locked ? null : () => _tap(i),
                      ),
                ],
              ),
          ],
        ),
        if (widget.result != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.edit, size: 18, color: fb.correct),
              const SizedBox(width: 6),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: e.tokens[e.errorIndex],
                        style: const TextStyle(decoration: TextDecoration.lineThrough),
                      ),
                      const TextSpan(text: '  →  '),
                      TextSpan(
                        text: e.correction,
                        style: TextStyle(color: fb.correct, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ],
        if (e.translation != null) ...[
          const SizedBox(height: 16),
          SubtleText(e.translation!, italic: true, icon: Icons.translate),
        ],
      ],
    );
  }
}
