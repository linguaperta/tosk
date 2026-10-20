import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../map/skill_stats.dart';
import 'tosk_palette.dart';

/// A swappable visual style: app theme plus everything the skill map draws.
///
/// The default skin is tosk's storybook look ([ToskSkin]); black & white for
/// e-ink is `BwSkin`. Another skin implements this class and overrides
/// `skinProvider`.
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

/// The colours the map's ink painters (branches, nodes, leaves, the marker)
/// use. Black & white sets every one to black, white or the gray.
@immutable
class MapInk {
  const MapInk({
    required this.ink,
    required this.paper,
    required this.cream,
    required this.bark,
    required this.barkDark,
    required this.leaf,
    required this.leafDark,
    required this.gold,
    required this.silver,
    required this.bronze,
    this.hatchOpacity = 0.62,
  });

  final Color ink;
  final Color paper;
  final Color cream;
  final Color bark;
  final Color barkDark;
  final Color leaf;
  final Color leafDark;
  final Color gold;
  final Color silver;
  final Color bronze;

  /// Opacity of hatching strokes (1 in black & white).
  final double hatchOpacity;

  MapInk copyWith({Color? ink, Color? bark, Color? barkDark, Color? leaf}) => MapInk(
    ink: ink ?? this.ink,
    paper: paper,
    cream: cream,
    bark: bark ?? this.bark,
    barkDark: barkDark ?? this.barkDark,
    leaf: leaf ?? this.leaf,
    leafDark: leafDark,
    gold: gold,
    silver: silver,
    bronze: bronze,
    hatchOpacity: hatchOpacity,
  );

  @override
  bool operator ==(Object other) =>
      other is MapInk &&
      other.ink == ink &&
      other.paper == paper &&
      other.cream == cream &&
      other.bark == bark &&
      other.barkDark == barkDark &&
      other.leaf == leaf &&
      other.leafDark == leafDark &&
      other.gold == gold &&
      other.silver == silver &&
      other.bronze == bronze &&
      other.hatchOpacity == hatchOpacity;

  @override
  int get hashCode => Object.hash(ink, paper, cream, bark, barkDark, leaf, leafDark, gold, silver, bronze, hatchOpacity);

  static const storybook = MapInk(
    ink: Tosk.ink,
    paper: Tosk.paper,
    cream: Tosk.cream,
    bark: Tosk.bark,
    barkDark: Tosk.barkDark,
    leaf: Tosk.leaf,
    leafDark: Tosk.leafDark,
    gold: Tosk.gold,
    silver: Tosk.silver,
    bronze: Tosk.bronze,
  );

  /// The dark theme: the same accents, bark and cream a little lighter so the
  /// branches read on deep bark, ink stays dark so the pen lines stay pen lines.
  static const night = MapInk(
    ink: Color(0xFF1A110B),
    paper: Color(0xFF6A5747),
    cream: Color(0xFFE9D8B4),
    bark: Color(0xFFA07F5F),
    barkDark: Color(0xFF6A5040),
    leaf: Color(0xFF8CAB6B),
    leafDark: Tosk.leafDark,
    gold: Tosk.gold,
    silver: Tosk.silver,
    bronze: Tosk.bronze,
  );
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
    this.ink = MapInk.storybook,
    this.nodeShape = const CircleBorder(),
    this.edgePainter = const CurvedEdgePainter(),
    this.monochrome = false,
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

  /// The ink painters' colours (branches, nodes, leaves).
  final MapInk ink;

  /// Black & white (e-ink): nodes are outlined, the strength ring has a
  /// dotted track, fading shows as a dashed border and tiers keep their
  /// hierarchy through ring count, rays and twinkles only.
  final bool monochrome;

  Color nodeColor(SkillKind kind) => kind == SkillKind.vocab ? vocabColor : grammarColor;

  Color bandColor(int index) => bandColors[index % bandColors.length];

  Color tierColor(MapTier tier) => monochrome
      ? ringColor
      : switch (tier) {
          MapTier.gold => ink.gold,
          MapTier.silver => ink.silver,
          MapTier.bronze => ink.bronze,
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

  /// The S-curve as a path (the branch painter draws its bough along it).
  Path path(Offset from, Offset to) {
    final dy = (to.dy - from.dy).abs();
    final bend = math.max(24.0, dy * 0.5);
    final dir = to.dy >= from.dy ? 1.0 : -1.0;
    return Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(from.dx, from.dy + bend * dir, to.dx, to.dy - bend * dir, to.dx, to.dy);
  }

  @override
  void paint(Canvas canvas, Offset from, Offset to, Paint paint) => canvas.drawPath(path(from, to), paint);
}

/// The tosk skin: the storybook palette (docs/brand-overhaul.md), Gelasio
/// for headings, parchment surfaces (light) or deep bark (dark).
class ToskSkin extends Skin {
  const ToskSkin();

  @override
  String get id => 'tosk';
  @override
  String get name => 'tosk';
  @override
  Color get seedColor => Tosk.fur;

  @override
  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = dark ? toskDarkScheme() : toskLightScheme();
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
    return base.copyWith(
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        // Screen titles in the brand serif (ThemeData's text theme has no
        // sizes yet: take titleLarge's geometry from the typography).
        titleTextStyle: toskSerif(
          Typography.material2021(platform: base.platform).englishLike.titleLarge!.merge(base.textTheme.titleLarge),
        )?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: scheme.surfaceContainerLow, surfaceTintColor: Colors.transparent),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        modalBackgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    );
  }

  @override
  MapStyle mapStyle(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final ink = dark ? MapInk.night : MapInk.storybook;
    return MapStyle(
      vocabColor: ink.cream,
      grammarColor: ink.cream,
      lockedColor: ink.paper,
      ringTrack: scheme.outlineVariant,
      ringColor: ink.leafDark,
      edgeColor: ink.bark,
      bandColors: dark
          ? [scheme.surfaceContainerLow, scheme.surfaceContainer]
          : [scheme.surfaceContainerLow, scheme.surfaceContainer],
      bandTitleColor: scheme.onSurfaceVariant,
      onNode: ink.barkDark,
      ink: ink,
    );
  }
}
