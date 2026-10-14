import 'package:flutter/material.dart';

import '../../core/core.dart';
import 'typing.dart';

/// Free-text answer input for production exercises (cloze without options).
///
/// [KeyboardAnswerField] types; the handwriting pad (`InkAnswerInput` in
/// `ui/ink/ink_answer_input.dart`, ML Kit Digital Ink, v0.5) implements the
/// same widget and reports recognizer alternatives in
/// [TextAnswer.candidates]. `answerInputBuilderProvider` picks one from the
/// Answer input setting.
abstract class AnswerInputWidget extends StatefulWidget {
  const AnswerInputWidget({
    super.key,
    required this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.hintText,
    this.preContext,
  });

  /// The current answer, or null when empty.
  final ValueChanged<TextAnswer?> onChanged;

  /// The user confirmed the answer (Enter on a keyboard, "done" on a canvas).
  final VoidCallback? onSubmitted;
  final bool enabled;
  final String? hintText;

  /// Text just before the answer (the words before a cloze gap): context for
  /// a handwriting recognizer; a keyboard ignores it.
  final String? preContext;

  InputMode get inputMode;
}

typedef AnswerInputBuilder = AnswerInputWidget Function({
  Key? key,
  required ValueChanged<TextAnswer?> onChanged,
  VoidCallback? onSubmitted,
  bool enabled,
  String? hintText,
  String? preContext,
});

AnswerInputWidget keyboardAnswerInputBuilder({
  Key? key,
  required ValueChanged<TextAnswer?> onChanged,
  VoidCallback? onSubmitted,
  bool enabled = true,
  String? hintText,
  String? preContext,
}) =>
    KeyboardAnswerField(key: key, onChanged: onChanged, onSubmitted: onSubmitted, enabled: enabled, hintText: hintText);

class KeyboardAnswerField extends AnswerInputWidget {
  const KeyboardAnswerField({super.key, required super.onChanged, super.onSubmitted, super.enabled, super.hintText});

  @override
  InputMode get inputMode => InputMode.keyboard;

  @override
  State<KeyboardAnswerField> createState() => _KeyboardAnswerFieldState();
}

class _KeyboardAnswerFieldState extends State<KeyboardAnswerField> {
  @override
  Widget build(BuildContext context) {
    // The accent bar (course letters, from `AccentLetters`) sits above the field.
    return TypedAnswerField(
      enabled: widget.enabled,
      hintText: widget.hintText,
      autofocus: widget.enabled,
      onChanged: (text) =>
          widget.onChanged(text.trim().isEmpty ? null : TextAnswer(text, inputMode: InputMode.keyboard)),
      onSubmitted: widget.onSubmitted,
    );
  }
}
