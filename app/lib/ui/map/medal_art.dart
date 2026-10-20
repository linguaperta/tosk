/// Medal drawing pieces for the skill nodes (v0.7.1): the cracks of a
/// decaying node, gold's laurel, silver's shine, bronze's matte stipple and
/// the twinkle motion of the map's shared sparkle layer. Everything is
/// seeded and pure, so a node looks the same on every frame, and every
/// colour comes from a [MapInk], so black & white stays pure.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../theme/skin.dart';
import 'branch_style.dart';
import 'ink_art.dart';
import 'skill_stats.dart';

Offset _polar(double angle, double radius) => Offset(math.cos(angle), math.sin(angle)) * radius;

Offset _unit(Offset o) => o.distance == 0 ? const Offset(0, 1) : o / o.distance;

Offset _rotate(Offset o, double a) =>
    Offset(o.dx * math.cos(a) - o.dy * math.sin(a), o.dx * math.sin(a) + o.dy * math.cos(a));

/// A chip knocked out of the rim: the cut-out region (to clip away) and its
/// broken inner edge (to ink), in unit coordinates (centre 0, radius 1).
class CrackChip {
  CrackChip(this.cut, this.edge, this.angle);
  final List<Offset> cut;
  final List<Offset> edge;

  /// Where on the rim (radians).
  final double angle;
}

/// A fragment breaking off next to a chip: a closed polygon in unit
/// coordinates, already moved and turned away from the rim.
class CrackShard {
  CrackShard(this.points);
  final List<Offset> points;
}

/// The cracks of a decaying node at crack [level] 0..1 (see [Cracks.level]):
/// hairline cracks running in from the rim, more, longer and branching as it
/// decays; chips knocked out of the rim (the first cracks start at them);
/// and from half way a fragment breaking off. Unit coordinates.
class CrackPattern {
  CrackPattern._(this.level, this.lines, this.chips, this.shards);

  final double level;

  /// Each crack runs from its tip inside the stone out to the rim (or chip).
  final List<List<Offset>> lines;
  final List<CrackChip> chips;
  final List<CrackShard> shards;

  bool get isEmpty => lines.isEmpty && chips.isEmpty;

  static final CrackPattern none = CrackPattern._(0, const [], const [], const []);

