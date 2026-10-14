import 'package:flutter/material.dart';

import '../../../core/core.dart';
import '../../../engine/templates/conj_pick.dart' show kNoEnding;
import '../typing.dart';
import 'common.dart';

/// Whether [ending] is the empty ending (Dutch "ik werk"): the engine sends it
/// as [kNoEnding] ('–'); an empty string means the same.
bool isNoEnding(String ending) => ending.isEmpty || ending == kNoEnding;

/// Display label for an ending; the empty ending shows as [kNoEnding] ('–').
String endingLabel(String ending) => isNoEnding(ending) ? kNoEnding : '-$ending';

/// The stem is shown (`mang___`); pick the ending for a person and tense.
class ConjPickView extends ExerciseWidget<ConjPickExercise> {
  const ConjPickView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.result,
    super.keys,
    super.reduceMotion,
    super.onCheck,
    this.typed = false,
  });

  /// Typing mode: type the ending instead of picking it.
  final bool typed;

  @override
  State<ConjPickView> createState() => _ConjPickViewState();
}

class _ConjPickViewState extends State<ConjPickView> with ExerciseKeysMixin<ConjPickView> {
  int? _selected;
  String _typed = '';

  void _type(String text) {
    if (widget.locked) return;
    setState(() => _typed = text.trim());
    widget.onChanged(_typed.isEmpty ? null : TextAnswer(_typed, inputMode: InputMode.keyboard));
  }

  void _select(int i) {
    if (widget.locked) return;
    setState(() => _selected = i);
    widget.onChanged(ChoiceAnswer(i));
  }

  @override
  void onDigit(int n) {
    if (widget.typed) return;
    if (n >= 1 && n <= widget.exercise.endings.length) _select(n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final theme = Theme.of(context);
    final fb = FeedbackColors.of(context);
    final sel = _selected;
    final typedEnding = _typed.replaceFirst(RegExp(r'^[-–]\s*'), '');
    final picked = widget.typed ? (_typed.isEmpty ? null : typedEnding) : (sel == null ? null : e.endings[sel]);
    final ending = picked == null ? null : (isNoEnding(picked) ? '' : picked);
    final endingColor = widget.result == null
        ? theme.colorScheme.secondary
        : (widget.result!.correct ? fb.correct : fb.wrong);

    return ExerciseLayout(
      prompt: Column(
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
              // An inflection table (plural, feminine plural, diminutive) names
              // just the cell; a conjugation names the person and the tense.
              if (e.inflection)
                Chip(avatar: const Icon(Icons.label_outline, size: 16), label: Text(e.personLabel))
              else ...[
                Chip(avatar: const Icon(Icons.person_outline, size: 16), label: Text(e.personLabel)),
                Chip(avatar: const Icon(Icons.schedule, size: 16), label: Text(e.tenseLabel)),
              ],
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
        ],
      ),
      controls: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.typed)
            TypedAnswerField(
              key: const ValueKey('conj-pick-typed'),
              enabled: !widget.locked,
              autofocus: true,
              prefixText: e.stem,
              hintText: 'ending',
              helperText: e.endings.any(isNoEnding) ? 'No ending? Type -' : null,
              onChanged: _type,
              onSubmitted: widget.onCheck,
            )
          else
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
      ),
    );
  }
}
