import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../slots/progression_slots.dart';
import '../theme/skill_icons.dart';
import '../theme/skin.dart';
import 'skill_stats.dart';

/// Desaturates and lightens [color] by [amount] (0..1); used for fading skills.
Color fadeColor(Color color, double amount) {
  if (amount <= 0) return color;
  final hsl = HSLColor.fromColor(color);
  final a = amount.clamp(0.0, 1.0);
  return hsl
      .withSaturation(hsl.saturation * (1 - 0.85 * a))
      .withLightness((hsl.lightness + (0.75 - hsl.lightness) * 0.45 * a).clamp(0.0, 1.0))
      .toColor();
}

/// One skill on the map: strength ring, icon, tier badge, title and days since practice.
class SkillNode extends StatefulWidget {
  const SkillNode({
    super.key,
    required this.skill,
    required this.title,
    required this.stats,
    required this.style,
    required this.diameter,
    required this.now,
    this.reduceMotion = false,
    this.onTap,
    this.onLongPress,
  });

  final Skill skill;
  final String title;
  final SkillStats stats;
  final MapStyle style;

  /// Diameter of the ring.
  final double diameter;
  final DateTime now;
  final bool reduceMotion;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<SkillNode> createState() => _SkillNodeState();
}

class _SkillNodeState extends State<SkillNode> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final theme = Theme.of(context);
    final stats = w.stats;
    final locked = stats.tier == MapTier.locked;
    final base = locked ? w.style.lockedColor : w.style.nodeColor(w.skill.kind);
    final fill = locked ? base.withValues(alpha: 0.45) : fadeColor(base, stats.decay);
    final days = stats.daysSince(w.now);
    final ring = w.diameter;
    final inner = ring - 10;
    final badge = math.max(16.0, ring * 0.32);

    final semantics = [
      w.title,
      if (locked) 'locked',
      if (stats.practiced) 'strength ${(stats.strength * 100).round()} percent',
      if (days != null) 'practiced ${daysAgoLabel(days)}',
      if (stats.tier.index >= MapTier.bronze.index) stats.tier.name,
    ].join(', ');

    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _pressed ? 0.92 : 1,
            duration: w.reduceMotion ? Duration.zero : const Duration(milliseconds: 120),
            child: SizedBox(
              width: ring + badge * 0.3,
              height: ring,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size.square(ring),
                    painter: StrengthRingPainter(
                      strength: stats.strength,
                      track: w.style.ringTrack,
                      color: stats.tier.index >= MapTier.bronze.index
                          ? w.style.tierColor(stats.tier)
                          : w.style.ringColor,
                    ),
                  ),
                  Material(
                    color: fill,
                    shape: w.style.nodeShape,
                    elevation: locked ? 0 : 2,
                    child: InkResponse(
                      key: ValueKey('skill-node-${w.skill.id}'),
                      customBorder: w.style.nodeShape,
                      onTap: w.onTap,
                      onLongPress: w.onLongPress,
                      onSecondaryTap: w.onLongPress,
                      onHighlightChanged: (v) => setState(() => _pressed = v),
                      child: SizedBox.square(
                        dimension: inner,
                        child: Icon(skillIcon(w.skill), size: inner * 0.5, color: w.style.onNode),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: TierBadgeSlot(tier: stats.tier, style: w.style, size: badge, reduceMotion: w.reduceMotion),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: Text(
              w.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: locked ? theme.colorScheme.outline : theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (days != null)
            Text(
              daysAgoShort(days),
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// Track plus an arc for strength 0..1, starting at 12 o'clock.
class StrengthRingPainter extends CustomPainter {
  const StrengthRingPainter({required this.strength, required this.track, required this.color, this.width = 4});
  final double strength;
  final Color track;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    final s = strength.clamp(0.0, 1.0);
    if (s > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * s, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(StrengthRingPainter old) =>
      old.strength != strength || old.track != track || old.color != color || old.width != width;
}
