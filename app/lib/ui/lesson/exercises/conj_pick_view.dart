import 'package:flutter/material.dart';

import '../../../core/core.dart';
import 'common.dart';

/// Display label for an ending; the empty ending (Dutch "ik werk") shows as ∅.
String endingLabel(String ending) => ending.isEmpty ? '∅' : '-$ending';

/// The stem is shown (`mang___`); pick the ending for a person and tense.
class ConjPickView extends ExerciseWidget<ConjPickExercise> {
  const ConjPickView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.result,
    super.keys,
    super.reduceMotion,
  });

  @override
  State<ConjPickView> createState() => _ConjPickViewState();
}

class _ConjPickViewState extends State<ConjPickView> with ExerciseKeysMixin<ConjPickView> {
  int? _selected;

  void _select(int i) {
    if (widget.locked) return;
    setState(() => _selected = i);
    widget.onChanged(ChoiceAnswer(i));
  }

  @override
  void onDigit(int n) {
    if (n >= 1 && n <= widget.exercise.endings.length) _select(n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final theme = Theme.of(context);
    final fb = FeedbackColors.of(context);
    final sel = _selected;
    final ending = sel == null ? null : e.endings[sel];
    final endingColor = widget.result == null
        ? theme.colorScheme.secondary
        : (widget.result!.correct ? fb.correct : fb.wrong);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InstructionText(e.instruction),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: e.lemma,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (e.gloss.isNotEmpty) TextSpan(text: '  ·  ${e.gloss}'),
            ],
          ),
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Chip(avatar: const Icon(Icons.person_outline, size: 16), label: Text(e.personLabel)),
            Chip(avatar: const Icon(Icons.schedule, size: 16), label: Text(e.tenseLabel)),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: Text.rich(
            key: const ValueKey('conj-pick-word'),
            TextSpan(
              children: [
                TextSpan(text: e.stem),
                TextSpan(
                  text: ending ?? '___',
                  style: TextStyle(
                    color: ending == null ? theme.colorScheme.outline : endingColor,
                    decoration: ending == null ? null : TextDecoration.underline,
                  ),
                ),
              ],
            ),
            style: theme.textTheme.displaySmall,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < e.endings.length; i++)
              SizedBox(
                width: 120,
                child: OptionButton(
                  key: ValueKey('ending-$i'),
                  number: i + 1,
                  label: endingLabel(e.endings[i]),
                  state: choiceState(index: i, selected: sel, correctIndex: e.correctIndex, result: widget.result),
                  onTap: widget.locked ? null : () => _select(i),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
