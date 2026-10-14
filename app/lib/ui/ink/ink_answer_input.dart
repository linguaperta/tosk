import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../lesson/answer_input.dart';
import 'ink_pad.dart';

/// The handwriting [AnswerInputWidget] (v0.5): an [InkPad] whose reading is
/// reported as `TextAnswer(best, inputMode: ink, candidates: [next two])`.
/// The engine accepts the answer when any candidate matches.
class InkAnswerInput extends AnswerInputWidget {
  const InkAnswerInput({
    super.key,
    required super.onChanged,
    super.onSubmitted,
    super.enabled,
    super.hintText,
    super.preContext,
    this.segmented = false,
  });

  /// Whole sentences: written in parts ("Next word").
  final bool segmented;

  @override
  InputMode get inputMode => InputMode.ink;

  @override
  State<InkAnswerInput> createState() => _InkAnswerInputState();
}

class _InkAnswerInputState extends State<InkAnswerInput> {
  @override
  Widget build(BuildContext context) => InkPad(
        enabled: widget.enabled,
        preContext: widget.preContext,
        hintText: widget.hintText ?? 'Write here',
        segmented: widget.segmented,
        onChanged: (r) => widget.onChanged(r?.toAnswer()),
      );
}

AnswerInputWidget inkAnswerInputBuilder({
  Key? key,
  required ValueChanged<TextAnswer?> onChanged,
  VoidCallback? onSubmitted,
  bool enabled = true,
  String? hintText,
  String? preContext,
}) =>
    InkAnswerInput(
      key: key,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
      hintText: 'Write here',
      preContext: preContext,
    );
