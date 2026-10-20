/// The skill node medallion in the storybook style (the Dart port of the
/// art kit's `node()`, following `assets/brand/branch-style.json`): a round
/// stone with wobbly ink rings, a shadow crescent of hatching, and one look
/// per state:
///
/// - locked: paper, hatched, one faint ring;
/// - available: cream, two rings and a sprouting leaflet;
/// - started: cream plus the strength ring (a dotted track, the filled part heavy);
/// - bronze: bronze stone, hatched, two rings, a gleam, one glint;
/// - silver: silver stone, cross-hatched, three rings, two twinkles and a dot;
/// - gold: gold stone, three rings, eight rays, four twinkles and three dots.
///
/// With [twinkle] (0..1, motion on) the twinkles breathe (scale 0.85–1.15,
/// opacity 0.6–1, phases offset); otherwise they are static. In black &
/// white every fill is white and the hierarchy is kept by hatching, ring
/// count, rays and the twinkle outlines alone.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/skin.dart';
import 'branch_style.dart';
import 'ink_art.dart';
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
    this.dashedRing = false,
  });

  final MapTier tier;
  final MapInk ink;
  final BranchStyle style;

  /// 0..1, the strength ring of a started skill.
  final double strength;

  /// 0..1, how faded the skill is (lightens the stone in colour).
  final double decay;

  /// Animation phase 0..1 (null: static twinkles).
  final double? twinkle;
  final int seed;
  final bool monochrome;

  /// Black & white: a fading skill gets a dashed outer ring.
  final bool dashedRing;

  /// Radius of the stone for a node box of [diameter]: the sparkles reach
  /// `extent` × r (1.75 by the spec), so the stone takes a bit over half.
  static double stoneRadius(double diameter, [double extent = 1.75]) => diameter / (2 * math.max(1.2, extent)) * 1.3;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = stoneRadius(size.shortestSide, style.extent);
    if (r <= 2) return;
    final hw = math.max(0.8, r * 0.035);
    final hatchOp = ink.hatchOpacity;
    final circle = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final inner = Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.78));
    final locked = tier == MapTier.locked;
    final metal = tier.index >= MapTier.bronze.index;

    var base = switch (tier) {
      MapTier.locked => ink.paper,
      MapTier.available || MapTier.started => ink.cream,
      MapTier.bronze => ink.bronze,
      MapTier.silver => ink.silver,
      MapTier.gold => ink.gold,
    };
    final fade = decay.isNaN ? 0.0 : decay.clamp(0.0, 1.0);
    if (!monochrome && fade > 0 && !locked) base = Color.lerp(base, ink.paper, 0.6 * fade)!;
    canvas.drawPath(circle, Paint()..color = base);

    switch (tier) {
      case MapTier.locked:
        hatchRegion(canvas, circle, ink.ink,
            angleDeg: 45, spacing: math.max(3, r * 0.14), width: hw, seed: seed, opacity: monochrome ? 1 : 0.45 * hatchOp);
      case MapTier.bronze:
        hatchRegion(canvas, inner, ink.ink,
            angleDeg: 45, spacing: math.max(3, r * 0.17), width: hw, seed: seed, opacity: monochrome ? 1 : 0.35 * hatchOp);
      case MapTier.silver:
        hatchRegion(canvas, inner, ink.ink,
            angleDeg: 25, spacing: math.max(3, r * 0.17), width: hw, seed: seed, opacity: monochrome ? 0.9 : 0.25 * hatchOp);
        hatchRegion(canvas, inner, ink.ink,
            angleDeg: 115,
            spacing: math.max(3, r * 0.34),
            width: hw * 0.7,
            seed: seed + 5,
            opacity: monochrome ? 0.55 : 0.2 * hatchOp);
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

    // The gleam: a paper-coloured arc on the metal, catching the light.
    if (metal && !monochrome) {
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

    // Rings: the outer stone edge, then one or two inner rings by tier.
    if (dashedRing) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, r * 0.1)
        ..color = ink.ink;
      const dashes = 16;
      final step = 2 * math.pi / dashes;
      for (var i = 0; i < dashes; i++) {
        canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * step, step * 0.55, false, p);
      }
    } else {
      inkRing(canvas, c, r, ink.ink,
          wmin: r * (locked ? 0.03 : 0.05), wmax: r * (locked ? 0.08 : 0.16), wobble: 0.3, seed: seed);
    }
    if (!locked) {
      inkRing(canvas, c, r * 0.78, ink.ink, wmin: r * 0.035, wmax: r * 0.06, wobble: 0.25, seed: seed + 2);
    }
    if (tier == MapTier.silver || tier == MapTier.gold) {
      inkRing(canvas, c, r * 0.66, ink.ink, wmin: r * 0.03, wmax: r * 0.045, wobble: 0.2, seed: seed + 3);
    }

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

    // Sparkle: rays, dots and twinkles per tier (gold most, bronze a glint).
    if (metal) {
      final sp = style.sparkleFor(tier.name);
      if (sp.rays case final rays?) {
        for (var k = 0; k < rays.count; k++) {
          final a = (k * 360 / rays.count + rays.startDeg) * math.pi / 180;
          final d = Offset(math.cos(a), math.sin(a));
          final ray = Path()
            ..moveTo(c.dx + d.dx * r * rays.r0, c.dy + d.dy * r * rays.r0)
            ..lineTo(c.dx + d.dx * r * rays.r1, c.dy + d.dy * r * rays.r1);
          inkStroke(canvas, Polyline.sample(ray, 2), ink.ink,
              wmin: r * rays.width, wmax: r * rays.width, wobble: 0, profile: 'in', seed: seed + k);
        }
      }
      for (final d in sp.dots) {
        canvas.drawCircle(_polar(c, r, d), math.max(0.8, r * d.size), Paint()..color = ink.ink);
      }
      for (var i = 0; i < sp.twinkles.length; i++) {
        final t = sp.twinkles[i];
        var scale = 1.0, opacity = 1.0;
        if (twinkle != null) {
          final phase = ((twinkle! + i * 0.37) % 1) * 2 * math.pi;
          scale = 1 + 0.15 * math.sin(phase);
          opacity = 0.8 + 0.2 * math.sin(phase);
        }
        paintTwinkle(canvas, _polar(c, r, t), r * t.size * scale, ink, rotate: t.rotate * math.pi / 180, opacity: opacity);
      }
    }
  }

  static Offset _polar(Offset c, double r, Sparkle s) {
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
      old.dashedRing != dashedRing;
}
