import 'package:flutter/material.dart';

import '../../../core/core.dart';
import '../../common/word_popover.dart';
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
    final tokens = e.sentenceTokens;
    // Recognizing a sentence: its words are tappable. Producing one: the
    // correct option becomes tappable once checked (never before: that
    // would point at the answer).
    final tappablePrompt =
        e.isSentence && e.direction == Direction.recognize && tokens != null && renderTokenRefs(tokens) == e.prompt;
    final tappableAnswer =
        widget.locked &&
        e.isSentence &&
        e.direction == Direction.produce &&
        tokens != null &&
        renderTokenRefs(tokens) == e.options[e.correctIndex];
    return ExerciseLayout(
      prompt: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InstructionText(e.instruction),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: tappablePrompt
                ? TappableSentence(
                    key: const ValueKey('mc-prompt-sentence'),
                    tokens: e.sentenceTokens!,
                    textAlign: TextAlign.center,
                    enabled: hideItemUntilAnswered(e, answered: widget.locked),
                    style: theme.textTheme.titleLarge,
                  )
                : Text(
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
          // A list (one column): options are often sentences. Tiles keep
          // their own height; long words shrink instead of breaking.
          ChoiceGrid(
            maxColumns: 1,
            uniformHeight: false,
            large: true,
            options: [
              for (var i = 0; i < e.options.length; i++)
                ChoiceOption(
                  key: ValueKey('option-$i'),
                  number: i + 1,
                  label: e.options[i],
                  labelWidget: tappableAnswer && i == e.correctIndex
                      ? TappableSentence(
                          key: const ValueKey('mc-answer-sentence'),
                          tokens: tokens,
                          style: optionLook(context, OptionState.correct, base: theme.textTheme.titleMedium).style,
                        )
                      : null,
                  state: choiceState(
                    index: i,
                    selected: _selected,
                    correctIndex: e.correctIndex,
                    result: widget.result,
                  ),
                  onTap: widget.locked ? null : () => _select(i),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
