import 'package:flutter/material.dart';

import '../theme/bw_skin.dart';

/// The map's actions in a compact bar under the map (the Scaffold's bottom
/// bar, so the map's viewport ends above it and no node is ever covered):
/// "Review mistakes (N)" while mistakes are open, "What's fading" once
/// something was practiced, and on long maps "Jump to current unit". They
/// used to float over the map and hid skill nodes on phones.
///
/// Buttons are at least 48 px tall; labels wrap to two lines on narrow
/// phones rather than being cut. Black & white: white with a 2 px rule on
/// top, a black "Review mistakes" button, outlined others.
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

  Widget _label(String text) => Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center);

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
          child: Tooltip(
            message: 'Practice your open mistakes',
            child: FilledButton.tonalIcon(
              key: const ValueKey('mistakes-button'),
              style: FilledButton.styleFrom(
                minimumSize: _minSize,
                backgroundColor: bw ? null : scheme.tertiaryContainer,
                foregroundColor: bw ? null : scheme.onTertiaryContainer,
              ),
              onPressed: mistakes,
              icon: const Icon(Icons.replay),
              label: _label('Review mistakes ($mistakeCount)'),
            ),
          ),
        ),
      if (fading != null)
        Expanded(
          child: Tooltip(
            message: 'Practice what you are forgetting',
            child: OutlinedButton.icon(
              key: const ValueKey('fading-button'),
              style: OutlinedButton.styleFrom(minimumSize: _minSize),
              onPressed: fading,
              icon: const Icon(Icons.restore),
              label: _label("What's fading"),
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