  factory CrackPattern.build(double level, int seed, [Cracks spec = const Cracks()]) {
    if (level.isNaN || level <= 0) return none;
    final lv = level.clamp(0.0, 1.0);
    final rnd = math.Random(seed * 7 + 13);
    final maxCracks = math.max(1, spec.maxCracks);
    final count = math.min(maxCracks, 1 + (lv * maxCracks).floor());
    final chipCount = math.min(count, spec.chipsAt.where((t) => lv >= t).length);
    final a0 = rnd.nextDouble() * 2 * math.pi;
    final lines = <List<Offset>>[];
    final chips = <CrackChip>[];
    final shards = <CrackShard>[];

    for (var k = 0; k < count; k++) {
      final a = a0 + k * 2 * math.pi / count + (rnd.nextDouble() - 0.5) * 0.9;
      var start = _polar(a, 0.99);
      if (k < chipCount) {
        // The chip: a bite out of the rim with a jagged inner edge.
        final d = 0.17 + rnd.nextDouble() * 0.09 + 0.05 * lv;
        final j1 = _polar(a - d * 0.45, 0.86 + rnd.nextDouble() * 0.04);
        final j2 = _polar(a + (rnd.nextDouble() - 0.5) * d * 0.3, 0.79 - 0.04 * lv);
        final j3 = _polar(a + d * 0.5, 0.85 + rnd.nextDouble() * 0.05);
        final r0 = _polar(a - d, 0.995), r1 = _polar(a + d, 0.995);
        chips.add(CrackChip(
          [_polar(a - d * 1.05, 1.4), r0, j1, j2, j3, r1, _polar(a + d * 1.05, 1.4)],
          [r0, j1, j2, j3, r1],
          a,
        ));
        start = j2;
        // From half way the first chip's piece is still falling off.
        if (k == 0 && lv >= 0.5) {
          final piece = [for (var i = 0; i <= 6; i++) _polar(a - d + 2 * d * i / 6, 1.0), j3, j2, j1];
          var cx = Offset.zero;
          for (final p in piece) {
            cx += p;
          }
          cx = cx / piece.length.toDouble();
          final out = _polar(a, 0.2 + 0.08 * lv) + const Offset(0, 0.06);
          final turn = (rnd.nextBool() ? 1 : -1) * (0.3 + 0.2 * lv);
          shards.add(CrackShard([for (final p in piece) cx + out + _rotate((p - cx) * 0.8, turn)]));
        }
      }
      // The crack: a zig-zag running inward, pulled back toward its heading.
      final heading = _rotate(-_polar(a, 1), (rnd.nextDouble() - 0.5) * 0.6);
      final length = math.min(1.05, 0.3 + 0.6 * lv + rnd.nextDouble() * 0.12);
      final pts = [start];
      var dir = heading;
      var travelled = 0.0;
      var p = start;
      while (travelled < length) {
        dir = _unit(_rotate(dir * 0.6 + heading * 0.4, (rnd.nextDouble() - 0.5) * 1.1));
        final step = 0.1 + rnd.nextDouble() * 0.07;
        final next = p + dir * step;
        if (next.distance > 0.95) break;
        pts.add(next);
        p = next;
        travelled += step;
      }
      if (pts.length >= 2) lines.add(pts.reversed.toList());
      // A side branch on the longer cracks.
      if (lv > 0.35 && pts.length >= 3) {
        final from = pts[1 + rnd.nextInt(pts.length - 2)];
        var bd = _rotate(heading, (rnd.nextBool() ? 1 : -1) * (0.7 + rnd.nextDouble() * 0.4));
        final branch = [from];
        var q = from;
        final n = 2 + (lv > 0.7 ? 1 : 0);
        for (var i = 0; i < n; i++) {
          bd = _unit(_rotate(bd, (rnd.nextDouble() - 0.5) * 0.9));
          final next = q + bd * (0.08 + rnd.nextDouble() * 0.06);
          if (next.distance > 0.95) break;
          branch.add(next);
          q = next;
        }
        if (branch.length >= 2) lines.add(branch.reversed.toList());
      }
    }
    return CrackPattern._(lv, lines, chips, shards);
  }

  /// [bounds] minus the chips, for clipping the stone at centre [c], radius [r].
  Path clipOutside(Offset c, double r, Rect bounds) {
    final cut = Path();
    for (final chip in chips) {
      cut.addPolygon([for (final p in chip.cut) c + p * r], true);
    }
    return Path.combine(PathOperation.difference, Path()..addRect(bounds), cut);
  }

  /// The crack lines (inside the stone, before the clip is restored).
  void paintLines(Canvas canvas, Offset c, double r, MapInk ink, {required bool monochrome, int seed = 1}) {
    final w = math.max(0.8, r * (0.035 + 0.035 * level));
    for (var i = 0; i < lines.length; i++) {
      final path = Path()..addPolygon([for (final p in lines[i]) c + p * r], false);
      final line = Polyline.sample(path, math.max(1.0, r * 0.05));
      if (!monochrome) {
        // The groove's far wall catches the light (lower left of the line).
        final lit = Polyline([for (final p in line.points) p - kInkLight * (w * 0.8)], line.tangents);
        inkStroke(canvas, lit, ink.paper.withValues(alpha: 0.55), wmin: w * 0.45, wmax: w * 0.45, wobble: 0, profile: 'in', seed: seed + i);
      }
      inkStroke(canvas, line, ink.ink, wmin: w, wmax: w * 1.25, wobble: 0.15, profile: 'in', seed: seed + i);
    }
  }

