import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tosk_palette.dart';
import '../../core/core.dart';
import '../brand/tosk.dart';
import '../theme/bw_skin.dart';
import '../theme/skin.dart';
import 'branch_style.dart';
import 'ink_art.dart';
import 'map_layout.dart';
import 'skill_node.dart';
import 'skill_stats.dart';

/// Which way the course grows on screen.
///
/// The layout itself is direction-free (bands and rows in course order);
/// [MapGeometry] turns it into pixels. [topDown] puts the first unit at the
/// top and scrolls down (today's map). [bottomUp] puts the roots at the
/// bottom, the first unit lowest and later units above it, so the learner
/// scrolls up as the tree grows; the branch painter draws every bough from
/// its parent to its child whichever is higher, and the marker, bands and
/// titles follow the geometry. To try it, change [kMapDirection] (and have
/// the map screen start scrolled to the bottom).
enum MapDirection { topDown, bottomUp }

/// The one setting for the map's growth direction.
const MapDirection kMapDirection = MapDirection.topDown;

/// Pixel geometry derived from a [MapLayout] for a given available width and zoom.
class MapGeometry {
  MapGeometry({required this.layout, required double availableWidth, required this.zoom, this.direction = kMapDirection}) {
    final cols = math.max(1.0, layout.columns);
    final fit = (availableWidth - 2 * hPad) / cols;
    cellWidth = math.max(64.0, math.min(144.0, fit) * zoom);
    diameter = (cellWidth * 0.6).clamp(40.0, 76.0);
    rowHeight = diameter + 64;
    gridWidth = cols * cellWidth;
    width = math.max(availableWidth, gridWidth + 2 * hPad);
    originX = (width - gridWidth) / 2;
    var y = 0.0;
    final tops = List<double>.filled(layout.bands.length, 0);
    final order = direction == MapDirection.topDown ? layout.bands : layout.bands.reversed;
    for (final b in order) {
      tops[b.index] = y;
      y += bandHeader + b.rowCount * rowHeight + bandGap;
    }
    bandTop.addAll(tops);
    height = y;
  }

  static const hPad = 12.0;
  static const bandHeader = 36.0;
  static const bandGap = 12.0;

  final MapLayout layout;
  final double zoom;
  final MapDirection direction;
  late final double cellWidth;
  late final double diameter;
  late final double rowHeight;
  late final double gridWidth;
  late final double width;
  late final double height;
  late final double originX;

  /// Top of each band, indexed by band index (not by position on screen).
  final List<double> bandTop = [];

  /// The row's position inside its band, counted from the band's top.
  int visualRow(MapNode n) =>
      direction == MapDirection.topDown ? n.row : layout.bands[n.band].rowCount - 1 - n.row;

  /// Top-left of the node's cell.
  Offset cellOrigin(MapNode n) =>
      Offset(originX + n.col * cellWidth, bandTop[n.band] + bandHeader + visualRow(n) * rowHeight);

  /// Center of the node's box (stone, ring and rays).
  Offset ringCenter(MapNode n) => cellOrigin(n) + Offset(cellWidth / 2, 8 + nodeBox / 2);

  /// The node widget's box (at least a 48 px target).
  double get nodeBox => math.max(diameter, 48);
}

/// The first skill in course order that is available or started: where Tosk
/// sits on the map (null when every skill is locked or done).
String? currentSkillId(Iterable<String> skillsInOrder, Map<String, SkillStats> stats) {
  for (final id in skillsInOrder) {
    final tier = stats[id]?.tier ?? MapTier.available;
    if (tier == MapTier.available || tier == MapTier.started) return id;
  }
  return null;
}

/// The skill graph as a tree: unit bands, storybook boughs along the
/// prerequisite edges, stone-medallion nodes and Tosk at the current skill.
/// Scrolls horizontally when zoomed in beyond the available width; the parent
/// scrolls vertically.
class SkillMapView extends StatelessWidget {
  const SkillMapView({
    super.key,
    required this.course,
    required this.layout,
    required this.stats,
    required this.style,
    required this.lang,
    required this.now,
    this.zoom = 1,
    this.reduceMotion = false,
    this.twinkle = false,
    this.branchStyle = BranchStyle.defaults,
    this.showMarker = true,
    this.onTap,
    this.onLongPress,
    this.unitKeys = const {},
    this.storyCounts = const {},
    this.storyUnitsOpen = const {},
    this.onUnitStories,
  });

