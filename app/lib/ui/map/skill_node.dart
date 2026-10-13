import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../slots/progression_slots.dart';
import '../theme/skill_icons.dart';
import '../theme/bw_skin.dart';
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
    this.labelBackground,
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

  /// Background behind the title (the band color), so prerequisite edges
  /// running behind a node never cross its text.
  final Color? labelBackground;

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
    final mono = w.style.monochrome;
    final base = locked ? w.style.lockedColor : w.style.nodeColor(w.skill.kind);
    // Black & white: white nodes with a black border; locked ones gray, and a
    // fading skill gets a dashed border instead of a washed-out color.
    final fill = mono ? kBwWhite : (locked ? base.withValues(alpha: 0.45) : fadeColor(base, stats.decay));
    final fading = mono && !locked && stats.practiced && stats.decay >= kMonoFadingDecay;
    final ShapeBorder shape = mono
        ? CircleBorder(side: fading ? BorderSide.none : BorderSide(color: locked ? kBwGray : kBwBlack, width: 2.5))
        : w.style.nodeShape;
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
      if (stats.practiced && stats.decay >= kMonoFadingDecay) 'fading',
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
                      dottedTrack: mono,
                      strength: stats.strength,
                      track: w.style.ringTrack,
                      color: stats.tier.index >= MapTier.bronze.index
                          ? w.style.tierColor(stats.tier)
                          : w.style.ringColor,
                    ),
                  ),
                  if (fading)
                    CustomPaint(
                      key: const ValueKey('node-dashed'),
                      size: Size.square(inner),
                      painter: const DashedCirclePainter(color: kBwBlack, width: 2.5),
                    ),
                  Material(
                    color: fading ? Colors.transparent : fill,
                    shape: shape,
                    elevation: locked || mono ? 0 : 2,
                    child: InkResponse(
                      key: ValueKey('skill-node-${w.skill.id}'),
                      customBorder: shape,
                      onTap: w.onTap,
                      onLongPress: w.onLongPress,
                      onSecondaryTap: w.onLongPress,
                      onHighlightChanged: (v) => setState(() => _pressed = v),
                      child: SizedBox.square(
                        dimension: inner,
                        child: Icon(
                          skillIcon(w.skill),
                          size: inner * 0.5,
                          color: mono && locked ? kBwGray : w.style.onNode,
                        ),
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
            child: _LabelBox(
              color: w.labelBackground,
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
          ),
          if (days != null)
            _LabelBox(
              color: w.labelBackground,
              child: Text(
                daysAgoShort(days),
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _LabelBox extends StatelessWidget {
  const _LabelBox({required this.color, required this.child});
  final Color? color;
  final Widget child;

  @override
  Widget build(BuildContext context) => color == null
      ? child
      : DecoratedBox(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: child),
        );
}

/// Decay from which a skill counts as fading in black & white (dashed border).
const double kMonoFadingDecay = 0.35;

/// A dashed circle border (fading skills in black & white).
class DashedCirclePainter extends CustomPainter {
  const DashedCirclePainter({required this.color, this.width = 2.5, this.dashes = 16});
  final Color color;
  final double width;
  final int dashes;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    canvas.drawCircle(rect.center, rect.width / 2, Paint()..color = kBwWhite);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    final step = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * step, step * 0.55, false, p);
    }
  }

  @override
  bool shouldRepaint(DashedCirclePainter old) => old.color != color || old.width != width || old.dashes != dashes;
}

/// Track plus an arc for strength 0..1, starting at 12 o'clock. With
/// [dottedTrack] (black & white) the track is a ring of dots and the arc solid.
class StrengthRingPainter extends CustomPainter {
  const StrengthRingPainter({
    required this.strength,
    required this.track,
    required this.color,
    this.width = 4,
    this.dottedTrack = false,
  });
  final double strength;
  final Color track;
  final Color color;
  final double width;
  final bool dottedTrack;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    if (dottedTrack) {
      final dots = Paint()..color = track;
      const n = 36;
      for (var i = 0; i < n; i++) {
        final a = 2 * math.pi * i / n;
        canvas.drawCircle(rect.center + Offset(math.cos(a), math.sin(a)) * (rect.width / 2), width * 0.22, dots);
      }
    } else {
      canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    }
    final s = strength.clamp(0.0, 1.0);
    if (s > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * s, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(StrengthRingPainter old) =>
      old.strength != strength ||
      old.track != track ||
      old.color != color ||
      old.width != width ||
      old.dottedTrack != dottedTrack;
}
