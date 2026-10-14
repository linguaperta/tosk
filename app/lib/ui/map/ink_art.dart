/// Pen-and-ink drawing primitives for the map: the Dart port of the storybook
/// generator's look (`app/assets/brand/explore/storybook/make_storybook.py`):
/// filled, tapered ink strokes whose weight follows the light, procedural
/// hatching, wobbly rings, ash leaves and 4-point twinkles. Everything is
/// deterministic (seeded) so a node or branch looks the same on every frame,
/// and every colour comes from a [MapInk], so black & white stays pure.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../theme/skin.dart';

/// Light comes from the top right (the storybook's `LIGHT`).
const Offset kInkLight = Offset(0.45, -0.89);

/// A sampled curve: points with unit tangents and left-hand normals.
class Polyline {
  Polyline(this.points, this.tangents) : normals = [for (final t in tangents) Offset(-t.dy, t.dx)];
  final List<Offset> points;
  final List<Offset> tangents;
  final List<Offset> normals;
  int get length => points.length;
  bool get isEmpty => points.length < 2;

  /// Samples [path] every [step] px (at least 2 points per contour).
  static Polyline sample(Path path, double step) {
    final pts = <Offset>[];
    final tans = <Offset>[];
    for (final m in path.computeMetrics()) {
      if (m.length <= 0) continue;
      final n = math.max(2, (m.length / step).ceil() + 1);
      for (var i = 0; i < n; i++) {
        final t = m.getTangentForOffset(m.length * i / (n - 1));
        if (t == null) continue;
        pts.add(t.position);
        tans.add(t.vector.distance == 0 ? const Offset(0, 1) : t.vector);
      }
    }
    return Polyline(pts, tans);
  }

  /// Smooths the normals so a sharp corner doesn't tear a band.
  Polyline smoothed([int passes = 2]) {
    var nrm = List.of(tangents);
    for (var p = 0; p < passes; p++) {
      nrm = [
        for (var i = 0; i < nrm.length; i++)
          _unit(nrm[math.max(0, i - 1)] + nrm[i] * 2 + nrm[math.min(nrm.length - 1, i + 1)]),
      ];
    }
    return Polyline(points, nrm);
  }
}

Offset _unit(Offset o) => o.distance == 0 ? const Offset(0, 1) : o / o.distance;

/// A closed polygon around a polyline, [halfWidth] (per index, per side) away
/// along the normal: left side forward, right side back.
Path bandPath(Polyline line, double Function(int i, int side) halfWidth) {
  final path = Path();
  if (line.isEmpty) return path;
  final n = line.length;
  for (var i = 0; i < n; i++) {
    final p = line.points[i] + line.normals[i] * halfWidth(i, 1);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  for (var i = n - 1; i >= 0; i--) {
    final p = line.points[i] - line.normals[i] * halfWidth(i, -1);
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  return path;
}

/// An ink stroke along [line]: a filled band whose width goes from [wmin] on
/// the lit side to [wmax] in the shadow (the stroke weight follows the light),
/// with a little hand wobble. [profile] scales the width along the stroke:
/// "taper" thins both ends, "in" thins only the start, "flat" is even.
void inkStroke(
  Canvas canvas,
  Polyline line,
  Color color, {
  required double wmin,
  required double wmax,
  double wobble = 0.35,
  int seed = 1,
  String profile = 'flat',
}) {
  if (line.isEmpty) return;
  final rnd = math.Random(seed);
  final n = line.length;
  final noise = List.generate(n, (_) => (rnd.nextDouble() - 0.5) * 2 * wobble);
  // Smooth the noise so the wobble is slow, like a hand, not jitter.
  for (var k = 0; k < 3; k++) {
    for (var i = 1; i < n - 1; i++) {
      noise[i] = (noise[i - 1] + noise[i] * 2 + noise[i + 1]) / 4;
    }
  }
  double width(int i) {
    final s = n == 1 ? 0.0 : i / (n - 1);
    final lit = (line.normals[i].dx * kInkLight.dx + line.normals[i].dy * kInkLight.dy);
    var w = wmin + (wmax - wmin) * (0.5 - 0.5 * lit) + noise[i];
    final p = switch (profile) {
      'taper' => math.min(1, math.min(s, 1 - s) * 6).clamp(0.15, 1.0),
      'in' => math.min(1, s * 6).clamp(0.15, 1.0),
      _ => 1.0,
    };
    return math.max(0.3, w * p);
  }

  canvas.drawPath(bandPath(line, (i, _) => width(i) / 2), Paint()..color = color);
}

/// Parallel hatching clipped to [region]: lines at [angleDeg], [spacing] px
/// apart, with a little jitter and random gaps so it reads as pen work.
void hatchRegion(
  Canvas canvas,
  Path region,
  Color color, {
  required double angleDeg,
  required double spacing,
  double width = 1.0,
  double jitter = 0.5,
  int seed = 11,
  double opacity = 1,
}) {
  final bounds = region.getBounds();
  if (bounds.isEmpty || spacing <= 0) return;
  final rnd = math.Random(seed);
  final a = angleDeg * math.pi / 180;
  final dir = Offset(math.cos(a), math.sin(a));
  final nrm = Offset(-dir.dy, dir.dx);
  final c = bounds.center;
  final r = bounds.longestSide;
  final paint = Paint()
    ..color = color.withValues(alpha: color.a * opacity)
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  canvas.save();
  canvas.clipPath(region);
  final count = (2 * r / spacing).ceil();
  for (var k = -count; k <= count; k++) {
    final off = k * spacing + (rnd.nextDouble() - 0.5) * jitter;
    final base = c + nrm * off;
    // Pen lines: slight angle drift and a broken line now and then.
    final drift = (rnd.nextDouble() - 0.5) * 0.06;
    final d = Offset(math.cos(a + drift), math.sin(a + drift));
    final p0 = base - d * r;
    final p1 = base + d * r;
    if (rnd.nextDouble() < 0.12) {
      final gap = 0.3 + rnd.nextDouble() * 0.4;
      canvas.drawLine(p0, Offset.lerp(p0, p1, gap - 0.04)!, paint);
      canvas.drawLine(Offset.lerp(p0, p1, gap + 0.04)!, p1, paint);
    } else {
      canvas.drawLine(p0, p1, paint);
    }
  }
  canvas.restore();
}

/// A wobbly ink ring: a circle drawn as an [inkStroke], heavier on the shadow side.
void inkRing(Canvas canvas, Offset center, double radius, Color color,
    {required double wmin, required double wmax, double wobble = 0.3, int seed = 2}) {
  if (radius <= 0) return;
  final path = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  inkStroke(canvas, Polyline.sample(path, 1.5).smoothed(), color, wmin: wmin, wmax: wmax, wobble: wobble, seed: seed);
}

/// A 4-point twinkle star around [center]: concave sides, [size] from the
/// center to a tip, [thin] the half width at the waist.
Path twinklePath(Offset center, double size, {double thin = 0.22}) {
  final c = center;
  final w = size * thin;
  return Path()
    ..moveTo(c.dx, c.dy - size)
    ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + size, c.dy)
    ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + size)
    ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - size, c.dy)
    ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - size)
    ..close();
}