  /// Stories per unit id: units with stories get a book button in their band
  /// header ([onUnitStories]); [storyUnitsOpen] are the units whose stories
  /// are unlocked (a closed book outline otherwise).
  final Map<String, int> storyCounts;
  final Set<String> storyUnitsOpen;
  final void Function(String unitId)? onUnitStories;

  /// Keys put on each unit band (by unit id), so the map can scroll to one.
  final Map<String, GlobalKey> unitKeys;

  final CourseData course;
  final MapLayout layout;
  final Map<String, SkillStats> stats;
  final MapStyle style;
  final String lang;
  final DateTime now;
  final double zoom;
  final bool reduceMotion;

  /// Animate the medal twinkles.
  final bool twinkle;
  final BranchStyle branchStyle;

  /// Tosk at the current skill.
  final bool showMarker;
  final void Function(Skill skill)? onTap;
  final void Function(Skill skill)? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final g = MapGeometry(layout: layout, availableWidth: constraints.maxWidth, zoom: zoom);
        final unitTitles = {for (final u in course.units) u.id: pickLang(u.title, lang)};
        final current = showMarker
            ? currentSkillId([
                for (final u in course.units)
                  for (final s in course.skills)
                    if (s.unitId == u.id) s.id,
              ], stats)
            : null;
        final markerNode = current == null ? null : layout.node(current);
        final markerSize = (g.diameter * 0.95).clamp(40.0, 56.0);

        final content = SizedBox(
          width: g.width,
          height: g.height,
          child: Stack(
            children: [
              for (final b in layout.bands)
                Positioned(
                  left: 4,
                  right: 4,
                  top: g.bandTop[b.index],
                  height: MapGeometry.bandHeader + b.rowCount * g.rowHeight,
                  child: DecoratedBox(
                    key: unitKeys[b.unitId],
                    decoration: BoxDecoration(
                      color: style.bandColor(b.index),
                      borderRadius: BorderRadius.circular(16),
                      border: style.monochrome ? Border.all(color: kBwBlack, width: kBwBorder) : null,
                    ),
                  ),
                ),
              Positioned.fill(
                child: CustomPaint(
                  painter: MapEdgesPainter(
                    layout: layout,
                    geometry: g,
                    style: style,
                    branchStyle: branchStyle,
                    lockedSkills: {
                      for (final e in stats.entries)
                        if (e.value.tier == MapTier.locked) e.key,
                    },
                  ),
                ),
              ),
              // Unit titles above the branches, on the band color, so a bough
              // passing through a band header never runs through its text.
              for (final b in layout.bands)
                Positioned(
                  left: 4,
                  // Room for the stories button on the right.
                  right: (storyCounts[b.unitId] ?? 0) > 0 && onUnitStories != null ? 4 + _storyButtonWidth : 4,
                  top: g.bandTop[b.index],
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: style.bandColor(b.index),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Text(
                            unitTitles[b.unitId] ?? b.unitId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // A wordmark-style serif title for each bough.
                            style: theme.textTheme.serifSection?.copyWith(color: style.bandTitleColor, fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // The unit's stories: a book and the count at the right end of
              // the band header: the header plus the gap above the nodes (44 px).
              if (onUnitStories != null)
                for (final b in layout.bands)
                  if ((storyCounts[b.unitId] ?? 0) > 0)
                    Positioned(
                      right: 8,
                      top: g.bandTop[b.index],
                      width: _storyButtonWidth,
                      height: _storyButtonHeight,
                      child: _UnitStoriesButton(
                        key: ValueKey('unit-stories-${b.unitId}'),
                        count: storyCounts[b.unitId]!,
                        open: storyUnitsOpen.contains(b.unitId),
                        unitTitle: unitTitles[b.unitId] ?? b.unitId,
                        background: style.bandColor(b.index),
                        foreground: style.bandTitleColor,
                        onTap: () => onUnitStories!(b.unitId),
                      ),
                    ),
              for (final n in layout.nodes)
                if (course.skill(n.skillId) case final skill?)
                  Positioned(
                    left: g.cellOrigin(n).dx,
                    top: g.cellOrigin(n).dy + 8,
                    width: g.cellWidth,
                    height: g.rowHeight - 8,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SkillNode(
                        skill: skill,
                        title: pickLang(skill.title, lang),
                        stats: stats[skill.id] ?? SkillStats.empty,
                        style: style,
                        diameter: g.diameter,
                        now: now,
                        reduceMotion: reduceMotion,
                        twinkle: twinkle,
                        branchStyle: branchStyle,
                        onTap: onTap == null ? null : () => onTap!(skill),
                        onLongPress: onLongPress == null ? null : () => onLongPress!(skill),
                        labelBackground: style.bandColor(n.band),
                      ),
                    ),
                  ),
              // Tosk sits on the current skill's stone (top left, peeking
              // over the ring); decorative, the node underneath is the target.
              if (markerNode != null)
                Positioned(
                  left: g.ringCenter(markerNode).dx - g.nodeBox / 2 - markerSize * 0.7,
                  top: g.ringCenter(markerNode).dy - g.nodeBox / 2 - markerSize * 0.55,
                  width: markerSize,
                  height: markerSize,
                  child: IgnorePointer(
                    child: Semantics(
                      key: const ValueKey('tosk-marker'),
                      label: 'Tosk: continue here',
                      child: ToskImage(pose: ToskPose.marker, height: markerSize),
                    ),
                  ),
                ),
            ],
          ),
        );

        if (g.width <= constraints.maxWidth + 0.5) return content;
        return SingleChildScrollView(
          key: const ValueKey('map-hscroll'),
          scrollDirection: Axis.horizontal,
          child: content,
        );
      },
    );
  }
}