  /// The chips' broken edges and the falling fragment (after the clip).
  void paintBreaks(Canvas canvas, Offset c, double r, MapInk ink, Color stone, {int seed = 1}) {
    final w = math.max(0.9, r * 0.06);
    for (var i = 0; i < chips.length; i++) {
      final path = Path()..addPolygon([for (final p in chips[i].edge) c + p * r], false);
      inkStroke(canvas, Polyline.sample(path, math.max(1.0, r * 0.04)), ink.ink, wmin: w * 0.8, wmax: w * 1.2, wobble: 0.1, seed: seed + 20 + i);
    }
    for (final s in shards) {
      final poly = Path()..addPolygon([for (final p in s.points) c + p * r], true);
      canvas.drawPath(poly, Paint()..color = stone);
      canvas.drawPath(
        poly,
        Paint()
          ..color = ink.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, r * 0.045)
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }
}

/// Gold's laurel: two sprigs of leaflets hugging the lower rim of the stone
/// at [c] with radius [r] (the right sprig mirrors the left).
void paintLaurel(Canvas canvas, Offset c, double r, Laurel laurel, MapInk ink, {int seed = 1}) {
  if (r <= 0 || laurel.leaves <= 0) return;
  final leaflet = Path()
    ..moveTo(0, 0)
    ..cubicTo(8, -7, 24, -8, 36, 0)
    ..cubicTo(24, 8, 8, 7, 0, 0)
    ..close();
  final from = laurel.fromDeg * math.pi / 180, to = laurel.toDeg * math.pi / 180;
  final rr = laurel.radius * r;
  final scale = laurel.size * r / 36;
  final outline = math.max(0.7, r * 0.03) / scale;
  for (final side in const [1.0, -1.0]) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (side < 0) canvas.scale(-1, 1);
    // The stem along the rim.
    final stem = Path();
    const steps = 14;
    for (var i = 0; i <= steps; i++) {
      final p = _polar(from + (to - from) * i / steps, rr);
      i == 0 ? stem.moveTo(p.dx, p.dy) : stem.lineTo(p.dx, p.dy);
    }
    inkStroke(canvas, Polyline.sample(stem, math.max(1.0, r * 0.05)), ink.ink,
        wmin: math.max(0.6, r * 0.035), wmax: math.max(0.8, r * 0.05), wobble: 0, profile: 'taper', seed: seed);
    void leaf(Offset at, Offset dir) {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(math.atan2(dir.dy, dir.dx));
      canvas.scale(scale);
      canvas.drawPath(leaflet, Paint()..color = ink.leaf);
      canvas.drawPath(
        leaflet,
        Paint()
          ..color = ink.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = outline
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawLine(const Offset(4, 0), const Offset(26, 0), Paint()
        ..color = ink.ink
        ..strokeWidth = outline * 0.6);
      canvas.restore();
    }

    final sign = to >= from ? 1.0 : -1.0;
    for (var i = 0; i < laurel.leaves; i++) {
      final a = from + (to - from) * (i + 0.45) / laurel.leaves;
      final at = _polar(a, rr);
      final tangent = Offset(-math.sin(a), math.cos(a)) * sign;
      final outward = _polar(a, 1);
      // Alternate outside and inside the stem, leaning toward the tip.
      final n = i.isEven ? outward : -outward;
      leaf(at, _unit(tangent * math.cos(0.6) + n * math.sin(0.6)));
    }
    // The terminal leaflet.
    leaf(_polar(to, rr), Offset(-math.sin(to), math.cos(to)) * sign);
    canvas.restore();
  }
}

/// Silver's shine: two bright diagonal bands on the lit side of the stone
/// (inside the inner ring, [r] the stone radius), perpendicular to the light.
/// With [edge] (black & white) the wide band gets thin ink edges, so the
/// shine reads as a highlight and not just as a gap in the hatching.
void paintShine(Canvas canvas, Offset c, double r, Color color, {Color? edge}) {
  final across = Offset(-kInkLight.dy, kInkLight.dx);
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.74)));
  for (final (off, half) in const [(0.3, 0.1), (0.52, 0.042)]) {
    final m = c + kInkLight * (r * off);
    canvas.drawPath(
      Path()
        ..addPolygon([
          m - across * r + kInkLight * (r * half),
          m + across * r + kInkLight * (r * half),
          m + across * r - kInkLight * (r * half),
          m - across * r - kInkLight * (r * half),
        ], true),
      Paint()..color = color,
    );
    if (edge != null && half > 0.05) {
      final p = Paint()
        ..color = edge
        ..strokeWidth = math.max(0.7, r * 0.025)
        ..style = PaintingStyle.stroke;
      for (final s in const [1.0, -1.0]) {
        final o = kInkLight * (r * half * s);
        canvas.drawLine(m - across * r + o, m + across * r + o, p);
      }
    }
  }
  canvas.restore();
}

