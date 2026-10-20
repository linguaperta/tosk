/// The skill node medallion in the storybook style (the Dart port of the
/// art kit's `node()`, following `assets/brand/branch-style.json`): a round
/// stone with wobbly ink rings, a shadow crescent of hatching, and one look
/// per state:
///
/// - locked: paper, hatched, one faint ring;
/// - available: cream, two rings and a sprouting leaflet;
/// - started: cream plus the strength ring (a dotted track, the filled part heavy);
/// - bronze: copper-brown and **matte**: a stippled face, two rings, one glint;
/// - silver: cool grey with a **shine**: cross-hatched, two bright diagonal
///   bands, three rings, two twinkles and a dot;
/// - gold: warm yellow and **radiant**: a polished face with the gleam arc,
///   three rings, rays over the top, a laurel round the bottom, four twinkles
///   and three dots.
///
/// The tiers differ in shape as much as in colour (texture, ring count, rays,
/// laurel, twinkle count), so they read in black & white and for colour-blind
/// learners. **Decay** cracks the stone ([CrackPattern]): hairline cracks from
/// the rim, more and longer as it fades, chips knocked out of the rim and,
/// from half way, a fragment breaking off; in colour the stone also pales a
/// little. In black & white every fill is white and the cracks are black.
///
/// With [twinkle] (0..1, a phase) the twinkles move as on the map; the map
/// itself paints its moving twinkles on one shared layer and passes
/// [paintTwinkles] false here, so a node's stone never repaints for them.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/skin.dart';
import 'branch_style.dart';
import 'ink_art.dart';
import 'medal_art.dart';
import 'skill_stats.dart';

class NodePainter extends CustomPainter {
  const NodePainter({
    required this.tier,
    required this.ink,
    required this.strength,
    this.style = BranchStyle.defaults,
    this.decay = 0,
    this.twinkle,
    this.seed = 4,
    this.monochrome = false,
    this.paintTwinkles = true,
    this.sweep,
  });

  final MapTier tier;
  final MapInk ink;
  final BranchStyle style;

  /// 0..1, the strength ring of a started skill.
  final double strength;

  /// 0..1, how faded the skill is: cracks the stone (see [Cracks]) and, in
  /// colour, pales it a little.
  final double decay;

  /// Animation phase 0..1 (null: static twinkles).
  final double? twinkle;
  final int seed;
  final bool monochrome;

  /// Paint the twinkles (false where a shared sparkle layer animates them).
  final bool paintTwinkles;

  /// 0..1: a shine sweeping across the stone (the promotion moment); null: none.
  final double? sweep;

  /// How many times any node was painted (for the map's repaint tests).
  static int debugPaintCount = 0;

  /// Radius of the stone for a node box of [diameter]: the sparkles reach
  /// `extent` × r (1.75 by the spec), so the stone takes a bit over half.
  static double stoneRadius(double diameter, [double extent = 1.75]) => diameter / (2 * math.max(1.2, extent)) * 1.3;

  /// The stone's base colour for [tier] (before fading).
  static Color baseColor(MapTier tier, MapInk ink) => switch (tier) {
    MapTier.locked => ink.paper,
    MapTier.available || MapTier.started => ink.cream,
    MapTier.bronze => ink.bronze,
    MapTier.silver => ink.silver,
    MapTier.gold => ink.gold,
  };