/// A twinkle: a paper-filled star with an ink outline, [size] to a tip,
/// turned by [rotate] radians. [opacity] below 1 (motion) blends it into
/// the background; in black & white it stays fully opaque (nothing grey).
void paintTwinkle(Canvas canvas, Offset center, double size, MapInk ink,
    {Color? fill, double rotate = 0, double opacity = 1}) {
  if (size <= 0.4 || size.isNaN) return;
  final mono = ink.hatchOpacity >= 1;
  final alpha = mono ? 1.0 : opacity.clamp(0.0, 1.0);
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(rotate);
  final star = twinklePath(Offset.zero, size);
  canvas.drawPath(star, Paint()..color = (fill ?? ink.paper).withValues(alpha: alpha));
  canvas.drawPath(
    star,
    Paint()
      ..color = ink.ink.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, size * 0.11)
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.restore();
}

/// One leaflet (the storybook's `LEAFLET`, 36 units long), drawn at the origin
/// pointing along +x. Scaled by the caller.
Path _leafletPath() => Path()
  ..moveTo(0, 0)
  ..cubicTo(8, -7, 24, -8, 36, 0)
  ..cubicTo(24, 8, 8, 7, 0, 0)
  ..close();

/// A pinnate ash leaf: a stem with three leaflet pairs and a terminal leaflet,
/// starting at [origin], rotated by [angle] (radians), [scale] × 92 px long.
void paintAshLeaf(Canvas canvas, Offset origin, double angle, double scale, MapInk ink, {int seed = 2, bool shade = true}) {
  if (scale <= 0) return;
  final rnd = math.Random(seed);
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  canvas.rotate(angle);
  canvas.scale(scale);
  final stem = Path()
    ..moveTo(0, 0)
    ..cubicTo(30, -4, 60, -2, 92, 0);
  inkStroke(canvas, Polyline.sample(stem, 3).smoothed(), ink.ink, wmin: 1.4, wmax: 2.4, profile: 'in', seed: seed);
  final leaflets = <(double, double, double)>[];
  for (var i = 0; i < 3; i++) {
    final t = 22.0 + 24 * i;
    for (final side in const [-1, 1]) {
      leaflets.add((t, side * (-52 + rnd.nextDouble() * 10), 0.9 + 0.1 * i));
    }
  }
  leaflets.add((92, -2, 1.05));
  final leaflet = _leafletPath();
  final outline = Paint()
    ..color = ink.ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;
  final rib = Paint()
    ..color = ink.ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.9;
  for (final (lx, deg, sc) in leaflets) {
    canvas.save();
    canvas.translate(lx, 0);
    canvas.rotate(deg * math.pi / 180);
    canvas.scale(sc);
    canvas.drawPath(leaflet, Paint()..color = ink.leaf);
    if (shade) {
      hatchRegion(canvas, leaflet, ink.ink, angleDeg: 35, spacing: 3.2, width: 0.8, seed: seed + lx.round(), opacity: ink.hatchOpacity);
    }
    canvas.drawPath(leaflet, outline);
    canvas.drawLine(const Offset(3, 0), const Offset(30, 0), rib);
    canvas.restore();
  }
  canvas.restore();
}

/// A small leaflet (the "ready to start" sprout on an available node).
void paintSprout(Canvas canvas, Offset at, double angle, double scale, MapInk ink) {
  if (scale <= 0) return;
  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.rotate(angle);
  canvas.scale(scale);
  final leaflet = _leafletPath();
  canvas.drawPath(leaflet, Paint()..color = ink.leaf);
  canvas.drawPath(
    leaflet,
    Paint()
      ..color = ink.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2,
  );
  canvas.drawLine(const Offset(3, 0), const Offset(28, 0), Paint()
    ..color = ink.ink
    ..strokeWidth = 1.2);
  canvas.restore();
}

/// A stable small integer from a string (seeds per node or edge).
int inkSeed(String s) {
  var h = 17;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}