/// Paints the prerequisite edges as storybook boughs: a tapered bark
/// silhouette with knuckles, grain dashes on the lit side, hatching in the
/// shadow, an ink outline whose weight follows the light, and an ash leaf on
/// a twig along the longer ones. Forks and joins come from the layout's
/// edges. Boughs to locked skills are thinner and paler (gray in black &
/// white). Edges that would pass behind another node detour through a free
/// lane ([detourLane]).
class MapEdgesPainter extends CustomPainter {
  MapEdgesPainter({
    required this.layout,
    required this.geometry,
    required this.style,
    this.branchStyle = BranchStyle.defaults,
    this.lockedSkills = const {},
  });
  final MapLayout layout;
  final MapGeometry geometry;
  final MapStyle style;
  final BranchStyle branchStyle;
  final Set<String> lockedSkills;

  @override
  void paint(Canvas canvas, Size size) {
    final r = geometry.diameter / 2;
    final d = geometry.diameter;
    for (final e in layout.edges) {
      final a = layout.node(e.from), b = layout.node(e.to);
      if (a == null || b == null) continue;
      final locked = lockedSkills.contains(e.to);
      final from = geometry.ringCenter(a);
      final to = geometry.ringCenter(b);
      final path = edgePath(a, b, from, to, r);
      if (path == null) continue;
      final seed = inkSeed('${e.from}>${e.to}');
      final scale = locked ? branchStyle.lockedWidthScale : 1.0;
      paintBough(
        canvas,
        path,
        ink: locked ? _lockedInk(style) : style.ink,
        style: branchStyle,
        w0: branchStyle.widthStart * d * scale,
        w1: branchStyle.widthEnd * d * scale,
        seed: seed,
        leaves: !locked,
        leafScale: branchStyle.leafScale * d / 80,
        leafMinLength: branchStyle.leafMinLength * d,
      );
    }
  }

  static MapInk _lockedInk(MapStyle style) => style.monochrome
      ? style.ink.copyWith(ink: kBwGray)
      : style.ink.copyWith(
          bark: Color.lerp(style.ink.bark, style.ink.paper, 0.4),
          ink: style.ink.ink.withValues(alpha: 0.55),
        );

