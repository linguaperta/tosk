/// Slots where the progression phase plugs its widgets in (`lib/ui/progression/`).
///
/// Each slot renders nothing (or a minimal default) for now. At integration,
/// replace the slot body with the progression widget; the screens that host the
/// slots don't need to change.
library;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../map/skill_stats.dart';
import '../theme/skin.dart';

/// Top of the skill map: XP / level bar and the streak heatmap.
class MapHeaderSlot extends StatelessWidget {
  const MapHeaderSlot({super.key});

  // TODO(integration): progression's level bar + streak heatmap.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Tier badge on a map node. The default draws a simple medal / lock.
class TierBadgeSlot extends StatelessWidget {
  const TierBadgeSlot({super.key, required this.tier, required this.style, this.size = 22});
  final MapTier tier;
  final MapStyle style;
  final double size;

  // TODO(integration): may be swapped for progression's tier badge widget.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final IconData? icon = switch (tier) {
      MapTier.locked => Icons.lock,
      MapTier.bronze || MapTier.silver || MapTier.gold => Icons.workspace_premium,
      MapTier.started => Icons.play_arrow_rounded,
      MapTier.available => null,
    };
    if (icon == null) return SizedBox(width: size, height: size);
    final color = style.tierColor(tier);
    return Semantics(
      label: tier.name,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tier == MapTier.locked || tier == MapTier.started ? scheme.surface : color,
          shape: BoxShape.circle,
          border: Border.all(color: tier == MapTier.locked ? style.lockedColor : color, width: 1.5),
        ),
        child: Icon(
          icon,
          size: size * 0.66,
          color: tier == MapTier.locked
              ? style.lockedColor
              : tier == MapTier.started
              ? color
              : Colors.white,
        ),
      ),
    );
  }
}

/// On the session summary: XP earned, words that improved, tier changes.
class SummaryProgressSlot extends StatelessWidget {
  const SummaryProgressSlot({super.key, required this.summary});
  final SessionSummary summary;

  // TODO(integration): progression's session summary card.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Above the non-stop player: combo multiplier and bonus-round HUD.
class NonStopHudSlot extends StatelessWidget {
  const NonStopHudSlot({super.key, required this.answered, required this.correct, this.lastCorrect});
  final int answered;
  final int correct;
  final bool? lastCorrect;

  // TODO(integration): progression's combo / bonus HUD.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// On the non-stop start screen: best run record.
class NonStopRecordSlot extends StatelessWidget {
  const NonStopRecordSlot({super.key});

  // TODO(integration): progression's best-run record.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
