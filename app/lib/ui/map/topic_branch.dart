/// Topic branches on the main map (docs/extensions.md, docs/ui.md "Topic
/// branches"): at each topic's anchor skill a side branch grows off the node
/// and runs out of the map's edge (on very wide maps it fades out instead).
/// Along it the topic's name and an arrow toward the edge are carved into the
/// bark itself, following the branch's curve. The branch and its carving are
/// static art: they are painted into the map's bough raster tiles
/// (`map_raster.dart`) like the boughs. The branch itself is the way into the
/// topic ([TopicBranchTarget]): a band at least 48 dp thick along it opens the
/// topic, with a pressed look drawn on a small overlay only while pressed.
///
/// Layout: the map inserts a strip under the anchor's row (`MapGeometry.strips`)
/// with one lane per branch on a side ([planBranchLanes]); a branch leaves the
/// stone diagonally, behind the anchor's title, and runs along its lane.
/// Several topics on one anchor alternate sides where there is room.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/bw_skin.dart';
import '../theme/skin.dart';
import 'bough.dart';
import 'branch_style.dart';
import 'ink_art.dart';
import 'map_layout.dart';

/// A topic as the main map shows it: its branch at [anchor].
@immutable
class TopicBranch {
  const TopicBranch({
    required this.id,
    required this.anchor,
    required this.title,
    required this.shortTitle,
    this.locked = false,
    this.progress = '',
  });

  final String id;

  /// The main-tree skill the branch grows from.
  final String anchor;
  final String title;

  /// Carved instead of [title] where the title doesn't fit.
  final String shortTitle;

  /// The anchor is not started yet: the branch and its carving look locked
  /// (the topic can still be opened and browsed).
  final bool locked;

  /// The topic's progress in words ("2 of 5 skills started"), for semantics.
  final String progress;

  @override
  bool operator ==(Object other) =>
      other is TopicBranch &&
      other.id == id &&
      other.anchor == anchor &&
      other.title == title &&
      other.shortTitle == shortTitle &&
      other.locked == locked &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(id, anchor, title, shortTitle, locked, progress);
}

/// The root of a topic's map: the main-tree skill it grows from, which leads
/// back to the main tree ([onTap]); [label] says so (semantics, tooltip).
@immutable
class TopicRoot {
  const TopicRoot({required this.skillId, required this.label, required this.onTap});
  final String skillId;
  final String label;
  final VoidCallback onTap;
}

/// Sizes of the topic branches at the map's stone [diameter].
@immutable
class BranchMetrics {
  const BranchMetrics(this.diameter);
  final double diameter;

  /// The branch's width where the carving is.
  double get width => (diameter * 0.46).clamp(20.0, 36.0);

  /// The carved letters' size.
  double get fontSize => (width * 0.56).clamp(11.0, 19.0);

  /// The tap band along a branch is at least this thick (a touch target).
  static const double minHit = 48;

  /// Half the thickness of the tap band along the branch: the bark (with its
  /// knuckles) and a margin, at least [minHit] / 2.
  double get hitHalf => math.max(minHit / 2, width * 0.6 + 6);

  /// A lane: the branch's tap band and a small margin (lanes on top of each
  /// other never share a tap band).
  double get laneHeight => 2 * hitHalf + 4;

  /// The longest run along a lane; beyond it the branch fades out (very wide maps).
  double maxRun(double cellWidth) => (cellWidth * 3.4).clamp(300.0, 480.0);
}

/// Where a branch goes: the anchor's node, the side (+1 right, -1 left) and
/// its lane in the strip under the anchor's row.
@immutable
class BranchLane {
  const BranchLane({required this.branch, required this.node, required this.side, required this.lane});
  final TopicBranch branch;
  final MapNode node;
  final int side;
  final int lane;
}

