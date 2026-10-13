import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../map/skill_stats.dart';

/// A swappable visual style: app theme plus everything the skill map draws.
///
/// The default skin is a clean Material 3 look. A forest skin (regions,
/// overgrowth for decay, lanterns for gold) can be added later by implementing
/// this class and overriding `skinProvider`.
abstract class Skin {
  const Skin();

  String get id;
  String get name;

  /// Seed for the Material 3 color scheme.
  Color get seedColor;

  ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  /// Map colors and shapes for the given scheme.
  MapStyle mapStyle(ColorScheme scheme);
}

/// Everything the map painter and nodes need from a [Skin].
@immutable
class MapStyle {
  const MapStyle({
    required this.vocabColor,
    required this.grammarColor,
    required this.lockedColor,
    required this.ringTrack,
    required this.ringColor,
    required this.edgeColor,
    required this.bandColors,
    required this.bandTitleColor,
    required this.onNode,
    this.nodeShape = const CircleBorder(),
    this.edgePainter = const CurvedEdgePainter(),
  });

  final Color vocabColor;
  final Color grammarColor;
  final Color lockedColor;
  final Color ringTrack;
  final Color ringColor;
  final Color edgeColor;

  /// Alternating backgrounds for unit bands.
  final List<Color> bandColors;
  final Color bandTitleColor;

  /// Icon color on a node.
  final Color onNode;
  final ShapeBorder nodeShape;
  final EdgePainter edgePainter;

  Color nodeColor(SkillKind kind) => kind == SkillKind.vocab ? vocabColor : grammarColor;

  Color bandColor(int index) => bandColors[index % bandColors.length];

  Color tierColor(MapTier tier) => switch (tier) {
    MapTier.gold => const Color(0xFFE6B422),
    MapTier.silver => const Color(0xFFA8B2BD),
    MapTier.bronze => const Color(0xFFC07A45),
    MapTier.started => ringColor,
    MapTier.available => ringTrack,
    MapTier.locked => lockedColor,
  };
}

/// Draws one prerequisite edge between two node centers (bottom of [from] to top of [to]).
abstract class EdgePainter {
  const EdgePainter();
  void paint(Canvas canvas, Offset from, Offset to, Paint paint);
}

/// Smooth vertical S-curve.
class CurvedEdgePainter extends EdgePainter {
  const CurvedEdgePainter();

  @override
  void paint(Canvas canvas, Offset from, Offset to, Paint paint) {
    final dy = (to.dy - from.dy).abs();
    final bend = math.max(24.0, dy * 0.5);
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(from.dx, from.dy + bend, to.dx, to.dy - bend, to.dx, to.dy);
    canvas.drawPath(path, paint);
  }
}

class DefaultSkin extends Skin {
  const DefaultSkin();

  @override
  String get id => 'default';
  @override
  String get name => 'Default';
  @override
  Color get seedColor => const Color(0xFF2E7D32);

  @override
  MapStyle mapStyle(ColorScheme scheme) => MapStyle(
    vocabColor: scheme.primary,
    grammarColor: scheme.tertiary,
    lockedColor: scheme.outline,
    ringTrack: scheme.outlineVariant,
    ringColor: scheme.secondary,
    edgeColor: scheme.outlineVariant,
    bandColors: [scheme.surfaceContainerLow, scheme.surfaceContainer],
    bandTitleColor: scheme.onSurfaceVariant,
    onNode: scheme.brightness == Brightness.dark ? scheme.surface : Colors.white,
  );
}
