import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../theme/bw_skin.dart';
import '../theme/skin.dart';
import 'map_layout.dart';
import 'skill_node.dart';
import 'skill_stats.dart';

/// Pixel geometry derived from a [MapLayout] for a given available width and zoom.
class MapGeometry {
  MapGeometry({required this.layout, required double availableWidth, required this.zoom}) {
    final cols = math.max(1.0, layout.columns);
    final fit = (availableWidth - 2 * hPad) / cols;
    cellWidth = math.max(64.0, math.min(144.0, fit) * zoom);
    diameter = (cellWidth * 0.6).clamp(40.0, 76.0);
    rowHeight = diameter + 64;
    gridWidth = cols * cellWidth;
    width = math.max(availableWidth, gridWidth + 2 * hPad);
    originX = (width - gridWidth) / 2;
    var y = 0.0;
    for (final b in layout.bands) {
      bandTop.add(y);
      y += bandHeader + b.rowCount * rowHeight + bandGap;
    }
    height = y;
  }

  static const hPad = 12.0;
  static const bandHeader = 36.0;
  static const bandGap = 12.0;

  final MapLayout layout;
  final double zoom;
  late final double cellWidth;
  late final double diameter;
  late final double rowHeight;
  late final double gridWidth;
  late final double width;
  late final double height;
  late final double originX;
  final List<double> bandTop = [];

  /// Top-left of the node's cell.
  Offset cellOrigin(MapNode n) => Offset(originX + n.col * cellWidth, bandTop[n.band] + bandHeader + n.row * rowHeight);

  /// Center of the node's ring.
  Offset ringCenter(MapNode n) => cellOrigin(n) + Offset(cellWidth / 2, 8 + diameter / 2);
}

/// The skill graph: unit bands, prerequisite edges and nodes. Scrolls horizontally
/// when zoomed in beyond the available width; the parent scrolls vertically.
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
    this.onTap,
    this.onLongPress,
  });

  final CourseData course;
  final MapLayout layout;
  final Map<String, SkillStats> stats;
  final MapStyle style;
  final String lang;
  final DateTime now;
  final double zoom;
  final bool reduceMotion;
  final void Function(Skill skill)? onTap;
  final void Function(Skill skill)? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final g = MapGeometry(layout: layout, availableWidth: constraints.maxWidth, zoom: zoom);
        final unitTitles = {for (final u in course.units) u.id: pickLang(u.title, lang)};

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
                    lockedSkills: {
                      for (final e in stats.entries)
                        if (e.value.tier == MapTier.locked) e.key,
                    },
                  ),
                ),
              ),
              // Unit titles above the edges, on the band color, so an edge
              // passing through a band header never runs through its text.
              for (final b in layout.bands)
                Positioned(
                  left: 4,
                  right: 4,
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
                            style: theme.textTheme.titleSmall?.copyWith(color: style.bandTitleColor),
                          ),
                        ),
                      ),
                    ),
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
                        onTap: onTap == null ? null : () => onTap!(skill),
                        onLongPress: onLongPress == null ? null : () => onLongPress!(skill),
                        labelBackground: style.bandColor(n.band),
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

class MapEdgesPainter extends CustomPainter {
  MapEdgesPainter({required this.layout, required this.geometry, required this.style, this.lockedSkills = const {}});
  final MapLayout layout;
  final MapGeometry geometry;
  final MapStyle style;
  final Set<String> lockedSkills;

  @override
  void paint(Canvas canvas, Size size) {
    final r = geometry.diameter / 2;
    for (final e in layout.edges) {
      final a = layout.node(e.from), b = layout.node(e.to);
      if (a == null || b == null) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = lockedSkills.contains(e.to)
            ? (style.monochrome ? kBwGray : style.edgeColor.withValues(alpha: 0.5))
            : style.edgeColor;
      final from = geometry.ringCenter(a);
      final to = geometry.ringCenter(b);
      if (to.dy > from.dy) {
        final lane = detourLane(a, b, from, to, r);
        if (lane != null) {
          _paintDetour(canvas, from + Offset(0, r), to - Offset(0, r), lane, paint);
        } else {
          style.edgePainter.paint(canvas, from + Offset(0, r), to - Offset(0, r), paint);
        }
      } else {
        // Same row or upward (pinned nodes): straight line between ring edges.
        final d = to - from;
        final len = d.distance;
        if (len <= 2 * r) continue;
        final u = d / len;
        canvas.drawLine(from + u * r, to - u * r, paint);
      }
    }
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

  void _paintDetour(Canvas canvas, Offset from, Offset to, double lane, Paint paint) {
    final h = geometry.rowHeight;
    final top = Offset(lane, from.dy + h * 0.45);
    final bottom = Offset(lane, to.dy - h * 0.45);
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(from.dx, from.dy + h * 0.25, lane, top.dy - h * 0.2, top.dx, top.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..cubicTo(lane, bottom.dy + h * 0.2, to.dx, to.dy - h * 0.25, to.dx, to.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MapEdgesPainter old) =>
      old.layout != layout ||
      old.geometry.cellWidth != geometry.cellWidth ||
      old.geometry.width != geometry.width ||
      old.style != style ||
      old.lockedSkills.length != lockedSkills.length;
}