/// Assigns each branch a side and a lane. [centerX] is the x of a node's
/// centre, [width] the map's width. The topics of one anchor alternate sides,
/// starting with the side with more room; branches of one row whose runs
/// overlap get separate lanes.
List<BranchLane> planBranchLanes({
  required MapLayout layout,
  required List<TopicBranch> branches,
  required double Function(MapNode) centerX,
  required double width,
  required double maxRun,
}) {
  final byAnchor = <String, List<TopicBranch>>{};
  for (final b in branches) {
    if (layout.node(b.anchor) != null) (byAnchor[b.anchor] ??= []).add(b);
  }
  final out = <BranchLane>[];
  // Runs taken per (band, row) and lane: x intervals.
  final taken = <(int, int), List<List<(double, double)>>>{};
  final anchors = byAnchor.keys.map(layout.node).whereType<MapNode>().toList()
    ..sort((a, b) => a.globalRow != b.globalRow ? a.globalRow.compareTo(b.globalRow) : a.col.compareTo(b.col));
  for (final n in anchors) {
    // The lane is a strip of its own under the row, so the run only needs
    // room: the first branch goes to the side with more of it.
    final cx = centerX(n);
    final first = width - cx >= cx - 0.5 ? 1 : -1;
    final list = byAnchor[n.skillId]!;
    for (var i = 0; i < list.length; i++) {
      final side = i.isEven ? first : -first;
      final end = side > 0 ? math.min(width, cx + maxRun) : math.max(0.0, cx - maxRun);
      final run = side > 0 ? (cx, end) : (end, cx);
      final lanes = taken[(n.band, n.row)] ??= [];
      var lane = 0;
      while (lane < lanes.length && lanes[lane].any((r) => r.$1 < run.$2 && run.$1 < r.$2)) {
        lane++;
      }
      if (lane == lanes.length) lanes.add([]);
      lanes[lane].add(run);
      out.add(BranchLane(branch: list[i], node: n, side: side, lane: lane));
    }
  }
  return out;
}

/// How many lanes each (band, row) needs.
Map<(int, int), int> branchLaneCounts(List<BranchLane> lanes) {
  final out = <(int, int), int>{};
  for (final l in lanes) {
    final k = (l.node.band, l.node.row);
    out[k] = math.max(out[k] ?? 0, l.lane + 1);
  }
  return out;
}

/// One carved letter: where its optical middle goes ([carvingOpticalCentre];
/// on the bark's middle line) and its angle.
typedef CarvedGlyph = ({String char, Offset center, double angle});

/// Gelasio Bold's x-height and cap height, as fractions of the em (its OS/2
/// table: 994 and 1419 of 2048 units).
const double kCarvingXHeight = 994 / 2048;
const double kCarvingCapHeight = 1419 / 2048;

/// How far above the baseline a carved title's optical middle is: halfway
/// between the middle of the x-height and the middle of the cap height (the
/// letters are mostly lower case, and the capital and the ascenders reach
/// about cap height), so the letters look centred on the bark, not sitting
/// on its middle line.
double carvingOpticalCentre(double fontSize) => fontSize * (kCarvingXHeight + kCarvingCapHeight) / 4;

/// Where to paint the laid-out glyph [tp] (a carving letter of [fontSize]) so
/// that its optical middle ([carvingOpticalCentre]) and horizontal middle land
/// on the origin.
Offset carvedGlyphOrigin(TextPainter tp, double fontSize) =>
    Offset(-tp.width / 2, carvingOpticalCentre(fontSize) - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic));

/// The carving along a branch: the letters (one of [text]) and an arrow
/// toward the map's edge, all following the branch's curve.
@immutable
class Carving {
  const Carving({
    required this.text,
    required this.fontSize,
    required this.glyphs,
    required this.shaft,
    required this.head,
    required this.tail,
    required this.bounds,
  });
  final String text;
  final double fontSize;
  final List<CarvedGlyph> glyphs;

  /// The arrow's shaft and head (toward the edge) and the fletching at its
  /// tail; all empty where only the name fits ([hasArrow]).
  final Polyline shaft;
  final List<Polyline> head;
  final List<Polyline> tail;

  /// Everything the carving covers.
  final Rect bounds;

  bool get hasArrow => shaft.points.isNotEmpty;
}

/// A planned branch: its bough, carving, tap band and fade.
class BranchPlan {
  BranchPlan({
    required this.branch,
    required this.side,
    required this.lane,
    required this.shape,
    required this.run,
    required this.hitHalf,
    required this.carving,
    required this.fade,
  });

  final TopicBranch branch;
  final int side;
  final int lane;

  /// The branch's bark, outline and grain (a bough without twig and leaf).
  final BoughShape shape;

  /// The centre line, sampled (stone → edge).
  final Polyline run;

  /// Half the thickness of the tap band along [run] ([hits]).
  final double hitHalf;
  final Carving? carving;

  /// Where the branch fades out (x from opaque to clear), on very wide maps; null when it runs off the edge.
  final (double, double)? fade;

  /// Everything the branch paints.
  late final Rect bounds = shape.bounds;

  /// Everything the tap band covers (and the pressed look paints).
  late final Rect hitBounds = () {
    var r = bounds;
    for (final p in run.points) {
      r = r.expandToInclude(Rect.fromCircle(center: p, radius: hitHalf));
    }
    return r;
  }();

