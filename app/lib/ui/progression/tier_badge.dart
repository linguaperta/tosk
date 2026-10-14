import 'package:flutter/material.dart';

import '../../progression/progression.dart';
import '../theme/bw_skin.dart';
import 'progression_colors.dart';

/// B, S or G: the medal letter used in black & white.
String medalLetter(SkillTier tier) => switch (tier) {
  SkillTier.bronze => 'B',
  SkillTier.silver => 'S',
  SkillTier.gold => 'G',
  _ => '',
};

/// Rings around the letter in black & white: 1 bronze, 2 silver, 3 gold.
int medalRings(SkillTier tier) => switch (tier) {
  SkillTier.bronze => 1,
  SkillTier.silver => 2,
  SkillTier.gold => 3,
  _ => 0,
};

/// Concentric black rings on white (black & white medals).
class MedalRingsPainter extends CustomPainter {
  const MedalRingsPainter({required this.rings});
  final int rings;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = kBwWhite);
    final stroke = (r * 0.12).clamp(1.2, 2.5);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = kBwBlack;
    for (var i = 0; i < rings; i++) {
      canvas.drawCircle(c, r - stroke / 2 - i * stroke * 1.7, p);
    }
  }

  @override
  bool shouldRepaint(MedalRingsPainter old) => old.rings != rings;
}

/// A round tier icon: lock, empty ring, started ring, or a bronze/silver/gold
/// medal (in black & white: the letter B, S or G inside 1, 2 or 3 rings).
class TierBadge extends StatelessWidget {
  const TierBadge({super.key, required this.tier, this.size = 32, this.reduceMotion = false, this.showLabel = false});

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
    final mono = isMonochrome(cs);
    final circle = mono && medal
        ? SizedBox(
            key: ValueKey(tier),
            width: size,
            height: size,
            child: CustomPaint(
              painter: MedalRingsPainter(rings: medalRings(tier)),
              child: Center(
                child: Text(
                  medalLetter(tier),
                  style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w900, color: kBwBlack, height: 1),
                ),
              ),
            ),
          )
        : Container(
            key: ValueKey(tier),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: medal ? color.withValues(alpha: 0.18) : (mono ? kBwWhite : Colors.transparent),
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
