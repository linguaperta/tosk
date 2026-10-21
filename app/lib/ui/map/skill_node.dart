import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../theme/skill_icons.dart';
import '../theme/bw_skin.dart';
import '../theme/skin.dart';
import 'branch_style.dart';
import 'ink_art.dart';
import 'map_labels.dart';
import 'map_raster.dart';
import 'node_painter.dart';
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

/// One skill on the map: a storybook stone medallion ([NodePainter]: the six
/// states, the strength ring, the sparkly metal tiers, the cracks of decay),
/// the skill's icon, the title and the days since practice.
///
/// The node itself never animates its medal: with motion on, the map paints
/// every moving twinkle on one shared layer ([paintTwinkles] false here), so
/// there is no controller per node and a node's stone paints once.
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
    this.paintTwinkles = true,
    this.branchStyle = BranchStyle.defaults,
    this.onTap,
    this.onLongPress,
    this.labelBackground,
    this.semanticsLabel,
  });

  /// Replaces the node's semantics label (a topic map's root: "Back to …").
  final String? semanticsLabel;

  final Skill skill;
  final String title;
  final SkillStats stats;
  final MapStyle style;

  /// Size of the node box (stone, ring and rays).
  final double diameter;
  final DateTime now;
  final bool reduceMotion;

  /// Paint the medal's twinkles on the stone (static); false when the map's
  /// shared sparkle layer animates them.
  final bool paintTwinkles;

  /// The art kit's spec (sparkle positions, gleam, extent).
  final BranchStyle branchStyle;
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
    final days = stats.daysSince(w.now);
    final box = math.max(w.diameter, 48.0);
    final stone = NodePainter.stoneRadius(box, w.branchStyle.extent) * 2;
    final seed = inkSeed(w.skill.id);

    final semantics = [
      w.title,
      if (locked) 'locked',
      if (stats.practiced) 'strength ${(stats.strength * 100).round()} percent',
      if (days != null) 'practiced ${daysAgoLabel(days)}',
      if (stats.tier.index >= MapTier.bronze.index) stats.tier.name,
      if (stats.practiced && stats.decay >= kMonoFadingDecay) 'fading',
      if (NodePainter.crackLevel(stats.tier, stats.decay, w.branchStyle) >= 0.5) 'cracked',
    ].join(', ');

    final iconColor = nodeIconColor(w.style, stats.tier);

    // The stone is drawn once into an image (it is thousands of ink ops) and
    // then just blitted; it reaches past the box (sparkles, rays, laurel,
    // falling fragments: at most 0.14 of the box over all tiers and decays).
    final stonePaint = CachedPaint(
      key: const ValueKey('skill-stone'),
      size: Size.square(box),
      overflow: box * 0.2,
      painter: NodePainter(
        tier: stats.tier,
        ink: w.style.ink,
        strength: stats.strength,
        style: w.branchStyle,
        decay: stats.decay,
        seed: seed,
        monochrome: mono,
        paintTwinkles: w.paintTwinkles,
      ),
    );

    return Semantics(
      button: true,
      label: w.semanticsLabel ?? semantics,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _pressed ? 0.92 : 1,
            duration: w.reduceMotion ? Duration.zero : const Duration(milliseconds: 120),
            child: SizedBox(
              width: box,
              height: box,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  stonePaint,
                  Material(
                    type: MaterialType.transparency,
                    child: InkResponse(
                      key: ValueKey('skill-node-${w.skill.id}'),
                      customBorder: const CircleBorder(),
                      radius: box / 2,
                      onTap: w.onTap,
                      onLongPress: w.onLongPress,
                      onSecondaryTap: w.onLongPress,
                      onHighlightChanged: (v) => setState(() => _pressed = v),
                      child: SizedBox.square(
                        dimension: box,
                        child: Icon(skillIcon(w.skill), size: stone * 0.5, color: iconColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          // The title (at most two lines) and the days chip under it: the
          // map reserves their height under every stone (`MapTextMetrics`),
          // so they never overlap each other or the next row.
          _LabelBox(
            color: w.labelBackground,
            child: Text(
              w.title,
              key: ValueKey('skill-title-${w.skill.id}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              textWidthBasis: TextWidthBasis.longestLine,
              style: mapNodeTitleStyle(theme)?.copyWith(
                color: locked ? theme.colorScheme.outline : theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (days != null)
            _LabelBox(
              color: w.labelBackground,
              child: Text(
                daysAgoShort(days),
                key: ValueKey('skill-days-${w.skill.id}'),
                maxLines: 1,
                style: mapNodeChipStyle(theme)?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
          child: Padding(padding: kMapLabelPadding, child: child),
        );
}

/// The skill icon's colour on a stone of [tier]: bark on the light stones,
/// cream on the dark copper of bronze (so it keeps its contrast), lighter
/// when locked; black (gray when locked) in black & white.
Color nodeIconColor(MapStyle style, MapTier tier) {
  final locked = tier == MapTier.locked;
  if (style.monochrome) return locked ? kBwGray : kBwBlack;
  if (locked) return style.ink.bark.withValues(alpha: 0.7);
  if (tier == MapTier.bronze) return style.ink.cream;
  return style.onNode;
}

/// Decay from which a skill counts as fading (its semantics label says so;
/// the stone shows cracks from `Cracks.start` on, in colour and black & white).
const double kMonoFadingDecay = 0.35;