  /// Whether [p] (map coordinates) is on the branch: within [hitHalf] of its
  /// centre line, which takes in the bark and the carving.
  bool hits(Offset p) {
    if (!hitBounds.contains(p)) return false;
    final pts = run.points;
    final h2 = hitHalf * hitHalf;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], ab = pts[i] - a;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      final t = len2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
      final d = p - (a + ab * t);
      if (d.dx * d.dx + d.dy * d.dy <= h2) return true;
    }
    return false;
  }

  /// A point in the middle of the carving (else of the run): where a test or
  /// a tour taps the branch.
  Offset get tapPoint {
    final c = carving;
    if (c != null && c.glyphs.isNotEmpty) return c.glyphs[c.glyphs.length ~/ 2].center;
    if (c != null && c.hasArrow) return c.shaft.points[c.shaft.length ~/ 2];
    return run.points[(run.length * 0.6).floor().clamp(0, run.length - 1)];
  }
}

/// The style of the carved letters (Gelasio, the storybook wordmark serif).
TextStyle carvingTextStyle(double fontSize) => TextStyle(
  fontFamily: 'Gelasio',
  fontWeight: FontWeight.w700,
  fontSize: fontSize,
  height: 1,
  letterSpacing: fontSize * 0.04,
);

/// Builds the branch of [lane] on the map: from the anchor's stone at
/// [stone] (radius [r]) down into its lane ([laneTop]) and out toward the
/// edge of a map [mapWidth] wide (or fading out after [maxRun]); [avoid] are
/// the x intervals where other boughs cross the lane (the carving keeps
/// clear of them). [scaler] scales the letters with the text size (at most 1.3).
BranchPlan? buildBranch({
  required BranchLane lane,
  required Offset stone,
  required double r,
  required double cellWidth,
  required double laneTop,
  required double mapWidth,
  required BranchMetrics metrics,
  required BranchStyle style,
  List<(double, double)> avoid = const [],
  TextScaler scaler = TextScaler.noScaling,
}) {
  final side = lane.side.toDouble();
  final w = metrics.width;
  // The branch runs along the middle of its lane (its tap band fills the lane).
  final y = laneTop + metrics.laneHeight / 2;
  // It leaves the stone sideways and sweeps down into its lane in one S-curve.
  final start = stone + Offset(side * r * 0.45, r * 0.2);
  final knee = Offset(stone.dx + side * (r + cellWidth * 0.36), y);
  final maxRun = metrics.maxRun(cellWidth);
  final edge = side > 0 ? mapWidth + 12 : -12.0;
  final fades = (edge - knee.dx).abs() > maxRun;
  final end = Offset(fades ? knee.dx + side * maxRun : edge, y + (inkSeed(lane.branch.id) % 5 - 2).toDouble());
  final runLen = (end.dx - knee.dx).abs();
  // The run sways a little (seeded), like a real branch, and droops toward its end.
  final rnd = math.Random(inkSeed('branch:${lane.branch.id}'));
  final sway = (rnd.nextDouble() - 0.5) * w * 0.35;
  final path = Path()
    ..moveTo(start.dx, start.dy)
    ..cubicTo(
      start.dx + side * r * 0.9,
      start.dy + (y - start.dy) * 0.15,
      knee.dx - side * cellWidth * 0.4,
      y,
      knee.dx,
      y,
    )
    ..cubicTo(
      knee.dx + side * runLen * 0.35,
      y + sway,
      knee.dx + side * runLen * 0.7,
      y - sway * 0.6,
      end.dx,
      end.dy,
    );
  final shape = BoughShape.build(
    path,
    style: style,
    w0: w * 1.05,
    w1: w * (fades ? 0.62 : 0.85),
    seed: inkSeed('topic>${lane.branch.id}'),
    leaves: false,
  );
  if (shape == null) return null;
  final run = Polyline.sample(path, 2).smoothed(2);
  final visibleEnd = side > 0 ? math.min(end.dx, mapWidth - 6) : math.max(end.dx, 6.0);
  final carving = _planCarving(
    branch: lane.branch,
    run: run,
    shape: shape,
    side: lane.side,
    from: knee.dx - side * w * 0.2,
    to: fades ? knee.dx + side * maxRun * 0.66 : visibleEnd - side * (metrics.fontSize + 6),
    avoid: avoid,
    fontSize: metrics.fontSize * scaler.scale(1).clamp(1.0, 1.3),
  );
  return BranchPlan(
    branch: lane.branch,
    side: lane.side,
    lane: lane.lane,
    shape: shape,
    run: run,
    hitHalf: metrics.hitHalf,
    carving: carving,
    fade: fades ? (knee.dx + side * maxRun * 0.62, end.dx) : null,
  );
}

/// The arc length of [line] at each point.
List<double> _arcLengths(Polyline line) {
  final out = List<double>.filled(line.length, 0);
  for (var i = 1; i < line.length; i++) {
    out[i] = out[i - 1] + (line.points[i] - line.points[i - 1]).distance;
  }
  return out;
}

