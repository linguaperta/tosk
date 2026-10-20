/// One storybook bough of the map: its geometry is computed once (seeded)
/// in [BoughShape.build] and painted in [BoughShape.paint], so the map can
/// keep the shapes between frames and hand the leaf positions to the leaf
/// layer, which sways them while the map scrolls (see `map_motion.dart`).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/skin.dart';
import 'branch_style.dart';
import 'ink_art.dart';

/// Where a bough's ash leaf hangs: at the tip of its twig, pointing along
/// [angle] (radians), [scale] the leaf's scale, [seed] its leaflet jitter.
@immutable
class LeafSpot {
  const LeafSpot({required this.tip, required this.angle, required this.scale, required this.seed});
  final Offset tip;
  final double angle;
  final double scale;
  final int seed;
}

/// A bough's precomputed geometry: the tapered silhouette with knuckles,
/// bark grain on the shadow side, the hatched shadow region, knuckle creases,
/// the two outline strokes, and the twig with its [leaf] on the longer ones.
class BoughShape {
  BoughShape._({
    required this.seed,
    required this.silhouette,
    required this.grain,
    required this.shadow,
    required this.hatchAngle,
    required this.creases,
    required this.outlines,
    required this.twig,
    required this.twigBand,
    required this.leaf,
  });

  final int seed;
  final Path silhouette;
  final Path grain;
  final Path shadow;
  final double hatchAngle;
  final List<Polyline> creases;
  final List<Polyline> outlines;
  final Polyline? twig;
  final Path? twigBand;

  /// The ash leaf at the twig's tip (null on short boughs or without leaves).
  final LeafSpot? leaf;

