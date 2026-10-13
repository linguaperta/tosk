import 'package:flutter/material.dart';

import '../../core/core.dart';

/// Free-text answer input for production exercises (cloze without options now,
/// grids in free-input mode later).
///
/// The keyboard implementation ships in v1. The handwriting one (ML Kit Digital
/// Ink, Phase 8) implements this same widget and reports recognizer alternatives
/// in [TextAnswer.candidates]; it plugs in through `answerInputBuilderProvider`.
abstract class AnswerInputWidget extends StatefulWidget {
  const AnswerInputWidget({super.key, required this.onChanged, this.onSubmitted, this.enabled = true, this.hintText});

  /// The current answer, or null when empty.
  final ValueChanged<TextAnswer?> onChanged;

  /// The user confirmed the answer (Enter on a keyboard, "done" on a canvas).
  final VoidCallback? onSubmitted;
  final bool enabled;
  final String? hintText;

  InputMode get inputMode;
}

typedef AnswerInputBuilder = AnswerInputWidget Function({
  Key? key,
  required ValueChanged<TextAnswer?> onChanged,
  VoidCallback? onSubmitted,
  bool enabled,
  String? hintText,
});

AnswerInputWidget keyboardAnswerInputBuilder({
  Key? key,
  required ValueChanged<TextAnswer?> onChanged,
  VoidCallback? onSubmitted,
  bool enabled = true,
  String? hintText,
}) =>
    KeyboardAnswerInput(key: key, onChanged: onChanged, onSubmitted: onSubmitted, enabled: enabled, hintText: hintText);

class KeyboardAnswerInput extends AnswerInputWidget {
  const KeyboardAnswerInput({super.key, required super.onChanged, super.onSubmitted, super.enabled, super.hintText});

  @override
  InputMode get inputMode => InputMode.keyboard;

  @override
  State<KeyboardAnswerInput> createState() => _KeyboardAnswerInputState();
}

class _KeyboardAnswerInputState extends State<KeyboardAnswerInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('answer-input'),
      controller: _controller,
      enabled: widget.enabled,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(border: const OutlineInputBorder(), hintText: widget.hintText ?? 'Type your answer'),
      onChanged: (text) =>
          widget.onChanged(text.trim().isEmpty ? null : TextAnswer(text, inputMode: InputMode.keyboard)),
      onSubmitted: (_) => widget.onSubmitted?.call(),
    );
  }
}
