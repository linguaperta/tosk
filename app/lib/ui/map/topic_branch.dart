/// Topic branches on the main map (docs/extensions.md, docs/ui.md "Topic
/// branches"): at each topic's anchor skill a side branch grows off the node
/// and runs out of the map's edge (on very wide maps it fades out instead).
/// Along it the topic's name and an arrow toward the edge are carved into the
/// bark itself, following the branch's curve; a "Go to …" button sits under
/// it. The branch and its carving are static art: they are painted into the
/// map's bough raster tiles (`map_raster.dart`) like the boughs.
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

  /// Room between the branch and the button under it.
  static const double buttonGap = 6;

  /// Height of the button ("Go to …").
  static const double buttonHeight = 48;

  /// A lane: the branch, the button and a margin.
  double get laneHeight => 4 + width + buttonGap + buttonHeight + 10;

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

/// One carved letter: its centre on the branch and its angle.
typedef CarvedGlyph = ({String char, Offset center, double angle});

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

  /// The arrow's shaft and head (toward the edge) and the fletching at its tail.
  final Polyline shaft;
  final List<Polyline> head;
  final List<Polyline> tail;

  /// Everything the carving covers.
  final Rect bounds;
}

/// A planned branch: its bough, carving, button room and fade.
class BranchPlan {
  BranchPlan({
    required this.branch,
    required this.side,
    required this.lane,
    required this.shape,
    required this.run,
    required this.buttonSlot,
    required this.buttonX,
    required this.carving,
    required this.fade,
  });

  /// Where the button starts (a right branch) or ends (a left one), in map x.
  final double buttonX;

  final TopicBranch branch;
  final int side;
  final int lane;

  /// The branch's bark, outline and grain (a bough without twig and leaf).
  final BoughShape shape;

  /// The centre line, sampled (stone → edge).
  final Polyline run;

  /// The room for the "Go to …" button: its left and right limits, top and height.
  final Rect buttonSlot;
  final Carving? carving;

  /// Where the branch fades out (x from opaque to clear), on very wide maps; null when it runs off the edge.
  final (double, double)? fade;

