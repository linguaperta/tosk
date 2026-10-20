/// The storybook medals outside the map (v0.7.1): [TierMedal], a tier as
/// the map paints it (with the cracks of a dropped tier), and
/// [MedalCelebration], the promotion moment at the end of a lesson.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../progression/progression.dart';
import '../map/ink_art.dart';
import '../map/node_painter.dart';
import '../map/skill_stats.dart';
import '../theme/bw_skin.dart';
import '../theme/skin.dart';
import '../theme/tosk_palette.dart';
import 'progression_colors.dart';
import 'tier_badge.dart' show medalLetter;

/// The map's ink for [cs]: black & white, the dark theme or the storybook paper.
MapInk medalInk(ColorScheme cs) =>
    isMonochrome(cs) ? kBwInk : (cs.brightness == Brightness.dark ? MapInk.night : MapInk.storybook);

MapTier _mapTier(SkillTier t) => MapTier.values.byName(t.name);

/// Decay drawn on a medal whose tier just dropped (cracked, a chip out).
const double kDroppedTierDecay = 0.7;

/// A medal tier painted like its map node: bronze matte, silver shiny, gold
/// radiant with a laurel; [decay] cracks it. In black & white the medal's
/// letter (B, S, G) sits on the stone too, so it reads at any size.
class TierMedal extends StatelessWidget {
  const TierMedal({super.key, required this.tier, this.size = 32, this.decay = 0, this.seed = 7});

  final SkillTier tier;

  /// The box (stone, rays and twinkles).
  final double size;
  final double decay;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mono = isMonochrome(cs);
    final cracked = NodePainter.crackLevel(_mapTier(tier), decay) > 0;
    return Semantics(
      container: true,
      label: '${tierLabel(tier)} medal${cracked ? ', cracked' : ''}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: NodePainter(tier: _mapTier(tier), ink: medalInk(cs), strength: 0.6, decay: decay, seed: seed, monochrome: mono),
          child: mono && tier.isMedal
              ? Center(
                  // On a white disc, so the hatching never runs through the letter.
                  child: Container(
                    width: size * 0.36,
                    height: size * 0.36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: kBwWhite, shape: BoxShape.circle),
                    child: Text(
                      medalLetter(tier),
                      style: TextStyle(fontSize: size * 0.26, fontWeight: FontWeight.w900, color: kBwBlack, height: 1),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// The promotion moment on the session summary: the new medal pops in, a
/// shine sweeps across it and twinkling 4-point stars burst around it, then
/// it settles (about 1.9 s, once). With reduce motion or in black & white it
/// is the settled picture from the start: the medal with static stars.
class MedalCelebration extends StatefulWidget {
  const MedalCelebration({super.key, required this.change, required this.skillName, this.reduceMotion = false, this.size = 112});

  final TierChange change;
  final String skillName;
  final bool reduceMotion;

  /// The medal's box; the stars reach a little beyond it.
  final double size;

  /// How long the moment lasts.
  static const duration = Duration(milliseconds: 1900);

  @override
  State<MedalCelebration> createState() => _MedalCelebrationState();
}

class _MedalCelebrationState extends State<MedalCelebration> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = widget.reduceMotion || isMonochrome(Theme.of(context).colorScheme);
    if (still) {
      _controller?.dispose();
      _controller = null;
    } else {
      _controller ??= AnimationController(vsync: this, duration: MedalCelebration.duration)..forward();
    }
  }

  @override
  void didUpdateWidget(MedalCelebration old) {
    super.didUpdateWidget(old);
    if (widget.reduceMotion && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mono = isMonochrome(cs);
    final c = widget.change;
    final label = '${tierLabel(c.to)} medal';
    final box = Size(widget.size * 1.7, widget.size * 1.4);
    return Semantics(
      container: true,
      label: 'New medal: ${tierLabel(c.to)}, ${widget.skillName}',
      excludeSemantics: true,
      child: Column(
        key: const ValueKey('medal-celebration'),
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: box,
            painter: CelebrationPainter(
              progress: _controller ?? kAlwaysCompleteAnimation,
              tier: _mapTier(c.to),
              ink: medalInk(cs),
              monochrome: mono,
              medal: widget.size,
              seed: inkSeed(c.skillId),
            ),
          ),
          Text(label, textAlign: TextAlign.center, style: theme.textTheme.serifSection),
          const SizedBox(height: 2),
          Text(
            '${widget.skillName}, up from ${tierLabel(c.from)}',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Paints the promotion moment at [progress] 0..1 (1: settled): the medal
/// popping in (to full size by 0.3), a shine sweeping across it (0.25-0.75)
/// and eight twinkles bursting out one after another, four of which stay.
class CelebrationPainter extends CustomPainter {
  CelebrationPainter({
    required this.progress,
    required this.tier,
    required this.ink,
    required this.medal,
    this.monochrome = false,
    this.seed = 1,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final MapTier tier;
  final MapInk ink;
  final double medal;
  final bool monochrome;
  final int seed;

  static const _stars = 8;

  /// The burst: angle (deg), distance and size (units of the stone radius),
  /// when it pops (0..1) and how big it stays (0: it fades away).
  static List<({double angle, double dist, double size, double start, double rest})> burst(int seed) {
    final rnd = math.Random(seed);
    return [
      for (var k = 0; k < _stars; k++)
        (
          angle: -100.0 + k * 45 + (rnd.nextDouble() - 0.5) * 18,
          dist: 1.6 + rnd.nextDouble() * 0.3,
          size: 0.16 + rnd.nextDouble() * 0.12,
          start: 0.1 + k * 0.07,
          rest: k.isEven ? 0.75 : 0.0,
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value.clamp(0.0, 1.0);
    final c = size.center(Offset.zero);
    final r = NodePainter.stoneRadius(medal);
    final pop = t >= 0.3 ? 1.0 : 0.55 + 0.45 * Curves.easeOutBack.transform(t / 0.3);
    final sweep = t > 0.25 && t < 0.75 ? (t - 0.25) / 0.5 : null;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(pop);
    canvas.translate(-medal / 2, -medal / 2);
    NodePainter(tier: tier, ink: ink, strength: 1, seed: seed, monochrome: monochrome, sweep: sweep)
        .paint(canvas, Size.square(medal));
    canvas.restore();

    for (final s in burst(seed)) {
      final u = ((t - s.start) / 0.45).clamp(0.0, 1.0);
      if (u <= 0) continue;
      final scale = u >= 1 ? s.rest : math.sin(math.pi * u) * 1.25 * (1 - u) + s.rest * u;
      if (scale <= 0.02) continue;
      final a = s.angle * math.pi / 180;
      final at = c + Offset(math.cos(a), math.sin(a)) * (r * s.dist * (0.85 + 0.15 * u));
      paintTwinkle(canvas, at, r * s.size * scale, ink, rotate: (1 - u) * 0.8);
    }
  }

  @override
  bool shouldRepaint(CelebrationPainter old) =>
      old.progress != progress ||
      old.tier != tier ||
      old.ink != ink ||
      old.medal != medal ||
      old.monochrome != monochrome ||
      old.seed != seed;
}
