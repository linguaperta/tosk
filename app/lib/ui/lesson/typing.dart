/// Typed answers ("challenge mode") and the accent bar.
///
/// * [TypedAnswerField]: a text field that reports every change (typing and
///   accent-bar inserts) and carries the accent bar above it.
/// * [AccentBar]: one row of the course's special letters (from course data,
///   `specialLetters`), 48 px targets; a tap inserts the letter at the cursor
///   of the field, a long press its capital. It sits in a
///   [TextFieldTapRegion], so tapping it never takes the focus (and the
///   on-screen keyboard) away from the field.
/// * [AccentLetters]: provides the letters to every field below it (the
///   exercise view sets it from [accentLettersProvider]).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/special_letters.dart';
import '../../providers.dart' show courseDataProvider;
import '../theme/bw_skin.dart';

/// Whether a typed answer takes the keyboard focus as its exercise appears:
/// on desktops (the native apps and desktop browsers), where a physical
/// keyboard is the norm, so "type, Enter, Enter, type" works without the
/// mouse. Not on phones and tablets, where it would pop the on-screen
/// keyboard over the exercise; there the learner taps the field.
bool get focusTypedAnswers => switch (defaultTargetPlatform) {
  TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
  _ => false,
};

/// Gives [node] the focus after the current frame when [focusTypedAnswers].
///
/// A plain `autofocus` loses to the lesson player, which takes the focus
/// for its keyboard shortcuts (Enter, number keys) whenever an exercise
/// starts, so the field was never focused.
void focusTypedAnswerSoon(State state, FocusNode node) {
  if (!focusTypedAnswers) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (state.mounted && node.canRequestFocus) node.requestFocus();
  });
}

/// The active course's special letters, most frequent first (empty for
/// courses written in plain ASCII).
final accentLettersProvider = Provider<List<String>>((ref) {
  final course = ref.watch(courseDataProvider).value;
  return course == null ? const [] : specialLetters(course);
});

/// The accent-bar letters for the fields below.
class AccentLetters extends InheritedWidget {
  const AccentLetters({super.key, required this.letters, required super.child});

  final List<String> letters;

  static List<String> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccentLetters>()?.letters ?? const [];

  @override
  bool updateShouldNotify(AccentLetters old) => old.letters.join() != letters.join();
}

/// Replaces the selection of [c] (or appends, without one) with [text] and
/// puts the cursor after it.
void insertAtCursor(TextEditingController c, String text) {
  final v = c.value;
  final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
  final start = sel.start.clamp(0, v.text.length), end = sel.end.clamp(0, v.text.length);
  c.value = TextEditingValue(
    text: v.text.replaceRange(start, end, text),
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}

/// A row of letter buttons that insert into the focused text field.
class AccentBar extends StatelessWidget {
  const AccentBar({super.key, required this.letters, required this.onInsert});

  final List<String> letters;
  final ValueChanged<String> onInsert;

  @override
  Widget build(BuildContext context) {
    if (letters.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final mono = isMonochrome(scheme);
    return TextFieldTapRegion(
      child: SizedBox(
        height: 48,
        child: ListView(
          key: const ValueKey('accent-bar'),
          scrollDirection: Axis.horizontal,
          children: [
            for (final l in letters)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Semantics(
                  button: true,
                  label: 'Insert $l',
                  excludeSemantics: true,
                  child: Material(
                    color: mono ? kBwWhite : scheme.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: mono ? kBwBlack : scheme.outlineVariant, width: mono ? kBwBorder : 1),
                    ),
                    child: InkWell(
                      key: ValueKey('accent-$l'),
                      borderRadius: BorderRadius.circular(10),
                      canRequestFocus: false,
                      onTap: () => onInsert(l),
                      onLongPress: () => onInsert(l.toUpperCase()),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Text(
                            l,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: scheme.onSurface),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A text field for a typed answer, with the accent bar above it.
///
/// Reports the text through [onChanged] on every change, including inserts
/// from the accent bar (a plain `TextField.onChanged` misses those).
class TypedAnswerField extends StatefulWidget {
  const TypedAnswerField({
    super.key,
    required this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.hintText,
    this.prefixText,
    this.helperText,
    this.multiline = false,
    this.autofocus = false,
    this.showAccentBar = true,
    this.fieldKey = const ValueKey('answer-input'),
    this.style,
  });

  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;
  final bool enabled;
  final String? hintText;

  /// Fixed text before the input (the stem of a conjugation pick).
  final String? prefixText;
  final String? helperText;
  final bool multiline;
  final bool autofocus;
  final bool showAccentBar;
  final Key fieldKey;
  final TextStyle? style;

  @override
  State<TypedAnswerField> createState() => _TypedAnswerFieldState();
}

class _TypedAnswerFieldState extends State<TypedAnswerField> {
  final _controller = TextEditingController();
  final _node = FocusNode(debugLabel: 'typed-answer');
  String _last = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    if (widget.autofocus && widget.enabled) focusTypedAnswerSoon(this, _node);
  }

  void _changed() {
    if (_controller.text == _last) return;
    _last = _controller.text;
    widget.onChanged(_last);
  }

  @override
  void dispose() {
    _controller.dispose();
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final letters = widget.showAccentBar && widget.enabled ? AccentLetters.of(context) : const <String>[];
    final field = TextField(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _node,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      autocorrect: false,
      enableSuggestions: false,
      style: widget.style,
      keyboardType: widget.multiline ? TextInputType.text : null,
      minLines: widget.multiline ? 2 : 1,
      maxLines: widget.multiline ? 4 : 1,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: widget.hintText ?? 'Type your answer',
        prefixText: widget.prefixText,
        helperText: widget.helperText,
      ),
      onSubmitted: (_) => widget.onSubmitted?.call(),
    );
    if (letters.isEmpty) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AccentBar(letters: letters, onInsert: (l) => insertAtCursor(_controller, l)),
        const SizedBox(height: 8),
        field,
      ],
    );
  }
}