/// A shine sweeping across the stone (the promotion moment): a soft bright
/// band at [t] 0..1 of the way from the lower left to the upper right.
void paintShineSweep(Canvas canvas, Offset c, double r, double t, Color color) {
  if (t.isNaN || t <= 0 || t >= 1) return;
  final across = Offset(-kInkLight.dy, kInkLight.dx);
  final m = c + kInkLight * (r * (-1.4 + 2.8 * t));
  final half = r * 0.16;
  final alpha = math.sin(math.pi * t);
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
  for (final (k, a) in const [(1.0, 0.35), (0.45, 0.75)]) {
    canvas.drawPath(
      Path()
        ..addPolygon([
          m - across * r * 1.2 + kInkLight * (half * k),
          m + across * r * 1.2 + kInkLight * (half * k),
          m + across * r * 1.2 - kInkLight * (half * k),
          m - across * r * 1.2 - kInkLight * (half * k),
        ], true),
      Paint()..color = color.withValues(alpha: color.a * a * alpha),
    );
  }
  canvas.restore();
}

/// Bronze's matte stipple: seeded ink dots on the inner disc.
void paintStipple(Canvas canvas, Offset c, double r, Color color, {int seed = 1}) {
  final rnd = math.Random(seed * 3 + 1);
  final n = (r * 1.1).round().clamp(10, 44);
  final dot = math.max(0.55, r * 0.03);
  final paint = Paint()..color = color;
  for (var i = 0; i < n; i++) {
    final a = rnd.nextDouble() * 2 * math.pi;
    final d = math.sqrt(rnd.nextDouble()) * r * 0.72;
    canvas.drawCircle(c + _polar(a, d), dot * (0.7 + rnd.nextDouble() * 0.6), paint);
  }
}

/// How twinkle [index] of a [tier] medal moves at [t] seconds on the map
/// ([phase] 0..1 per node, so nodes don't pulse in step): silver and gold
/// breathe (scale and opacity on a slow sine, phases offset) with now and
/// then a brighter flare; bronze's single glint rests and flares once every
/// few seconds. Rotation in radians.
({double scale, double opacity, double rotate}) twinkleMotion(MapTier tier, int index, double t, double phase) {
  if (t.isNaN) return (scale: 1, opacity: 1, rotate: 0);
  double flare(double period, double width, double offset) {
    final local = ((t / period + phase + offset) % 1) * period;
    return local < width ? math.sin(math.pi * local / width) : 0;
  }

  switch (tier) {
    case MapTier.bronze:
      final f = flare(5.2, 0.7, 0);
      return (scale: 1 + 0.45 * f, opacity: 1, rotate: 0.6 * f);
    case MapTier.silver:
      final ph = 2 * math.pi * (t / 2.4 + phase + index * 0.37);
      final f = index == 0 ? flare(6.5, 0.6, 0.3) : 0.0;
      return (scale: 1 + 0.14 * math.sin(ph) + 0.35 * f, opacity: 0.82 + 0.18 * math.sin(ph), rotate: 0.5 * f);
    case MapTier.gold:
      final ph = 2 * math.pi * (t / 2.0 + phase + index * 0.29);
      final f = flare(4.5, 0.55, index * 0.25);
      return (
        scale: 1 + 0.18 * math.sin(ph) + 0.3 * f,
        opacity: 0.75 + 0.25 * math.sin(ph),
        rotate: 0.12 * math.sin(ph * 0.5) + 0.5 * f,
      );
    default:
      return (scale: 1, opacity: 1, rotate: 0);
  }
}