/// The point and the tangent angle at arc length [s] of [line].
(Offset, double) _at(Polyline line, List<double> arc, double s) {
  final n = line.length;
  if (s <= 0) return (line.points.first, math.atan2(line.tangents.first.dy, line.tangents.first.dx));
  var i = 1;
  while (i < n - 1 && arc[i] < s) {
    i++;
  }
  final a = arc[i - 1], b = arc[i];
  final t = b - a <= 0 ? 0.0 : ((s - a) / (b - a)).clamp(0.0, 1.0);
  final p = Offset.lerp(line.points[i - 1], line.points[i], t)!;
  final tan = line.tangents[i - 1] * (1 - t) + line.tangents[i] * t;
  return (p, math.atan2(tan.dy, tan.dx));
}

/// The arc length of [line] where it first reaches x = [x] (moving in [side]).
double _arcAtX(Polyline line, List<double> arc, double x, int side) {
  for (var i = 1; i < line.length; i++) {
    final a = line.points[i - 1].dx, b = line.points[i].dx;
    if ((side > 0 && a <= x && x <= b) || (side < 0 && b <= x && x <= a)) {
      final t = (b - a).abs() < 1e-6 ? 0.0 : (x - a) / (b - a);
      return arc[i - 1] + (arc[i] - arc[i - 1]) * t;
    }
  }
  return side > 0 ? (x <= line.points.first.dx ? 0 : arc.last) : (x >= line.points.first.dx ? 0 : arc.last);
}

/// The bark's cross-section at [p] across [nrm] (a unit normal): where the
/// line through [p] along [nrm] meets each of [shape]'s two outlines (the
/// nearest crossing on each), as the middle between them and the thickness.
/// Null where the line misses an outline (past the branch's ends).
({Offset centre, double thickness})? branchCrossSection(BoughShape shape, Offset p, Offset nrm) {
  final hits = <double>[];
  for (final o in shape.outlines) {
    double? best;
    final pts = o.points;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      // Solve p + nrm * t = a + (b - a) * u, 0 <= u <= 1.
      final e = b - a;
      final den = nrm.dx * e.dy - nrm.dy * e.dx;
      if (den.abs() < 1e-9) continue;
      final ap = a - p;
      final t = (ap.dx * e.dy - ap.dy * e.dx) / den;
      final u = (ap.dx * nrm.dy - ap.dy * nrm.dx) / den;
      if (u < 0 || u > 1) continue;
      if (best == null || t.abs() < best.abs()) best = t;
    }
    if (best == null) return null;
    hits.add(best);
  }
  if (hits.length != 2) return null;
  return (centre: p + nrm * ((hits[0] + hits[1]) / 2), thickness: (hits[0] - hits[1]).abs());
}

