import 'package:flutter/material.dart';

import '../../../core/core.dart';
import '../../theme/bw_skin.dart';

export 'choice_grid.dart' show ChoiceGrid, ChoiceOption;
export 'exercise_layout.dart' show ExerciseLayout;

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
    this.onSelect,
    this.result,
    this.keys,
    this.reduceMotion = false,
  });

  final E exercise;
  final ValueChanged<Answer?> onChanged;
  final ValueChanged<Answer>? onSubmit;

  /// Asks the player to check the current draft (e.g. Enter in a text field).
  final VoidCallback? onCheck;

  /// A tap selected something that doesn't change the draft answer (a match
  /// pairs card): the player plays the select tick. Taps that change the
  /// draft already arrive through [onChanged].
  final VoidCallback? onSelect;
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
///
/// In black & white everything is black on white: right and wrong are told
/// apart by [markIcon], labels, border weight and strikethrough instead.
class FeedbackColors {
  FeedbackColors.of(BuildContext context) : _scheme = Theme.of(context).colorScheme;
  final ColorScheme _scheme;

  /// Black & white (e-ink) theme.
  bool get mono => isMonochrome(_scheme);

  // The skin's leaf tones (tosk: leaf dark / leaf tint, leaf light / leaf night).
  Color get correct => mono ? kBwBlack : _scheme.secondary;
  Color get correctContainer => mono ? kBwWhite : _scheme.secondaryContainer;
  Color get onCorrectContainer => mono ? kBwBlack : _scheme.onSecondaryContainer;
  Color get wrong => _scheme.error;
  Color get wrongContainer => _scheme.errorContainer;
  Color get onWrongContainer => _scheme.onErrorContainer;
}

enum OptionState {
  idle,
  selected,
  correct,
  wrong,
  dimmed,

  /// A right word in the wrong place (a sentence answer's tile after checking).
  misplaced,
}

/// The mark shown on a right or wrong option in black & white (✓ / ✗).
IconData? markIcon(OptionState s) => switch (s) {
  OptionState.correct => Icons.check,
  OptionState.wrong => Icons.close,
  OptionState.misplaced => Icons.swap_horiz,
  _ => null,
};

/// Colors, border width and text style of an option or tile in [state]. In
/// black & white: idle is outlined (2 px), selected is inverted (black fill,
/// white text), correct has a 3.5 px border, bold text and ✓, wrong a 2 px
/// border, struck-through text and ✗, dimmed is the one gray, misplaced a
/// 2 px dashed-look border (dotted underline) and ⇄.
({Color bg, Color border, Color fg, double width, TextStyle style}) optionLook(
  BuildContext context,
  OptionState state, {
  required TextStyle? base,
}) {
  final scheme = Theme.of(context).colorScheme;
  final fb = FeedbackColors.of(context);
  final b = base ?? const TextStyle();
  if (fb.mono) {
    return switch (state) {
      OptionState.idle => (
        bg: kBwWhite,
        border: kBwBlack,
        fg: kBwBlack,
        width: kBwBorder,
        style: b.copyWith(color: kBwBlack),
      ),
      OptionState.selected => (
        bg: kBwBlack,
        border: kBwBlack,
        fg: kBwWhite,
        width: kBwBorder,
        style: b.copyWith(color: kBwWhite, fontWeight: FontWeight.w700),
      ),
      OptionState.correct => (
        bg: kBwWhite,
        border: kBwBlack,
        fg: kBwBlack,
        width: 3.5,
        style: b.copyWith(color: kBwBlack, fontWeight: FontWeight.w800),
      ),
      OptionState.wrong => (
        bg: kBwWhite,
        border: kBwBlack,
        fg: kBwBlack,
        width: kBwBorder,
        style: b.copyWith(
          color: kBwBlack,
          decoration: TextDecoration.lineThrough,
          decorationColor: kBwBlack,
          decorationThickness: 2,
        ),
      ),
      OptionState.dimmed => (
        bg: kBwWhite,
        border: kBwGray,
        fg: kBwGray,
        width: kBwBorder,
        style: b.copyWith(color: kBwGray),
      ),
      OptionState.misplaced => (
        bg: kBwWhite,
        border: kBwBlack,
        fg: kBwBlack,
        width: kBwBorder,
        style: b.copyWith(
          color: kBwBlack,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: kBwBlack,
          decorationThickness: 2,
        ),
      ),
    };
  }
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
    OptionState.misplaced => (scheme.tertiaryContainer, scheme.tertiary, scheme.onTertiaryContainer),
  };
  final style = state == OptionState.misplaced
      ? b.copyWith(
          color: fg,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: fg,
          decorationThickness: 2,
        )
      : b.copyWith(color: fg);
  return (bg: bg, border: border, fg: fg, width: state == OptionState.idle ? 1.2 : 2, style: style);
}