  /// The crack level (0..1) for [tier] at [decay]: locked and never-started
  /// skills don't crack.
  static double crackLevel(MapTier tier, double decay, [BranchStyle style = BranchStyle.defaults]) =>
      tier.index < MapTier.started.index ? 0 : style.cracks.level(decay.isNaN ? 0 : decay.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = stoneRadius(size.shortestSide, style.extent);
    if (r <= 2) return;
    debugPaintCount++;
    final hw = math.max(0.8, r * 0.035);
    final hatchOp = ink.hatchOpacity;
    final circle = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final inner = Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.78));
    final locked = tier == MapTier.locked;
    final metal = tier.index >= MapTier.bronze.index;

    var base = baseColor(tier, ink);
    final fade = decay.isNaN ? 0.0 : decay.clamp(0.0, 1.0);
    if (!monochrome && fade > 0 && !locked) base = Color.lerp(base, ink.paper, 0.35 * fade)!;
    final cracks = CrackPattern.build(crackLevel(tier, fade, style), seed, style.cracks);

    // Chips are clipped out of everything on the stone.
    canvas.save();
    if (cracks.chips.isNotEmpty) canvas.clipPath(cracks.clipOutside(c, r, Offset.zero & size));

    canvas.drawPath(circle, Paint()..color = base);

    switch (tier) {
      case MapTier.locked:
        hatchRegion(canvas, circle, ink.ink,
            angleDeg: 45, spacing: math.max(3, r * 0.14), width: hw, seed: seed, opacity: monochrome ? 1 : 0.45 * hatchOp);
      case MapTier.bronze:
        // Matte copper: a darker patina low on the left, a stippled face, no gleam.
        if (!monochrome) {
          final low = Path()
            ..moveTo(c.dx - r, c.dy - r * 0.1)
            ..lineTo(c.dx + r * 0.5, c.dy + r)
            ..lineTo(c.dx - r, c.dy + r)
            ..close();
          canvas.drawPath(Path.combine(PathOperation.intersect, circle, low), Paint()..color = Color.lerp(base, ink.ink, 0.22)!);
        }
        paintStipple(canvas, c, r, ink.ink.withValues(alpha: monochrome ? 1 : 0.5 * hatchOp), seed: seed);
      case MapTier.silver:
        hatchRegion(canvas, inner, ink.ink,
            angleDeg: 25, spacing: math.max(3, r * 0.17), width: hw, seed: seed, opacity: monochrome ? 0.9 : 0.25 * hatchOp);
        hatchRegion(canvas, inner, ink.ink,
            angleDeg: 115,
            spacing: math.max(3, r * 0.34),
            width: hw * 0.7,
            seed: seed + 5,
            opacity: monochrome ? 0.55 : 0.2 * hatchOp);
        // The shine: bright bands on the lit side, cutting through the hatching.
        paintShine(canvas, c, r, monochrome ? ink.paper : Color.lerp(base, Colors.white, 0.82)!.withValues(alpha: 0.9),
            edge: monochrome ? ink.ink : null);
      case MapTier.gold:
        // Polished: a warmer, lighter centre.
        if (!monochrome) {
          canvas.drawCircle(c, r * 0.62, Paint()..color = Color.lerp(base, Colors.white, 0.16)!);
        }
      case _:
        break;
    }

    // Shadow crescent on the lower left (not on locked: flat and quiet).
    if (!locked) {
      final wedge = Path()
        ..moveTo(c.dx - r, c.dy - r * 0.3)
        ..lineTo(c.dx + r * 0.3, c.dy + r)
        ..lineTo(c.dx - r, c.dy + r)
        ..close();
      final crescent = Path.combine(PathOperation.intersect, circle, wedge);
      hatchRegion(canvas, crescent, ink.ink,
          angleDeg: 40, spacing: math.max(2.6, r * 0.11), width: hw, seed: seed + 1, opacity: hatchOp);
    }

    // The gleam: a paper-coloured arc on polished metal (gold), catching the light.
    if (metal && !monochrome && style.gleam.tiers.contains(tier.name)) {
      final g = style.gleam;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * g.radius),
        g.from * math.pi / 180,
        (g.to - g.from) * math.pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, r * g.width)
          ..strokeCap = StrokeCap.round
          ..color = ink.paper.withValues(alpha: g.opacity),
      );
    }

    // The promotion's shine sweep.
    if (sweep case final t?) paintShineSweep(canvas, c, r, t, monochrome ? ink.paper : Colors.white);

    // Rings: the outer stone edge, then one or two inner rings by tier.
    inkRing(canvas, c, r, ink.ink, wmin: r * (locked ? 0.03 : 0.05), wmax: r * (locked ? 0.08 : 0.16), wobble: 0.3, seed: seed);
    if (!locked) {
      inkRing(canvas, c, r * 0.78, ink.ink, wmin: r * 0.035, wmax: r * 0.06, wobble: 0.25, seed: seed + 2);
    }
    if (tier == MapTier.silver || tier == MapTier.gold) {
      inkRing(canvas, c, r * 0.66, ink.ink, wmin: r * 0.03, wmax: r * 0.045, wobble: 0.2, seed: seed + 3);
    }

    // Decay: the crack lines, then the chips' broken edges and the falling piece.
    if (!cracks.isEmpty) cracks.paintLines(canvas, c, r, ink, monochrome: monochrome, seed: seed + 30);
    canvas.restore();
    if (!cracks.isEmpty) cracks.paintBreaks(canvas, c, r, ink, base, seed: seed + 30);

    // Started: the strength ring outside the stone.
    if (tier == MapTier.started) {
      final big = r * 1.24;
      final track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, r * 0.045)
        ..strokeCap = StrokeCap.round
        ..color = ink.ink;
      final dash = r * 0.08, gap = r * 0.16;
      final circumference = 2 * math.pi * big;
      final n = math.max(8, (circumference / (dash + gap)).floor());
      for (var i = 0; i < n; i++) {
        final a0 = 2 * math.pi * i / n;
        canvas.drawArc(Rect.fromCircle(center: c, radius: big), a0, dash / big, false, track);
      }
      final s = (strength.isNaN ? 0.0 : strength).clamp(0.02, 0.999);
      final a0 = -math.pi / 2, a1 = a0 + 2 * math.pi * s;
      final arc = Path()..addArc(Rect.fromCircle(center: c, radius: big), a0, a1 - a0);
      final line = Polyline.sample(arc, 2).smoothed();
      inkStroke(canvas, line, monochrome ? ink.ink : ink.leafDark, wmin: r * 0.16, wmax: r * 0.16, wobble: 0, seed: seed + 8);
      inkStroke(canvas, line, ink.ink, wmin: r * 0.05, wmax: r * 0.05, wobble: 0.2, seed: seed + 9);
      final end = c + Offset(math.cos(a1), math.sin(a1)) * big;
      canvas.drawCircle(end, r * 0.11, Paint()..color = ink.ink);
    }

    // Available: a sprouting leaflet, this one is ready to start.
    if (tier == MapTier.available) {
      paintSprout(canvas, c + Offset(r * 0.62, -r * 0.86), -50 * math.pi / 180, r / 60, ink);
    }

    // Sparkle: rays, laurel, dots and twinkles per tier (gold most, bronze a glint).
    if (metal) {
      final sp = style.sparkleFor(tier.name);
      if (sp.rays case final rays?) {
        void ray(double deg, double r1, int k) {
          final a = deg * math.pi / 180;
          final d = Offset(math.cos(a), math.sin(a));
          final path = Path()
            ..moveTo(c.dx + d.dx * r * rays.r0, c.dy + d.dy * r * rays.r0)
            ..lineTo(c.dx + d.dx * r * r1, c.dy + d.dy * r * r1);
          inkStroke(canvas, Polyline.sample(path, 2), ink.ink,
              wmin: r * rays.width, wmax: r * rays.width, wobble: 0, profile: 'in', seed: seed + k);
        }

        final long = rays.angles;
        for (var k = 0; k < long.length; k++) {
          ray(long[k], rays.r1, k);
        }
        final short = rays.shortAngles;
        for (var k = 0; k < short.length; k++) {
          ray(short[k], rays.shortR1!, 20 + k);
        }
      }
      if (sp.laurel case final laurel?) paintLaurel(canvas, c, r, laurel, ink, seed: seed + 40);
      for (final d in sp.dots) {
        canvas.drawCircle(sparklePosition(c, r, d), math.max(0.8, r * d.size), Paint()..color = ink.ink);
      }
      if (paintTwinkles) {
        for (var i = 0; i < sp.twinkles.length; i++) {
          final t = sp.twinkles[i];
          final m = twinkle == null ? null : twinkleMotion(tier, i, twinkle! * 2.6, 0);
          paintTwinkle(canvas, sparklePosition(c, r, t), r * t.size * (m?.scale ?? 1), ink,
              rotate: t.rotate * math.pi / 180 + (m?.rotate ?? 0), opacity: m?.opacity ?? 1);
        }
      }
    }
  }

  /// Where sparkle [s] sits around a stone at [c] with radius [r].
  static Offset sparklePosition(Offset c, double r, Sparkle s) {
    final a = s.angle * math.pi / 180;
    return c + Offset(math.cos(a), math.sin(a)) * (r * s.dist);
  }

  @override
  bool shouldRepaint(NodePainter old) =>
      old.tier != tier ||
      old.ink != ink ||
      old.style != style ||
      old.strength != strength ||
      old.decay != decay ||
      old.twinkle != twinkle ||
      old.seed != seed ||
      old.monochrome != monochrome ||
      old.paintTwinkles != paintTwinkles ||
      old.sweep != sweep;
}