/// Picks the longest stretch of the run in [from]..[to] that no other bough
/// crosses, and fits the title there with the arrow (else the short title;
/// else the title or the short title without the arrow, since the name is the
/// only thing that says where the branch goes; else only the arrow); the
/// letters read left to right whichever way the branch runs, and the arrow
/// sits at the end toward the edge.
Carving? _planCarving({
  required TopicBranch branch,
  required Polyline run,
  required BoughShape shape,
  required int side,
  required double from,
  required double to,
  required List<(double, double)> avoid,
  required double fontSize,
}) {
  var lo = math.min(from, to), hi = math.max(from, to);
  if (hi - lo < 24) return null;
  // Free stretches between the crossing boughs.
  final blocks = [for (final a in avoid) if (a.$2 > lo && a.$1 < hi) a]..sort((a, b) => a.$1.compareTo(b.$1));
  var best = (lo, lo);
  var x = lo;
  for (final b in blocks) {
    if (b.$1 - 3 - x > best.$2 - best.$1) best = (x, b.$1 - 3);
    x = math.max(x, b.$2 + 3);
  }
  if (hi - x > best.$2 - best.$1) best = (x, hi);
  lo = best.$1;
  hi = best.$2;
  final room = hi - lo;
  final arrowLen = fontSize * 1.9;
  final gap = fontSize * 0.55 + 4;

  TextPainter measure(String t, double size) => TextPainter(
    text: TextSpan(text: t, style: carvingTextStyle(size)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  String? text;
  TextPainter? tp;
  var size = fontSize;
  var arrow = true;
  search:
  for (final withArrow in const [true, false]) {
    for (final candidate in [branch.title, if (branch.shortTitle != branch.title) branch.shortTitle]) {
      for (final s in [fontSize, math.max(12.0, fontSize * 0.86), math.max(12.0, fontSize * 0.74)]) {
        final p = measure(candidate, s);
        if (p.width + (withArrow ? gap + arrowLen : 0) <= room) {
          text = candidate;
          tp = p;
          size = s;
          arrow = withArrow;
          break search;
        }
        p.dispose();
      }
    }
  }
  final textWidth = tp?.width ?? 0;
  final total = textWidth + (text != null && arrow ? gap : 0) + (arrow ? arrowLen : 0);
  if (total > room) return null;

  final arc = _arcLengths(run);
  // The group starts near the knee: on the right after it, on the left before it.
  final startX = side > 0 ? lo + 2 : hi - 2 - total;
  // Left to right along x: [arrow?][text] for a left branch, [text][arrow] for a right one.
  final glyphs = <CarvedGlyph>[];
  // On the bark's own middle: halfway between its two outlines across the
  // run (the bark tapers, swells at the knuckles and wobbles a little, so the
  // middle is measured where each letter goes, not taken from the run).
  Offset onRun(double atX) {
    final s = _arcAtX(run, arc, atX, side);
    final (p, a) = _at(run, arc, s);
    final nrm = Offset(-math.sin(a), math.cos(a));
    return branchCrossSection(shape, p, nrm)?.centre ?? p;
  }

  double angleAt(double atX) {
    final s = _arcAtX(run, arc, atX, side);
    var (_, a) = _at(run, arc, s);
    // Letters stay upright: read left to right.
    if (math.cos(a) < 0) a += math.pi;
    return a;
  }

  final textX = side > 0 || !arrow ? startX : startX + arrowLen + gap;
  // (The fletching reaches back toward the letters; the gap keeps them apart.)
  if (text != null && tp != null) {
    var i = 0;
    for (final ch in text.characters) {
      final n = ch.length;
      final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + n));
      i += n;
      if (boxes.isEmpty || ch.trim().isEmpty) continue;
      final cx = textX + (boxes.first.left + boxes.last.right) / 2;
      glyphs.add((char: ch, center: onRun(cx), angle: angleAt(cx)));
    }
  }
  tp?.dispose();

  var bounds = Rect.zero;
  for (final g in glyphs) {
    final r = Rect.fromCircle(center: g.center, radius: size * 0.75);
    bounds = bounds == Rect.zero ? r : bounds.expandToInclude(r);
  }
  if (!arrow) {
    return Carving(
      text: text!,
      fontSize: size,
      glyphs: glyphs,
      shaft: Polyline(const [], const []),
      head: const [],
      tail: const [],
      bounds: bounds,
    );
  }

  // The arrow: a shaft along the branch, a head toward the edge, fletching at the tail.
  final a0 = side > 0 ? textX + textWidth + (text == null ? 0 : gap) : startX;
  final a1 = a0 + arrowLen;
  final shaftPts = <Offset>[];
  final shaftTans = <Offset>[];
  for (var k = 0; k <= 12; k++) {
    final ax = side > 0 ? a0 + (a1 - a0) * k / 12 : a1 - (a1 - a0) * k / 12;
    shaftPts.add(onRun(ax));
    final ang = angleAt(ax) + (side > 0 ? 0 : math.pi);
    shaftTans.add(Offset(math.cos(ang), math.sin(ang)));
  }
  final shaft = Polyline(shaftPts, shaftTans);
  final tipAng = math.atan2(shaftTans.last.dy, shaftTans.last.dx);
  final tip = shaftPts.last;
  final hl = size * 0.62;
  Polyline barb(double turn) {
    final a = tipAng + math.pi + turn;
    final q = tip + Offset(math.cos(a), math.sin(a)) * hl;
    return Polyline.sample(Path()
      ..moveTo(q.dx, q.dy)
      ..lineTo(tip.dx, tip.dy), 1.5);
  }

  final tailAng = math.atan2(shaftTans.first.dy, shaftTans.first.dx);
  final tailBase = shaftPts.first;
  List<Polyline> fletch(double along) {
    final base = tailBase + Offset(math.cos(tailAng), math.sin(tailAng)) * along;
    return [
      for (final turn in const [0.75, -0.75])
        Polyline.sample(
          Path()
            ..moveTo(base.dx + math.cos(tailAng + math.pi + turn) * size * 0.42,
                base.dy + math.sin(tailAng + math.pi + turn) * size * 0.42)
            ..lineTo(base.dx, base.dy),
          1.5,
        ),
    ];
  }

  final shaftBounds = Rect.fromPoints(shaftPts.first, shaftPts.last).inflate(size * 0.7);
  bounds = bounds == Rect.zero ? shaftBounds : bounds.expandToInclude(shaftBounds);
  return Carving(
    text: text ?? '',
    fontSize: size,
    glyphs: glyphs,
    shaft: shaft,
    head: [barb(0.6), barb(-0.6)],
    tail: [...fletch(size * 0.15), ...fletch(size * 0.55)],
    bounds: bounds,
  );
}