  /// The bough's centre line from the parent's box to the child's, in the
  /// parent→child direction; null when the nodes overlap.
  @visibleForTesting
  Path? edgePath(MapNode a, MapNode b, Offset from, Offset to, double r) {
    final inset = r * 0.5;
    final down = to.dy > from.dy;
    if ((to.dy - from.dy).abs() > 1) {
      final top = down ? from : to;
      final bottom = down ? to : from;
      final topNode = down ? a : b;
      final bottomNode = down ? b : a;
      final lane = detourLane(topNode, bottomNode, top + Offset(0, inset), bottom - Offset(0, inset), r);
      final p = lane != null
          ? _detourPath(top + Offset(0, inset), bottom - Offset(0, inset), lane)
          : const CurvedEdgePainter().path(top + Offset(0, inset), bottom - Offset(0, inset));
      return down ? p : _reversed(p);
    }
    // Same row (pinned nodes): a straight bough between the boxes.
    final v = to - from;
    final len = v.distance;
    if (len <= 2 * inset) return null;
    final u = v / len;
    return Path()
      ..moveTo(from.dx + u.dx * inset, from.dy + u.dy * inset)
      ..lineTo(to.dx - u.dx * inset, to.dy - u.dy * inset);
  }

  static Path _reversed(Path p) {
    final line = Polyline.sample(p, 2);
    final out = Path();
    for (var i = line.length - 1; i >= 0; i--) {
      final q = line.points[i];
      i == line.length - 1 ? out.moveTo(q.dx, q.dy) : out.lineTo(q.dx, q.dy);
    }
    return out;
  }

  /// When the straight edge from [a] to [b] would pass behind another node
  /// (an edge skipping rows, often across unit bands), the x of a free lane
  /// between columns to route it through instead; null when the way is clear.
  @visibleForTesting
  double? detourLane(MapNode a, MapNode b, Offset from, Offset to, double r) {
    final g = geometry;
    final blockers = <Offset>[];
    final between = <Offset>[];
    for (final n in layout.nodes) {
      if (n.skillId == a.skillId || n.skillId == b.skillId) continue;
      final c = g.ringCenter(n);
      if (c.dy <= from.dy + r || c.dy >= to.dy - r) continue;
      between.add(c);
      final t = (c.dy - from.dy) / (to.dy - from.dy);
      final x = from.dx + (to.dx - from.dx) * t;
      // The node plus its title below it.
      if ((c.dx - x).abs() < g.cellWidth * 0.45) blockers.add(c);
    }
    if (blockers.isEmpty) return null;
    // Lanes are the column boundaries; take the one closest to the straight
    // line that no blocker sits on.
    final mid = (from.dx + to.dx) / 2;
    final candidates = <double>[];
    for (var k = 0; k <= 2 * layout.columns.ceil() + 2; k++) {
      candidates.add(g.originX + (k / 2 - 0.5) * g.cellWidth + g.cellWidth / 2);
    }
    candidates.sort((x, y) => (x - mid).abs().compareTo((y - mid).abs()));
    for (final lane in candidates) {
      if (between.every((c) => (c.dx - lane).abs() >= g.cellWidth * 0.45)) return lane;
    }
    return null;
  }

