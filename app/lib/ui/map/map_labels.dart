/// Room for the map's text: how tall a node's title (up to two lines) and its
/// days chip are at the current text size, so the geometry reserves that
/// height under every stone ([MapTextMetrics]); how wide a node's label may
/// be next to its neighbours (`MapGeometry.labelWidth`); and which leaves
/// would hang over a unit title's plaque ([leafTouches]).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tosk_palette.dart';
import 'bough.dart';

/// The text styles of the map (the node title, its days chip and the unit
/// title), shared by the widgets and the measurements.
TextStyle? mapNodeTitleStyle(ThemeData theme) => theme.textTheme.labelMedium;
TextStyle? mapNodeChipStyle(ThemeData theme) => theme.textTheme.labelSmall;
TextStyle? mapBandTitleStyle(ThemeData theme) => theme.textTheme.serifSection?.copyWith(fontSize: 15);

/// Padding of the backing behind a node's title and chip (on the band
/// colour, so boughs passing behind never run through the text).
const EdgeInsets kMapLabelPadding = EdgeInsets.symmetric(horizontal: 4, vertical: 1);

/// Padding of the unit title's plaque round its text (a margin the boughs
/// passing behind the plaque keep from the letters).
const EdgeInsets kMapBandTitlePadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);

/// The unit title's backing sits this far below the band's top.
const double kMapBandTitleTop = 6;

/// Heights of the map's text at the current text scale.
@immutable
class MapTextMetrics {
  const MapTextMetrics({this.titleBlock = 32, this.chipLine = 16, this.headerLine = 20, this.headerBlock = 40});

  /// A node title of two lines.
  final double titleBlock;

  /// The days chip ("2d", "today").
  final double chipLine;

  /// One line of a unit title.
  final double headerLine;

  /// A unit title of two lines (a long title squeezed between boughs).
  final double headerBlock;

  /// The defaults (text scale 1 with the default fonts).
  static const fallback = MapTextMetrics();

  /// Everything under a stone: the title's and the chip's backing.
  double get labelBlock => titleBlock + chipLine + 2 * kMapLabelPadding.vertical;

  /// The unit title's height with [lines] lines (1 or 2).
  double headerText(int lines) => lines >= 2 ? headerBlock : headerLine;

  /// The band header for a unit title of [lines] lines: the title's backing
  /// plus a margin (at least 36 px).
  double headerHeight([int lines = 1]) =>
      math.max(36, kMapBandTitleTop + headerText(lines) + kMapBandTitlePadding.vertical + 2);

  /// Measures the map's text styles in [context] (theme and text scaler).
  static MapTextMetrics of(BuildContext context) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double lines(TextStyle? style, int n) {
      final tp = TextPainter(
        text: TextSpan(text: List.filled(n, 'Hg').join('\n'), style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: n,
      )..layout();
      final h = tp.height;
      tp.dispose();
      // Rounded up, plus a hair for subpixel layout.
      return h.ceilToDouble() + 1;
    }

    return MapTextMetrics(
      titleBlock: lines(mapNodeTitleStyle(theme), 2),
      chipLine: lines(mapNodeChipStyle(theme), 1),
      headerLine: lines(mapBandTitleStyle(theme), 1),
      headerBlock: lines(mapBandTitleStyle(theme), 2),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MapTextMetrics &&
      other.titleBlock == titleBlock &&
      other.chipLine == chipLine &&
      other.headerLine == headerLine &&
      other.headerBlock == headerBlock;

  @override
  int get hashCode => Object.hash(titleBlock, chipLine, headerLine, headerBlock);
}

/// Whether [s]'s twig or the bounding box of its resting leaf reaches into [r].
bool leafTouches(BoughShape s, Rect r) {
  if (s.twig?.points.any(r.contains) ?? false) return true;
  final l = s.leaf;
  if (l == null) return false;
  final hull = leafHull(l);
  var box = Rect.fromPoints(hull.first, hull.first);
  for (final p in hull) {
    box = box.expandToInclude(Rect.fromPoints(p, p));
  }
  return box.overlaps(r);
}

/// A closed outline around an ash leaf at rest (`paintAshLeaf`: the stem
/// 92 units, the terminal leaflet about 38 beyond it, leaflets about 33 to
/// each side), in map coordinates.
List<Offset> leafHull(LeafSpot l) {
  final c = math.cos(l.angle), s = math.sin(l.angle);
  Offset at(double x, double y) => l.tip + Offset(c * x - s * y, s * x + c * y) * l.scale;
  return [at(0, 0), at(20, -34), at(70, -38), at(132, -6), at(132, 6), at(70, 38), at(20, 34), at(0, 0)];
}