/// The semantics of a topic's branch: "Go to Food and cooking, topic, 1 of 4
/// skills started", plus that it opens after its anchor while locked.
String topicBranchLabel(TopicBranch branch) => [
  'Go to ${branch.title}',
  'topic',
  if (branch.progress.isNotEmpty) branch.progress,
  if (branch.locked) 'opens after its first skill on this tree; you can look around already',
].join(', ');

/// The way into a topic: its branch on the main map. Laid over the branch's
/// [BranchPlan.hitBounds] (map coordinates; [plan]), it takes taps within
/// [BranchPlan.hitHalf] of the branch's centre line (a band at least 48 dp
/// thick along the bark and the carving) and calls [onTap]. It is a button
/// for semantics ([topicBranchLabel]) and for the keyboard (focusable, Enter
/// or Space opens the topic).
///
/// The branch itself stays in the map's raster tiles; this only paints while
/// pressed or focused ([paintBranchPressed]: the bark and carving lighten; in
/// black & white the branch turns black with a white carving), fading in and
/// out in a short moment (at once with [reduceMotion] or in black & white).
class TopicBranchTarget extends StatefulWidget {
  const TopicBranchTarget({
    super.key,
    required this.plan,
    required this.ink,
    required this.onTap,
    this.mono = false,
    this.reduceMotion = false,
  });

  final BranchPlan plan;

  /// The ink the branch is painted in (the locked ink while locked).
  final MapInk ink;
  final VoidCallback onTap;
  final bool mono;
  final bool reduceMotion;

  @override
  State<TopicBranchTarget> createState() => TopicBranchTargetState();
}