  Path _detourPath(Offset from, Offset to, double lane) {
    final h = geometry.rowHeight;
    final top = Offset(lane, from.dy + h * 0.45);
    final bottom = Offset(lane, to.dy - h * 0.45);
    return Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(from.dx, from.dy + h * 0.25, lane, top.dy - h * 0.2, top.dx, top.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..cubicTo(lane, bottom.dy + h * 0.2, to.dx, to.dy - h * 0.25, to.dx, to.dy);
  }

  @override
  bool shouldRepaint(MapEdgesPainter old) =>
      old.layout != layout ||
      old.geometry.cellWidth != geometry.cellWidth ||
      old.geometry.width != geometry.width ||
      old.geometry.direction != geometry.direction ||
      old.style != style ||
      old.branchStyle != branchStyle ||
      old.lockedSkills.length != lockedSkills.length;
}

/// Draws one bough along [centre] (parent → child), [w0] px wide at the start
/// and [w1] at the end, in the storybook style (see [MapEdgesPainter]).
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
  final line = Polyline.sample(centre, 2.5).smoothed(2);
  if (line.isEmpty) return;
  final n = line.length;
  final rnd = math.Random(seed);
  double length = 0;
  for (var i = 1; i < n; i++) {
    length += (line.points[i] - line.points[i - 1]).distance;
  }
  if (length < 4) return;

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
  canvas.drawPath(silhouette, Paint()..color = ink.bark);

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
  canvas.drawPath(
    grain,
    Paint()
      ..color = ink.ink.withValues(alpha: ink.ink.a * style.grainOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.grainWidth
      ..strokeCap = StrokeCap.round,
  );

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
  hatchRegion(canvas, Path.combine(PathOperation.intersect, shadow, silhouette), ink.ink,
      angleDeg: dirDeg + style.hatchAngle,
      spacing: style.hatchSpacing,
      width: style.hatchWidth,
      seed: seed,
      opacity: ink.hatchOpacity >= 1 ? 1 : style.hatchOpacity);

  // Knuckle creases: a short curved stroke across the bough where it swells.
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
      inkStroke(canvas, Polyline.sample(crease, 2), ink.ink, wmin: 1.2, wmax: 1.8, profile: 'taper', seed: seed + i);
    }
  }

  // The outline: two ink strokes, one per side, heavier in the shadow.
  for (final side in const [1, -1]) {
    final pts = <Offset>[], tans = <Offset>[];
    for (var i = 0; i < n; i++) {
      pts.add(line.points[i] + line.normals[i] * (prof(sAt(i)) / 2 + (side > 0 ? wobbleL[i] : wobbleR[i])) * side.toDouble());
      tans.add(line.tangents[i]);
    }
    inkStroke(canvas, Polyline(pts, tans), ink.ink, wmin: style.outlineMin, wmax: style.outlineMax, wobble: style.wobble * 0.6, seed: seed + side);
  }

  // A leaf on a twig, on the longer boughs.
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
    final twigLine = Polyline.sample(twig, 2).smoothed();
    canvas.drawPath(bandPath(twigLine, (j, _) => (twigW0 + (twigW1 - twigW0) * j / math.max(1, twigLine.length - 1)) / 2), Paint()..color = ink.bark);
    inkStroke(canvas, twigLine, ink.ink, wmin: 1.0 * leafScale, wmax: 1.8 * leafScale, profile: 'flat', seed: seed + 7);
    final leafAngle = math.atan2(nrm.dy, nrm.dx) + (tan.dy.abs() > tan.dx.abs() ? 0.35 : -0.35) * side;
    paintAshLeaf(canvas, tip, leafAngle, leafScale * 0.85, ink, seed: seed + 3);
  }
}

/// +1 when the polyline's left normal faces the light, else -1.
double _litSide(Polyline line) {
  var dot = 0.0;
  for (final nrm in line.normals) {
    dot += nrm.dx * kInkLight.dx + nrm.dy * kInkLight.dy;
  }
  return dot >= 0 ? 1 : -1;
}

const double _storyButtonWidth = 64;
const double _storyButtonHeight = MapGeometry.bandHeader + 8;

/// The book button of a unit band: an open book when the unit's stories are
/// unlocked, an outline otherwise, plus the number of stories.
class _UnitStoriesButton extends StatelessWidget {
  const _UnitStoriesButton({
    super.key,
    required this.count,
    required this.open,
    required this.unitTitle,
    required this.background,
    required this.foreground,
    required this.onTap,
  });
  final int count;
  final bool open;
  final String unitTitle;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mono = isBw(context);
    return Semantics(
      button: true,
      label: '$count ${count == 1 ? 'story' : 'stories'}, $unitTitle${open ? '' : ', locked'}',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Stories',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: mono ? kBwBlack : foreground.withValues(alpha: 0.5), width: mono ? kBwBorder : 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(open ? Icons.menu_book : Icons.menu_book_outlined, size: 18, color: foreground),
                  const SizedBox(width: 4),
                  Text('$count', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foreground)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
