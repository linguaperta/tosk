import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../theme/skill_icons.dart';
import '../theme/bw_skin.dart';
import '../theme/skin.dart';
import 'branch_style.dart';
import 'ink_art.dart';
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
/// states, the strength ring, the sparkly metal tiers), the skill's icon,
/// the title and the days since practice.
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
    this.twinkle = false,
    this.branchStyle = BranchStyle.defaults,
    this.onTap,
    this.onLongPress,
    this.labelBackground,
  });

  final Skill skill;
  final String title;
  final SkillStats stats;
  final MapStyle style;

  /// Size of the node box (stone, ring and rays).
  final double diameter;
  final DateTime now;
  final bool reduceMotion;

  /// Animate the medal twinkles (motion on; off under `flutter test`).
  final bool twinkle;

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

class _SkillNodeState extends State<SkillNode> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  AnimationController? _sparkle;

  bool get _wantsSparkle => widget.twinkle && !widget.reduceMotion && widget.stats.tier.index >= MapTier.bronze.index;

  @override
  void initState() {
    super.initState();
    _syncSparkle();
  }

  @override
  void didUpdateWidget(SkillNode old) {
    super.didUpdateWidget(old);
    _syncSparkle();
  }

  void _syncSparkle() {
    if (_wantsSparkle) {
      _sparkle ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
    } else {
      _sparkle?.dispose();
      _sparkle = null;
    }
  }

  @override
  void dispose() {
    _sparkle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final theme = Theme.of(context);
    final stats = w.stats;
    final locked = stats.tier == MapTier.locked;
    final mono = w.style.monochrome;
    final fading = !locked && stats.practiced && stats.decay >= kMonoFadingDecay;
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
    ].join(', ');

    final iconColor = mono
        ? (locked ? kBwGray : kBwBlack)
        : locked
            ? w.style.ink.bark.withValues(alpha: 0.7)
            : w.style.onNode;

    Widget stonePaint(double? phase) => CustomPaint(
      size: Size.square(box),
      painter: NodePainter(
        tier: stats.tier,
        ink: w.style.ink,
        strength: stats.strength,
        style: w.branchStyle,
        decay: stats.decay,
        twinkle: phase,
        seed: seed,
        monochrome: mono,
        dashedRing: mono && fading,
      ),
    );

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
              width: box,
              height: box,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (_sparkle case final ctl?)
                    AnimatedBuilder(animation: ctl, builder: (_, _) => stonePaint(ctl.value))
                  else
                    stonePaint(null),
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

/// Decay from which a skill counts as fading (dashed ring in black & white).
const double kMonoFadingDecay = 0.35;
