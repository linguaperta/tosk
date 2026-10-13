import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../theme/skin.dart';
import 'map_layout.dart';
import 'skill_node.dart';
import 'skill_stats.dart';

/// Pixel geometry derived from a [MapLayout] for a given available width and zoom.
class MapGeometry {
  MapGeometry({required this.layout, required double availableWidth, required this.zoom}) {
    final cols = math.max(1.0, layout.columns);
    final fit = (availableWidth - 2 * hPad) / cols;
    cellWidth = math.max(64.0, math.min(112.0, fit) * zoom);
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
                    decoration: BoxDecoration(color: style.bandColor(b.index), borderRadius: BorderRadius.circular(16)),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
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
        ..color = lockedSkills.contains(e.to) ? style.edgeColor.withValues(alpha: 0.5) : style.edgeColor;
      final from = geometry.ringCenter(a);
      final to = geometry.ringCenter(b);
      if (to.dy > from.dy) {
        style.edgePainter.paint(canvas, from + Offset(0, r), to - Offset(0, r), paint);
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

  @override
  bool shouldRepaint(MapEdgesPainter old) =>
      old.layout != layout ||
      old.geometry.cellWidth != geometry.cellWidth ||
      old.geometry.width != geometry.width ||
      old.style != style ||
      old.lockedSkills.length != lockedSkills.length;
}
