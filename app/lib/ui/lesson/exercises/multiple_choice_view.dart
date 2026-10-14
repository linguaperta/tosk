import 'package:flutter/material.dart';

import '../../../core/core.dart';
import 'common.dart';

/// Pick the translation of a word or sentence.
class MultipleChoiceView extends ExerciseWidget<MultipleChoiceExercise> {
  const MultipleChoiceView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.result,
    super.keys,
    super.reduceMotion,
  });

  @override
  State<MultipleChoiceView> createState() => _MultipleChoiceViewState();
}

class _MultipleChoiceViewState extends State<MultipleChoiceView> with ExerciseKeysMixin<MultipleChoiceView> {
  int? _selected;

  void _select(int i) {
    if (widget.locked) return;
    setState(() => _selected = i);
    widget.onChanged(ChoiceAnswer(i));
  }

  @override
  void onDigit(int n) {
    if (n >= 1 && n <= widget.exercise.options.length) _select(n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final theme = Theme.of(context);
    return ExerciseLayout(
      prompt: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InstructionText(e.instruction),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              e.prompt,
              textAlign: TextAlign.center,
              style: e.isSentence ? theme.textTheme.titleLarge : theme.textTheme.headlineMedium,
            ),
          ),
          if (e.hint != null)
            Center(
              child: Padding(
                key: const ValueKey('mc-hint'),
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  e.hint!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
        ],
      ),
      controls: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < e.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OptionButton(
                key: ValueKey('option-$i'),
                number: i + 1,
                label: e.options[i],
                large: true,
                state: choiceState(index: i, selected: _selected, correctIndex: e.correctIndex, result: widget.result),
                onTap: widget.locked ? null : () => _select(i),
              ),
            ),
        ],
      ),
    );
  }
}