  /// The bough along [centre] (parent → child), [w0] px wide at the start
  /// and [w1] at the end; null when the path is too short to draw.
  static BoughShape? build(
    Path centre, {
    required BranchStyle style,
    required double w0,
    required double w1,
    int seed = 6,
    bool leaves = true,
    double leafScale = 0.8,
    double leafMinLength = 120,
  }) {
    final line = Polyline.sample(centre, 2.5).smoothed(2);
    if (line.isEmpty) return null;
    final n = line.length;
    final rnd = math.Random(seed);
    double length = 0;
    for (var i = 1; i < n; i++) {
      length += (line.points[i] - line.points[i - 1]).distance;
    }
    if (length < 4) return null;

    // Knuckles: where the bough swells.
    final bumps = <(double, double, double)>[];
    final count = style.knucklesMin + (style.knucklesMax > style.knucklesMin ? rnd.nextInt(style.knucklesMax - style.knucklesMin + 1) : 0);
    double pick(List<double> range) => range.length == 2 ? range[0] + rnd.nextDouble() * (range[1] - range[0]) : (range.isEmpty ? 0 : range[0]);
    for (var k = 0; k < count; k++) {
      bumps.add((pick(style.knuckleCentre), pick(style.knuckleAmp), pick(style.knuckleSigma)));
    }
    double prof(double s) {
      var w = w0 + (w1 - w0) * s;
      for (final (c, amp, wd) in bumps) {
        w *= 1 + amp * math.exp(-math.pow((s - c) / wd, 2));
      }
      return w;
    }

    double sAt(int i) => n == 1 ? 0 : i / (n - 1);
    // The silhouette, with a slow hand wobble on each side.
    final wobbleL = List.generate(n, (_) => (rnd.nextDouble() - 0.5) * style.wobble * 2);
    final wobbleR = List.generate(n, (_) => (rnd.nextDouble() - 0.5) * style.wobble * 2);
    for (var k = 0; k < 4; k++) {
      for (var i = 1; i < n - 1; i++) {
        wobbleL[i] = (wobbleL[i - 1] + wobbleL[i] * 2 + wobbleL[i + 1]) / 4;
        wobbleR[i] = (wobbleR[i - 1] + wobbleR[i] * 2 + wobbleR[i + 1]) / 4;
      }
    }
    final silhouette = bandPath(line, (i, side) => prof(sAt(i)) / 2 + (side > 0 ? wobbleL[i] : wobbleR[i]));

    // Which side the light falls on: the normal pointing toward the light.
    final litSign = _litSide(line);

    // Bark grain on the shadow side: broken lines offset from the centre.
    final grain = Path();
    for (final off in style.grainOffsets) {
      var start = rnd.nextDouble() * 0.25;
      while (start < 0.95) {
        final ln = pick(style.grainDash);
        final i0 = (start * (n - 1)).floor(), i1 = (math.min(0.999, start + ln) * (n - 1)).floor();
        var first = true;
        for (var i = i0; i <= i1; i += 2) {
          final h = prof(sAt(i)) / 2 * off * -litSign;
          final p = line.points[i] + line.normals[i] * h;
          first ? grain.moveTo(p.dx, p.dy) : grain.lineTo(p.dx, p.dy);
          first = false;
        }
        start += ln + pick(style.grainGap);
      }
    }

    // Hatching on the shadow side, between hatchInner and hatchOuter of the half width.
    final shadow = Path();
    for (var i = 0; i < n; i++) {
      final p = line.points[i] + line.normals[i] * (prof(sAt(i)) / 2 * style.hatchOuter * -litSign);
      i == 0 ? shadow.moveTo(p.dx, p.dy) : shadow.lineTo(p.dx, p.dy);
    }
    for (var i = n - 1; i >= 0; i--) {
      final p = line.points[i] + line.normals[i] * (prof(sAt(i)) / 2 * style.hatchInner * -litSign);
      shadow.lineTo(p.dx, p.dy);
    }
    shadow.close();
    final dir = line.points.last - line.points.first;
    final dirDeg = math.atan2(dir.dy, dir.dx) * 180 / math.pi;

    // Knuckle creases: a short curved stroke across the bough where it swells.
    final creases = <Polyline>[];
    for (final (c, _, _) in bumps) {
      final i = (c * (n - 1)).round().clamp(0, n - 1);
      final h = prof(c) / 2;
      final nrm = line.normals[i];
      final tan = line.tangents[i];
      for (final side in const [1.0, -1.0]) {
        final cx = line.points[i] + nrm * (h * 0.55 * side);
        final crease = Path()
          ..moveTo(cx.dx - tan.dx * h * 0.5, cx.dy - tan.dy * h * 0.5)
          ..quadraticBezierTo(cx.dx + nrm.dx * 3 * side, cx.dy + nrm.dy * 3 * side, cx.dx + tan.dx * h * 0.5, cx.dy + tan.dy * h * 0.5);
        creases.add(Polyline.sample(crease, 2));
      }
    }

    // The outline: two ink strokes, one per side, heavier in the shadow.
    final outlines = <Polyline>[];
    for (final side in const [1, -1]) {
      final pts = <Offset>[], tans = <Offset>[];
      for (var i = 0; i < n; i++) {
        pts.add(line.points[i] + line.normals[i] * (prof(sAt(i)) / 2 + (side > 0 ? wobbleL[i] : wobbleR[i])) * side.toDouble());
        tans.add(line.tangents[i]);
      }
      outlines.add(Polyline(pts, tans));
    }

    // A leaf on a twig, on the longer boughs.
    Polyline? twigLine;
    Path? twigBand;
    LeafSpot? leaf;
    if (leaves && length >= leafMinLength) {
      final i = (style.leafAt * (n - 1)).round().clamp(0, n - 1);
      final side = (seed % 2 == 0 ? 1.0 : -1.0);
      final nrm = line.normals[i] * side;
      final tan = line.tangents[i];
      final base = line.points[i] + nrm * (prof(sAt(i)) / 2 * 0.6);
      // Twig length and widths in spec px, scaled to this node size.
      final twigLen = pick(style.twigLength) * leafScale;
      final twigW0 = (style.twigWidth.isEmpty ? 10.0 : style.twigWidth.first) * 0.35 * leafScale;
      final twigW1 = (style.twigWidth.length < 2 ? 4.0 : style.twigWidth[1]) * 0.35 * leafScale;
      final tip = base + nrm * twigLen + tan * (twigLen * 0.35);
      final twig = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(base.dx + nrm.dx * twigLen * 0.5, base.dy + nrm.dy * twigLen * 0.5, tip.dx, tip.dy);
      final tl = Polyline.sample(twig, 2).smoothed();
      twigLine = tl;
      twigBand = bandPath(tl, (j, _) => (twigW0 + (twigW1 - twigW0) * j / math.max(1, tl.length - 1)) / 2);
      final leafAngle = math.atan2(nrm.dy, nrm.dx) + (tan.dy.abs() > tan.dx.abs() ? 0.35 : -0.35) * side;
      leaf = LeafSpot(tip: tip, angle: leafAngle, scale: leafScale * 0.85, seed: seed + 3);
    }

    return BoughShape._(
      seed: seed,
      silhouette: silhouette,
      grain: grain,
      shadow: Path.combine(PathOperation.intersect, shadow, silhouette),
      hatchAngle: dirDeg + style.hatchAngle,
      creases: creases,
      outlines: outlines,
      twig: twigLine,
      twigBand: twigBand,
      leaf: leaf,
    );
  }