  /// Everything the branch paints.
  late final Rect bounds = shape.bounds;
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
  final y = laneTop + 4 + w / 2;
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
    side: lane.side,
    from: knee.dx - side * w * 0.2,
    to: fades ? knee.dx + side * maxRun * 0.66 : visibleEnd - side * (metrics.fontSize + 6),
    avoid: avoid,
    fontSize: metrics.fontSize * scaler.scale(1).clamp(1.0, 1.3),
    branchWidth: w,
  );
  final buttonTop = y + w / 2 + BranchMetrics.buttonGap;
  // The whole lane; the button starts under the carving (a right branch) or
  // ends under it (a left one), shifted to fit ([TopicButtonLayout]).
  final slot = Rect.fromLTRB(8, buttonTop, mapWidth - 8, buttonTop + BranchMetrics.buttonHeight);
  final buttonX = carving == null
      ? knee.dx
      : side > 0
      ? carving.bounds.left + carving.fontSize * 0.5
      : carving.bounds.right - carving.fontSize * 0.5;
  return BranchPlan(
    branch: lane.branch,
    side: lane.side,
    lane: lane.lane,
    shape: shape,
    run: run,
    buttonSlot: slot,
    buttonX: buttonX,
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

/// Picks the longest stretch of the run in [from]..[to] that no other bough
/// crosses, and fits the title there (else the short title, else only the
/// arrow); the letters read left to right whichever way the branch runs, and
/// the arrow sits at the end toward the edge.
Carving? _planCarving({
  required TopicBranch branch,
  required Polyline run,
  required int side,
  required double from,
  required double to,
  required List<(double, double)> avoid,
  required double fontSize,
  required double branchWidth,
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
  for (final candidate in [branch.title, if (branch.shortTitle != branch.title) branch.shortTitle]) {
    for (final s in [fontSize, math.max(12.0, fontSize * 0.86), math.max(12.0, fontSize * 0.74)]) {
      final p = measure(candidate, s);
      if (p.width + gap + arrowLen <= room) {
        text = candidate;
        tp = p;
        size = s;
        break;
      }
      p.dispose();
    }
    if (text != null) break;
  }
  final textWidth = tp?.width ?? 0;
  final total = textWidth + (text == null ? 0 : gap) + arrowLen;
  if (total > room) return null;

  final arc = _arcLengths(run);
  // The group starts near the knee: on the right after it, on the left before it.
  final startX = side > 0 ? lo + 2 : hi - 2 - total;
  // Left to right along x: [arrow?][text] for a left branch, [text][arrow] for a right one.
  final glyphs = <CarvedGlyph>[];
  final lift = branchWidth * 0.06; // a little toward the lit side, off the shadow hatching
  Offset onRun(double atX, {double up = 0}) {
    final s = _arcAtX(run, arc, atX, side);
    final (p, a) = _at(run, arc, s);
    // The normal pointing up (toward the light at the top right).
    final dir = Offset(math.cos(a), math.sin(a));
    var nrm = Offset(dir.dy, -dir.dx);
    if (nrm.dy > 0) nrm = -nrm;
    return p + nrm * up;
  }

  double angleAt(double atX) {
    final s = _arcAtX(run, arc, atX, side);
    var (_, a) = _at(run, arc, s);
    // Letters stay upright: read left to right.
    if (math.cos(a) < 0) a += math.pi;
    return a;
  }

  final textX = side > 0 ? startX : startX + arrowLen + gap;
  // (The fletching reaches back toward the letters; the gap keeps them apart.)
  if (text != null && tp != null) {
    var i = 0;
    for (final ch in text.characters) {
      final n = ch.length;
      final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + n));
      i += n;
      if (boxes.isEmpty || ch.trim().isEmpty) continue;
      final cx = textX + (boxes.first.left + boxes.last.right) / 2;
      glyphs.add((char: ch, center: onRun(cx, up: lift), angle: angleAt(cx)));
    }
  }
  tp?.dispose();

  // The arrow: a shaft along the branch, a head toward the edge, fletching at the tail.
  final a0 = side > 0 ? textX + textWidth + gap : startX;
  final a1 = a0 + arrowLen;
  final shaftPts = <Offset>[];
  final shaftTans = <Offset>[];
  for (var k = 0; k <= 12; k++) {
    final ax = side > 0 ? a0 + (a1 - a0) * k / 12 : a1 - (a1 - a0) * k / 12;
    shaftPts.add(onRun(ax, up: lift));
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

  var bounds = Rect.fromPoints(shaftPts.first, shaftPts.last).inflate(size * 0.7);
  for (final g in glyphs) {
    bounds = bounds.expandToInclude(Rect.fromCircle(center: g.center, radius: size * 0.75));
  }
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

/// "Go to …" (`Go to <topic>`): the clear way into a topic, under its branch (48 dp tall).
/// Its semantics say what it is, the topic's progress and whether its
/// anchor is still ahead.
class TopicButton extends StatelessWidget {
  const TopicButton({super.key, required this.branch, required this.onTap, this.background, this.side = 1});
  final TopicBranch branch;
  final VoidCallback onTap;
  final Color? background;
  final int side;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = isBw(context);
    final fg = branch.locked ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface;
    final label = 'Go to ${branch.title}';
    return Semantics(
      button: true,
      label: [
        label,
        'topic',
        if (branch.progress.isNotEmpty) branch.progress,
        if (branch.locked) 'opens after its first skill on this tree; you can look around already',
      ].join(', '),
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, BranchMetrics.buttonHeight),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: background,
            foregroundColor: fg,
            side: BorderSide(
              color: mono ? kBwBlack : theme.colorScheme.outline,
              width: mono ? kBwBorder : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (branch.locked) ...[Icon(Icons.lock_outline, size: 18, color: fg), const SizedBox(width: 6)],
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(color: fg)),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Places the "Go to …" button in its lane: starting at [x] (a right branch,
/// [side] > 0) or ending there (a left one), moved in to fit the lane.
class TopicButtonLayout extends SingleChildLayoutDelegate {
  const TopicButtonLayout(this.x, this.side);

  /// In the lane's coordinates.
  final double x;
  final int side;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = side > 0 ? x : x - childSize.width;
    return Offset(left.clamp(0.0, math.max(0.0, size.width - childSize.width)), (size.height - childSize.height) / 2);
  }

  @override
  bool shouldRelayout(TopicButtonLayout old) => old.x != x || old.side != side;
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
/// an arrow cut into the bark ([carvingColours]: pale wood with a lit
/// lower-left wall and a shaded upper-right one, the light coming from the top
/// right; a dark groove on a light bark); in black & white it is a black incised line on the white bark.
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
  final r = c.fontSize * 0.55;
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
  // A cut shows the paler wood under the bark: a light wall on the lower left
  // (the light comes from the top right), a dark wall on the upper right. On
  // a light bark (the dark theme's) pale wood wouldn't stand out: there the
  // cut is a dark groove with the same walls.
  if (ink.bark.computeLuminance() > 0.2) {
    return (
      floor: Color.lerp(ink.barkDark, ink.ink, locked ? 0.1 : 0.45)!.withValues(alpha: locked ? 0.6 : 1),
      lit: Color.lerp(ink.bark, ink.cream, locked ? 0.3 : 0.7)!,
      shade: ink.ink.withValues(alpha: locked ? 0.5 : 1),
    );
  }
  return (
    floor: Color.lerp(ink.bark, ink.cream, locked ? 0.3 : 0.62)!,
    lit: Color.lerp(ink.bark, ink.cream, locked ? 0.45 : 0.92)!,
    shade: Color.lerp(ink.barkDark, ink.ink, 0.6)!.withValues(alpha: locked ? 0.5 : 0.95),
  );
}

void _paintCarving(Canvas canvas, Carving c, MapInk ink, {required bool mono, required bool locked}) {
  final colours = carvingColours(ink, mono: mono, locked: locked);
  final style = carvingTextStyle(c.fontSize);
  final bounds = c.bounds.inflate(4);
  final k = (c.fontSize / 14).clamp(0.75, 1.3);
  // Shifts in screen space; the bands they uncover are the walls of the cut.
  final towardLight = Offset(0.55, -0.55) * k; // uncovers the lower-left (lit) wall
  final awayFromLight = Offset(-0.85, 0.85) * k; // uncovers the upper-right (shaded) wall
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
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2 - c.fontSize * 0.04));
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
    cut(colours.floor, Offset.zero);
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

