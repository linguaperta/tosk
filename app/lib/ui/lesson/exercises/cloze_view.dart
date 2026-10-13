import 'package:flutter/material.dart';

import '../../../core/core.dart';
import '../answer_input.dart';
import 'common.dart';

/// Fill the gap in a sentence: choice chips when the engine gives options, else
/// free input through the pluggable [AnswerInputWidget] (keyboard now, ink later).
class ClozeView extends ExerciseWidget<ClozeExercise> {
  const ClozeView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.onCheck,
    super.result,
    super.keys,
    super.reduceMotion,
    this.inputBuilder = keyboardAnswerInputBuilder,
  });

  final AnswerInputBuilder inputBuilder;

  @override
  State<ClozeView> createState() => _ClozeViewState();
}

class _ClozeViewState extends State<ClozeView> with ExerciseKeysMixin<ClozeView> {
  int? _selected;
  String _typed = '';

  void _select(int i) {
    if (widget.locked) return;
    setState(() => _selected = i);
    widget.onChanged(ChoiceAnswer(i));
  }

  @override
  void onDigit(int n) {
    final options = widget.exercise.options;
    if (options != null && n >= 1 && n <= options.length) _select(n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final theme = Theme.of(context);
    final fb = FeedbackColors.of(context);
    final options = e.options;
    final result = widget.result;

    final String gapText;
    if (options != null) {
      gapText = _selected == null ? '' : options[_selected!];
    } else {
      gapText = _typed;
    }
    final gapColor = result == null ? theme.colorScheme.secondary : (result.correct ? fb.correct : fb.wrong);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InstructionText(e.instruction),
        Text.rich(
          key: const ValueKey('cloze-sentence'),
          TextSpan(
            children: [
              TextSpan(text: e.before),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 56),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: gapColor, width: 2)),
                  ),
                  child: Text(
                    gapText.isEmpty ? ' ' : gapText,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(color: gapColor),
                  ),
                ),
              ),
              TextSpan(text: e.after),
            ],
          ),
          style: theme.textTheme.headlineSmall,
        ),
        if (e.hint != null) ...[const SizedBox(height: 12), SubtleText(e.hint!, icon: Icons.lightbulb_outline)],
        if (e.translation != null) ...[
          const SizedBox(height: 8),
          SubtleText(e.translation!, italic: true, icon: Icons.translate),
        ],
        const SizedBox(height: 24),
        if (options != null)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < options.length; i++)
                SizedBox(
                  width: 140,
                  child: OptionButton(
                    key: ValueKey('cloze-option-$i'),
                    number: i + 1,
                    label: options[i],
                    state: choiceState(
                      index: i,
                      selected: _selected,
                      correctIndex: e.correctIndex ?? -1,
                      result: result,
                    ),
                    onTap: widget.locked ? null : () => _select(i),
                  ),
                ),
            ],
          )
        else
          widget.inputBuilder(
            enabled: !widget.locked,
            hintText: 'Type the missing word',
            onChanged: (answer) {
              setState(() => _typed = answer?.text.trim() ?? '');
              widget.onChanged(answer);
            },
            onSubmitted: widget.onCheck,
          ),
      ],
    );
  }
}