  /// Paints the bough in [ink]; [leaf] false leaves the ash leaf out (the
  /// map's leaf layer draws it, swaying), the twig is always drawn.
  void paint(Canvas canvas, MapInk ink, BranchStyle style, {bool leaf = true}) {
    canvas.drawPath(silhouette, Paint()..color = ink.bark);
    canvas.drawPath(
      grain,
      Paint()
        ..color = ink.ink.withValues(alpha: ink.ink.a * style.grainOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.grainWidth
        ..strokeCap = StrokeCap.round,
    );
    hatchRegion(canvas, shadow, ink.ink,
        angleDeg: hatchAngle,
        spacing: style.hatchSpacing,
        width: style.hatchWidth,
        seed: seed,
        opacity: ink.hatchOpacity >= 1 ? 1 : style.hatchOpacity);
    for (var k = 0; k < creases.length; k++) {
      inkStroke(canvas, creases[k], ink.ink, wmin: 1.2, wmax: 1.8, profile: 'taper', seed: seed + k);
    }
    for (var k = 0; k < outlines.length; k++) {
      inkStroke(canvas, outlines[k], ink.ink,
          wmin: style.outlineMin, wmax: style.outlineMax, wobble: style.wobble * 0.6, seed: seed + (k == 0 ? 1 : -1));
    }
    final l = this.leaf;
    if (twig case final t? when l != null) {
      canvas.drawPath(twigBand!, Paint()..color = ink.bark);
      final s = l.scale / 0.85;
      inkStroke(canvas, t, ink.ink, wmin: 1.0 * s, wmax: 1.8 * s, profile: 'flat', seed: seed + 7);
      if (leaf) paintAshLeaf(canvas, l.tip, l.angle, l.scale, ink, seed: l.seed);
    }
  }
}

/// Draws one bough along [centre] (parent → child), [w0] px wide at the start
/// and [w1] at the end, in the storybook style (see `MapEdgesPainter`).
void paintBough(
  Canvas canvas,
  Path centre, {
  required MapInk ink,
  required BranchStyle style,
  required double w0,
  required double w1,
  int seed = 6,
  bool leaves = true,
  double leafScale = 0.8,
  double leafMinLength = 120,
}) {
  BoughShape.build(centre, style: style, w0: w0, w1: w1, seed: seed, leaves: leaves, leafScale: leafScale, leafMinLength: leafMinLength)
      ?.paint(canvas, ink, style);
}

/// +1 when the polyline's left normal faces the light, else -1.
double _litSide(Polyline line) {
  var dot = 0.0;
  for (final nrm in line.normals) {
    dot += nrm.dx * kInkLight.dx + nrm.dy * kInkLight.dy;
  }
  return dot >= 0 ? 1 : -1;
}
