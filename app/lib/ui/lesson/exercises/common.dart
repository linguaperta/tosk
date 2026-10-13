import 'package:flutter/material.dart';

import '../../../core/core.dart';

/// Shortcut presses forwarded from the player to the current exercise widget
/// (desktop: digits pick options, Enter on an exercise without a draft = primary action).
class ExerciseKeys extends ChangeNotifier {
  ExerciseEvent? _last;
  ExerciseEvent? get last => _last;

  void digit(int n) {
    _last = ExerciseEvent.digit(n);
    notifyListeners();
  }

  void primary() {
    _last = const ExerciseEvent.primary();
    notifyListeners();
  }
}

class ExerciseEvent {
  const ExerciseEvent.digit(int this.digit) : isPrimary = false;
  const ExerciseEvent.primary() : digit = null, isPrimary = true;
  final int? digit;
  final bool isPrimary;
}

/// Base class of the 9 exercise widgets.
///
/// A widget reports its draft answer through [onChanged] (null while incomplete);
/// the player's Check button submits it. Self-submitting types (flashcard
/// self-grade, match pairs when all matched) call [onSubmit] directly. Once
/// [result] is set the widget shows feedback marks and ignores input.
abstract class ExerciseWidget<E extends Exercise> extends StatefulWidget {
  const ExerciseWidget({
    super.key,
    required this.exercise,
    required this.onChanged,
    this.onSubmit,
    this.onCheck,
    this.result,
    this.keys,
    this.reduceMotion = false,
  });

  final E exercise;
  final ValueChanged<Answer?> onChanged;
  final ValueChanged<Answer>? onSubmit;

  /// Asks the player to check the current draft (e.g. Enter in a text field).
  final VoidCallback? onCheck;
  final Result? result;
  final ExerciseKeys? keys;
  final bool reduceMotion;

  bool get locked => result != null;
}

/// Subscribes a state to [ExerciseWidget.keys].
mixin ExerciseKeysMixin<W extends ExerciseWidget> on State<W> {
  void onDigit(int n) {}
  void onPrimary() {}

  void _listener() {
    final e = widget.keys?.last;
    if (e == null || widget.locked) return;
    if (e.isPrimary) {
      onPrimary();
    } else {
      onDigit(e.digit!);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.keys?.addListener(_listener);
  }

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keys != widget.keys) {
      oldWidget.keys?.removeListener(_listener);
      widget.keys?.addListener(_listener);
    }
  }

  @override
  void dispose() {
    widget.keys?.removeListener(_listener);
    super.dispose();
  }
}

/// Colors for right/wrong marks.
class FeedbackColors {
  FeedbackColors.of(BuildContext context) : _scheme = Theme.of(context).colorScheme;
  final ColorScheme _scheme;
  bool get _dark => _scheme.brightness == Brightness.dark;

  Color get correct => _dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
  Color get correctContainer => _dark ? const Color(0xFF1E3A22) : const Color(0xFFDDF3DF);
  Color get onCorrectContainer => _dark ? const Color(0xFFC8EBC9) : const Color(0xFF0F3D14);
  Color get wrong => _scheme.error;
  Color get wrongContainer => _scheme.errorContainer;
  Color get onWrongContainer => _scheme.onErrorContainer;
}

enum OptionState { idle, selected, correct, wrong, dimmed }

/// A tappable answer option with an optional shortcut number.
class OptionButton extends StatelessWidget {
  const OptionButton({
    super.key,
    required this.label,
    this.number,
    this.state = OptionState.idle,
    this.onTap,
    this.large = false,
    this.center = false,
  });

  final String label;
  final int? number;
  final OptionState state;
  final VoidCallback? onTap;
  final bool large;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fb = FeedbackColors.of(context);
    final (Color bg, Color border, Color fg) = switch (state) {
      OptionState.idle => (scheme.surface, scheme.outlineVariant, scheme.onSurface),
      OptionState.selected => (scheme.secondaryContainer, scheme.secondary, scheme.onSecondaryContainer),
      OptionState.correct => (fb.correctContainer, fb.correct, fb.onCorrectContainer),
      OptionState.wrong => (fb.wrongContainer, fb.wrong, fb.onWrongContainer),
      OptionState.dimmed => (
        scheme.surface,
        scheme.outlineVariant.withValues(alpha: 0.5),
        scheme.onSurface.withValues(alpha: 0.45),
      ),
    };
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: state == OptionState.selected,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: state == OptionState.idle ? 1.2 : 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: large ? 14 : 10),
            child: Row(
              children: [
                if (number != null) ...[
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$number', style: text.labelSmall?.copyWith(color: fg)),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    label,
                    textAlign: center ? TextAlign.center : TextAlign.start,
                    style: (large ? text.titleMedium : text.bodyLarge)?.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A word tile (sentence builder, transform, grid bank, spot-the-error tokens).
class WordTile extends StatelessWidget {
  const WordTile({super.key, required this.label, this.onTap, this.state = OptionState.idle, this.hidden = false});
  final String label;
  final VoidCallback? onTap;
  final OptionState state;

  /// Keeps the tile's space but shows an empty slot (tile is in use elsewhere).
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fb = FeedbackColors.of(context);
    final (Color bg, Color border, Color fg) = switch (state) {
      OptionState.idle => (scheme.surface, scheme.outlineVariant, scheme.onSurface),
      OptionState.selected => (scheme.secondaryContainer, scheme.secondary, scheme.onSecondaryContainer),
      OptionState.correct => (fb.correctContainer, fb.correct, fb.onCorrectContainer),
      OptionState.wrong => (fb.wrongContainer, fb.wrong, fb.onWrongContainer),
      OptionState.dimmed => (scheme.surface, scheme.outlineVariant, scheme.onSurface.withValues(alpha: 0.4)),
    };
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: hidden ? Colors.transparent : fg),
      ),
    );
    if (hidden) {
      return Container(
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
        child: ExcludeSemantics(child: child),
      );
    }
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: border, width: 1.2),
      ),
      elevation: state == OptionState.idle ? 1 : 0,
      child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: child),
    );
  }
}

class InstructionText extends StatelessWidget {
  const InstructionText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

/// Muted secondary line (translation, hint).
class SubtleText extends StatelessWidget {
  const SubtleText(this.text, {super.key, this.italic = false, this.icon});
  final String text;
  final bool italic;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontStyle: italic ? FontStyle.italic : null,
    );
    if (icon == null) return Text(text, style: style);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

/// Option state for choice exercises: selection before checking, right/wrong after.
OptionState choiceState({
  required int index,
  required int? selected,
  required int correctIndex,
  required Result? result,
}) {
  if (result == null) return index == selected ? OptionState.selected : OptionState.idle;
  if (index == correctIndex) return OptionState.correct;
  if (index == selected) return OptionState.wrong;
  return OptionState.dimmed;
}