class TopicBranchTargetState extends State<TopicBranchTarget> with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 220),
  );
  final FocusNode focusNode = FocusNode(debugLabel: 'topic branch');
  bool _down = false;
  bool _focused = false;

  /// How far the pressed look is shown (0: not at all, 1: fully).
  @visibleForTesting
  double get pressed => _press.value;

  bool get _instant => widget.reduceMotion || widget.mono;

  void _setDown(bool down) {
    _down = down;
    if (_instant) {
      _press.value = down ? 1 : 0;
    } else if (down) {
      _press.forward();
    } else {
      // A quick tap still shows the pressed look for a moment.
      _press.animateTo(1, duration: const Duration(milliseconds: 60)).whenCompleteOrCancel(() {
        if (mounted && !_down) _press.reverse();
      });
    }
  }

  void _activate() {
    if (_instant || !mounted) {
      widget.onTap();
      return;
    }
    // Keyboard: a short flash of the pressed look.
    _setDown(true);
    _setDown(false);
    widget.onTap();
  }

  @override
  void dispose() {
    _press.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return Semantics(
      container: true,
      button: true,
      label: topicBranchLabel(plan.branch),
      onTap: widget.onTap,
      child: FocusableActionDetector(
        focusNode: focusNode,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _activate();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          excludeFromSemantics: true,
          onTapDown: (_) => _setDown(true),
          onTapUp: (_) => _setDown(false),
          onTapCancel: () => _setDown(false),
          onTap: widget.onTap,
          child: RepaintBoundary(
            child: CustomPaint(
              size: plan.hitBounds.size,
              painter: _BranchPressPainter(
                plan: plan,
                ink: widget.ink,
                mono: widget.mono,
                press: _press,
                focused: _focused,
                focusColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the pressed (or focused) look of a branch over the raster and says
/// which points are on the branch (the tap band).
class _BranchPressPainter extends CustomPainter {
  _BranchPressPainter({
    required this.plan,
    required this.ink,
    required this.mono,
    required this.press,
    required this.focused,
    required this.focusColor,
  }) : super(repaint: press);

  final BranchPlan plan;
  final MapInk ink;
  final bool mono;
  final Animation<double> press;
  final bool focused;
  final Color focusColor;

  @override
  void paint(Canvas canvas, Size size) {
    final t = press.value;
    if (t <= 0 && !focused) return;
    canvas.translate(-plan.hitBounds.left, -plan.hitBounds.top);
    if (t > 0) paintBranchPressed(canvas, plan, ink, mono: mono, amount: t);
    if (focused) paintBranchFocus(canvas, plan, mono ? kBwBlack : focusColor);
  }

  @override
  bool hitTest(Offset position) => plan.hits(position + plan.hitBounds.topLeft);

  @override
  bool shouldRepaint(_BranchPressPainter old) =>
      old.plan != plan || old.ink != ink || old.mono != mono || old.focused != focused || old.focusColor != focusColor;
}

/// The pressed look of [plan]'s branch, [amount] (0–1) of the way in: the bark
/// and its carving lighten (a pale wash screened over the silhouette, fading out with
/// the branch on very wide maps); in black & white ([mono]) the branch turns
/// black with its carving white (no gray in between: shown fully from any
/// [amount]).
void paintBranchPressed(Canvas canvas, BranchPlan plan, MapInk ink, {required bool mono, double amount = 1}) {
  final s = plan.shape;
  if (mono) {
    canvas.drawPath(s.silhouette, Paint()..color = kBwBlack);
    if (plan.carving case final c?) _paintCarving(canvas, c, ink, mono: true, locked: false, colour: kBwWhite);
    return;
  }
  // Screened, so it only ever lightens (the pale letters stay as pale).
  final wash = ink.cream.withValues(alpha: 0.32 * amount.clamp(0.0, 1.0));
  final paint = Paint()
    ..color = wash
    ..blendMode = BlendMode.screen;
  if (plan.fade case (final x0, final x1)) {
    paint.shader = ui.Gradient.linear(Offset(x0, 0), Offset(x1, 0), [wash, wash.withValues(alpha: 0)]);
  }
  canvas.drawPath(s.silhouette, paint);
}

/// The keyboard focus look of [plan]'s branch: an outline of its tap band in [colour].
void paintBranchFocus(Canvas canvas, BranchPlan plan, Color colour) {
  canvas.drawPath(
    bandPath(plan.run, (_, _) => plan.hitHalf - 3),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = colour,
  );
}

/// The x intervals where [shapes] cross the horizontal band [top]..[bottom]: an
/// `avoid` for [buildBranch] when the branch is painted behind other boughs
/// (the map paints it in front, so it passes none).
List<(double, double)> crossings(Iterable<BoughShape> shapes, double top, double bottom) {
  final out = <(double, double)>[];
  for (final s in shapes) {
    if (s.bounds.bottom < top || s.bounds.top > bottom) continue;
    double? lo, hi;
    for (final o in s.outlines) {
      for (final p in o.points) {
        if (p.dy < top || p.dy > bottom) continue;
        lo = lo == null ? p.dx : math.min(lo, p.dx);
        hi = hi == null ? p.dx : math.max(hi, p.dx);
      }
    }
    if (lo != null && hi != null) out.add((lo - 2, hi + 2));
  }
  return out;
}

/// Paints [plan]: the bark (fading out on very wide maps), the grain and
/// hatching (kept off the letters), the outline, and the carving: letters and
/// an arrow cut into the bark ([carvingColours]: very pale wood with a bright
/// lower-left wall and a shaded upper-right edge, the light coming from the
/// top right); in black & white it is a black incised line on the white bark.
void paintBranch(Canvas canvas, BranchPlan plan, MapInk ink, BranchStyle style, {required bool mono, bool locked = false}) {
  final s = plan.shape;
  final fade = plan.fade;
  if (fade != null && !mono) {
    canvas.saveLayer(s.bounds.inflate(6), Paint());
  }
  canvas.drawPath(s.silhouette, Paint()..color = ink.bark);
  final carving = plan.carving;
  final keepOff = carving == null ? null : _carvingMask(carving);
  canvas.save();
  if (keepOff != null) {
    canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(s.bounds.inflate(8)), keepOff));
  }
  canvas.drawPath(
    s.grain,
    Paint()
      ..color = ink.ink.withValues(alpha: ink.ink.a * style.grainOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.grainWidth
      ..strokeCap = StrokeCap.round,
  );
  hatchRegion(canvas, s.shadow, ink.ink,
      angleDeg: s.hatchAngle,
      spacing: style.hatchSpacing,
      width: style.hatchWidth,
      seed: s.seed,
      opacity: ink.hatchOpacity >= 1 ? 1 : style.hatchOpacity);
  for (var k = 0; k < s.creases.length; k++) {
    inkStroke(canvas, s.creases[k], ink.ink, wmin: 1.2, wmax: 1.8, profile: 'taper', seed: s.seed + k);
  }
  canvas.restore();
  for (var k = 0; k < s.outlines.length; k++) {
    inkStroke(canvas, s.outlines[k], ink.ink,
        wmin: style.outlineMin, wmax: style.outlineMax, wobble: style.wobble * 0.6, seed: s.seed + (k == 0 ? 1 : -1));
  }
  if (carving != null) _paintCarving(canvas, carving, ink, mono: mono, locked: locked);
  if (fade != null && !mono) {
    // Fade the far end out (dstIn keeps the branch where the mask is opaque).
    final (x0, x1) = fade;
    canvas.drawRect(
      s.bounds.inflate(6),
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(Offset(x0, 0), Offset(x1, 0), const [Color(0xFF000000), Color(0x00000000)]),
    );
    canvas.restore();
  }
}

/// The area round the letters and the arrow, kept clear of grain and hatching.
Path _carvingMask(Carving c) {
  final p = Path();
  // Round each letter's optical middle: wide enough for the ascenders and
  // descenders (the letters sit in the bark's middle).
  final r = c.fontSize * 0.68;
  for (final g in c.glyphs) {
    p.addOval(Rect.fromCircle(center: g.center, radius: r));
  }
  for (final q in c.shaft.points) {
    p.addOval(Rect.fromCircle(center: q, radius: c.fontSize * 0.32));
  }
  for (final l in [...c.head, ...c.tail]) {
    for (final q in l.points) {
      p.addOval(Rect.fromCircle(center: q, radius: c.fontSize * 0.25));
    }
  }
  return p;
}

/// The colours of a cut into the bark: its floor, its lit wall and its shaded wall.
({Color floor, Color lit, Color shade}) carvingColours(MapInk ink, {required bool mono, bool locked = false}) {
  if (mono) {
    final c = locked ? kBwGray : kBwBlack;
    return (floor: c, lit: c, shade: c);
  }
  // A cut shows the pale wood under the bark: the letters are very light (the
  // cream lifted toward white), with a bright wall on the lower left (the
  // light comes from the top right) and a dark wall on the upper right that
  // makes them read as cut in, not stuck on. On the dark theme's lighter bark
  // the dark wall is the full ink, so the pale letters still stand out.
  final lightBark = ink.bark.computeLuminance() > 0.2;
  const white = Color(0xFFFFFFFF);
  if (locked) {
    return (
      floor: Color.lerp(ink.bark, ink.cream, 0.75)!,
      lit: Color.lerp(ink.bark, ink.cream, 0.9)!,
      shade: Color.lerp(ink.barkDark, ink.ink, 0.5)!.withValues(alpha: 0.65),
    );
  }
  return (
    floor: Color.lerp(ink.cream, white, lightBark ? 0.55 : 0.4)!,
    lit: Color.lerp(ink.cream, white, 0.85)!,
    shade: lightBark ? ink.ink : Color.lerp(ink.barkDark, ink.ink, 0.7)!.withValues(alpha: 0.9),
  );
}

/// [colour] replaces the colours of a black & white ([mono]) cut (the pressed look's white).
void _paintCarving(Canvas canvas, Carving c, MapInk ink, {required bool mono, required bool locked, Color? colour}) {
  final colours = carvingColours(ink, mono: mono, locked: locked);
  final style = carvingTextStyle(c.fontSize);
  final bounds = c.bounds.inflate(4);
  // On the dark theme's lighter bark the walls are a little wider, so the pale
  // letters keep a clear edge.
  final k = (c.fontSize / 14).clamp(0.75, 1.3) * (ink.bark.computeLuminance() > 0.2 ? 1.35 : 1.0);
  // Shifts in screen space; the bands they uncover are the walls of the cut.
  final towardLight = Offset(0.5, -0.5) * k; // uncovers the lower-left (lit) wall
  final awayFromLight = Offset(-0.8, 0.8) * k; // uncovers the upper-right (shaded) wall
  final lw = math.max(1.8, c.fontSize * 0.17);

  void glyphs(Color color, Offset shift) {
    for (final g in c.glyphs) {
      final tp = TextPainter(
        text: TextSpan(text: g.char, style: style.copyWith(color: color)),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(g.center.dx + shift.dx, g.center.dy + shift.dy);
      canvas.rotate(g.angle);
      tp.paint(canvas, carvedGlyphOrigin(tp, c.fontSize));
      canvas.restore();
      tp.dispose();
    }
  }

  void strokes(Color color, Offset shift) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = lw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final l in [c.shaft, ...c.head, ...c.tail]) {
      final path = Path();
      for (var i = 0; i < l.length; i++) {
        final q = l.points[i] + shift;
        i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  void cut(Color color, Offset shift) {
    glyphs(color, shift);
    strokes(color, shift);
  }

  if (mono) {
    // Black & white: black incised lines on the white bark.
    cut(colour ?? colours.floor, Offset.zero);
    return;
  }
  canvas.saveLayer(bounds, Paint());
  // The whole cut as the lit wall, then the shade where the cut shifted toward
  // the light still covers it (all but the lower-left wall)...
  cut(colours.lit, Offset.zero);
  canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.srcATop);
  cut(colours.shade, towardLight);
  canvas.restore();
  // ...and the floor inside both walls.
  canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.srcATop);
  cut(colours.floor, awayFromLight);
  canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
  cut(const Color(0xFF000000), towardLight);
  canvas.restore();
  canvas.restore();
  canvas.restore();
}

