import 'package:flutter/material.dart';

import '../../progression/progression.dart';
import 'progression_colors.dart';

/// A round tier icon: lock, empty ring, started ring, or a bronze/silver/gold medal.
class TierBadge extends StatelessWidget {
  const TierBadge({
    super.key,
    required this.tier,
    this.size = 32,
    this.reduceMotion = false,
    this.showLabel = false,
  });

  final SkillTier tier;
  final double size;
  final bool reduceMotion;

  /// Shows the tier name under the icon.
  final bool showLabel;

  static IconData iconFor(SkillTier tier) => switch (tier) {
        SkillTier.locked => Icons.lock_outline,
        SkillTier.available => Icons.radio_button_unchecked,
        SkillTier.started => Icons.trip_origin,
        SkillTier.bronze || SkillTier.silver || SkillTier.gold => Icons.military_tech,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = ProgressionColors.tier(tier, cs);
    final medal = tier.isMedal;
    final circle = Container(
      key: ValueKey(tier),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: medal ? color.withValues(alpha: 0.18) : Colors.transparent,
        border: Border.all(color: color, width: medal ? 2 : 1.5),
      ),
      alignment: Alignment.center,
      child: Icon(iconFor(tier), size: size * 0.62, color: color),
    );
    final icon = reduceMotion
        ? circle
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: circle,
          );
    return Semantics(
      label: '${tierLabel(tier)} tier',
      excludeSemantics: true,
      child: showLabel
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 4),
                Text(tierLabel(tier), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
              ],
            )
          : icon,
    );
  }
}