/// A tappable answer option with an optional shortcut number.
///
/// Options usually sit in a `ChoiceGrid`, which sizes them (equal tiles) and
/// picks [textScale] so no word breaks; the layout constants below are what
/// it measures against.
class OptionButton extends StatelessWidget {
  const OptionButton({
    super.key,
    required this.label,
    this.number,
    this.state = OptionState.idle,
    this.onTap,
    this.large = false,
    this.center = false,
    this.labelWidget,
    this.textScale = 1,
  });

  /// Horizontal padding on each side of the content.
  static const double hPadding = 12;

  /// The number badge and the gap after it.
  static const double badgeSize = 22, badgeGap = 10;

  /// The black & white ✓ / ✗ mark and the gap before it.
  static const double markSize = 22, markGap = 6;

  /// Minimum height: a comfortable tap target.
  static const double minHeight = 48;

  /// The label's base text style (before the state's color and weight).
  static TextStyle? baseStyle(BuildContext context, {bool large = false}) {
    final text = Theme.of(context).textTheme;
    return large ? text.titleMedium : text.bodyLarge;
  }

  final String label;

  /// Multiplies the label's font size (a `ChoiceGrid` shrinks every label of
  /// a grid a little so its longest word fits on one line).
  final double textScale;

  /// Replaces the label text (e.g. a sentence with tappable words); [label]
  /// still names the option for semantics.
  final Widget? labelWidget;
  final int? number;
  final OptionState state;
  final VoidCallback? onTap;
  final bool large;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final look = optionLook(context, state, base: baseStyle(context, large: large));
    final (bg, border, fg) = (look.bg, look.border, look.fg);
    final labelStyle = textScale == 1
        ? look.style
        : look.style.copyWith(fontSize: (look.style.fontSize ?? 14) * textScale);
    final mark = FeedbackColors.of(context).mono ? markIcon(state) : null;
    return Semantics(
      button: true,
      selected: state == OptionState.selected,
      hint: switch (state) {
        OptionState.correct => 'correct answer',
        OptionState.wrong => 'wrong answer',
        OptionState.misplaced => 'right word, wrong place',
        _ => null,
      },
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: look.width),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            // At least 48 px tall: a comfortable tap target.
            constraints: const BoxConstraints(minHeight: minHeight),
            padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: large ? 14 : 10),
            child: Row(
              children: [
                if (number != null) ...[
                  Container(
                    width: badgeSize,
                    height: badgeSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$number', style: text.labelSmall?.copyWith(color: fg)),
                  ),
                  const SizedBox(width: badgeGap),
                ],
                Expanded(
                  child:
                      labelWidget ??
                      Text(label, textAlign: center ? TextAlign.center : TextAlign.start, style: labelStyle),
                ),
                if (mark != null) ...[const SizedBox(width: markGap), Icon(mark, size: markSize, color: fg)],
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
    final mono = FeedbackColors.of(context).mono;
    final look = optionLook(context, state, base: Theme.of(context).textTheme.bodyLarge);
    final mark = mono ? markIcon(state) : null;
    // At least 48 x 48 px: a comfortable tap target even for one-letter tiles.
    final child = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(label, style: hidden ? look.style.copyWith(color: Colors.transparent) : look.style),
              ),
              if (mark != null && !hidden) ...[const SizedBox(width: 4), Icon(mark, size: 18, color: look.fg)],
            ],
          ),
        ),
      ),
    );
    if (hidden) {
      // The tile's empty slot: a gray outline in black & white.
      return Container(
        decoration: BoxDecoration(
          color: mono ? kBwWhite : scheme.surfaceContainerHighest,
          border: mono ? Border.all(color: kBwGray, width: kBwBorder) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ExcludeSemantics(child: child),
      );
    }
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: state == OptionState.selected,
      hint: switch (state) {
        OptionState.correct => 'correct',
        OptionState.wrong => 'wrong',
        OptionState.misplaced => 'right word, wrong place',
        _ => null,
      },
      child: Material(
        color: look.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: look.border, width: mono ? look.width : 1.2),
        ),
        elevation: state == OptionState.idle && !mono ? 1 : 0,
        child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: child),
      ),
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
