import 'package:flutter/material.dart';

import '../theme/bw_skin.dart';

/// The map's actions in a compact bar under the map (the Scaffold's bottom
/// bar, so the map's viewport ends above it and no node is ever covered):
/// "Mistakes · N" while mistakes are open, "Fading" once something was
/// practiced, and on long maps "Jump to current unit". They used to float
/// over the map and hid skill nodes on phones.
///
/// Buttons are at least 48 px tall. The labels are short so they fit on one
/// line at 360 dp with text 1.3 (the mistakes button gets the larger
/// share); on narrower screens a label scales down a little
/// rather than being cut. The full wording ("Review mistakes (N)", "What's
/// fading") is in the semantics label and the tooltip. Black & white: white
/// with a 2 px rule on top, a black mistakes button, outlined others.
class MapActionBar extends StatelessWidget {
  const MapActionBar({super.key, required this.mistakeCount, this.onMistakes, this.onFading, this.onJump});

  final int mistakeCount;

  /// Null hides the button (no open mistakes).
  final VoidCallback? onMistakes;

  /// Null hides "What's fading" (nothing practiced yet).
  final VoidCallback? onFading;

  /// Null hides "Jump to current unit" (short maps).
  final VoidCallback? onJump;

  /// Whether the bar has anything to show.
  static bool shows({required bool mistakes, required bool fading, required bool jump}) => mistakes || fading || jump;

  static const _minSize = Size(48, 48);

  /// Tighter than the default (16 / 24), so the labels fit on small phones.
  static const _padding = EdgeInsets.symmetric(horizontal: 12);

  Widget _label(String text, String semantics) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(text, maxLines: 1, softWrap: false, semanticsLabel: semantics),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bw = isBw(context);
    final mistakes = onMistakes;
    final fading = onFading;
    final jump = onJump;
    final children = <Widget>[
      if (mistakes != null)
        Expanded(
          // The longer label gets more room.
          flex: fading != null ? 3 : 1,
          child: Tooltip(
            message: 'Practice your open mistakes',
            child: FilledButton.tonalIcon(
              key: const ValueKey('mistakes-button'),
              style: FilledButton.styleFrom(
                minimumSize: _minSize,
                padding: _padding,
                backgroundColor: bw ? null : scheme.tertiaryContainer,
                foregroundColor: bw ? null : scheme.onTertiaryContainer,
              ),
              onPressed: mistakes,
              icon: const Icon(Icons.replay),
              label: _label('Mistakes · $mistakeCount', 'Review mistakes ($mistakeCount)'),
            ),
          ),
        ),
      if (fading != null)
        Expanded(
          flex: mistakes != null ? 2 : 1,
          child: Tooltip(
            message: 'Practice what you are forgetting',
            child: OutlinedButton.icon(
              key: const ValueKey('fading-button'),
              style: OutlinedButton.styleFrom(minimumSize: _minSize, padding: _padding),
              onPressed: fading,
              icon: const Icon(Icons.restore),
              label: _label('Fading', "What's fading"),
            ),
          ),
        ),
      // Long maps: back to where the learner is (first unfinished unit).
      if (jump != null)
        IconButton.outlined(
          key: const ValueKey('jump-current-unit'),
          tooltip: 'Jump to current unit',
          constraints: BoxConstraints.tight(_minSize),
          onPressed: jump,
          icon: const Icon(Icons.my_location),
        ),
    ];
    final spaced = <Widget>[
      for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 8), children[i]],
    ];
    return DecoratedBox(
      key: const ValueKey('map-action-bar'),
      decoration: BoxDecoration(
        color: bw ? kBwWhite : scheme.surfaceContainerLow,
        border: Border(
          top: bw ? const BorderSide(color: kBwBlack, width: kBwBorder) : BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: spaced),
        ),
      ),
    );
  }
}
