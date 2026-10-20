import 'package:flutter/material.dart';

import '../../progression/progression.dart';
import '../theme/bw_skin.dart';

/// Colors shared by the progression widgets, tuned for light and dark themes.
/// In black & white every accent is black; the widgets carry the meaning with
/// icons, letters, patterns and labels instead (see `isMonochrome`).
abstract final class ProgressionColors {
  static const _bronzeLight = Color(0xFF9C5A30);
  static const _bronzeDark = Color(0xFFCC8A58);
  static const _silverLight = Color(0xFF6D7C8C);
  static const _silverDark = Color(0xFFBCC8D4);
  static const _goldLight = Color(0xFFC79A00);
  static const _goldDark = Color(0xFFFFCF40);
  static const _freezeLight = Color(0xFF4FA3D9);
  static const _freezeDark = Color(0xFF7CC4F0);
  static const _flame = Color(0xFFFF7A1A);

  static bool _dark(ColorScheme cs) => cs.brightness == Brightness.dark;

  /// A light tint of [c] for backgrounds; plain white in black & white (no
  /// translucent fills there; the widget draws a border instead).
  static Color tint(Color c, double alpha, ColorScheme cs) => isMonochrome(cs) ? kBwWhite : c.withValues(alpha: alpha);

  /// A soft border color; solid black in black & white.
  static Color soft(Color c, double alpha, ColorScheme cs) => isMonochrome(cs) ? kBwBlack : c.withValues(alpha: alpha);

  static Color bronze(ColorScheme cs) => isMonochrome(cs) ? kBwBlack : (_dark(cs) ? _bronzeDark : _bronzeLight);
  static Color silver(ColorScheme cs) => isMonochrome(cs) ? kBwBlack : (_dark(cs) ? _silverDark : _silverLight);
  static Color gold(ColorScheme cs) => isMonochrome(cs) ? kBwBlack : (_dark(cs) ? _goldDark : _goldLight);
  static Color freeze(ColorScheme cs) => isMonochrome(cs) ? kBwBlack : (_dark(cs) ? _freezeDark : _freezeLight);
  static Color flame(ColorScheme cs) => isMonochrome(cs) ? kBwBlack : _flame;

  static Color tier(SkillTier tier, ColorScheme cs) => switch (tier) {
    SkillTier.locked => isMonochrome(cs) ? kBwGray : cs.outline,
    SkillTier.available => cs.primary,
    SkillTier.started => cs.primary,
    SkillTier.bronze => bronze(cs),
    SkillTier.silver => silver(cs),
    SkillTier.gold => gold(cs),
  };

  /// Background of a verb-table chip ("lights up" with mastery).
  static Color masteryFill(VerbMastery m, ColorScheme cs) => isMonochrome(cs)
      ? (m == VerbMastery.mastered ? kBwBlack : kBwWhite)
      : switch (m) {
          VerbMastery.unseen => cs.surfaceContainerHighest,
          VerbMastery.learning => cs.primaryContainer.withValues(alpha: 0.45),
          VerbMastery.known => cs.primaryContainer,
          VerbMastery.mastered => gold(cs),
        };

  static Color masteryText(VerbMastery m, ColorScheme cs) => isMonochrome(cs)
      ? switch (m) {
          VerbMastery.unseen => kBwGray,
          VerbMastery.mastered => kBwWhite,
          _ => kBwBlack,
        }
      : switch (m) {
          VerbMastery.unseen => cs.onSurfaceVariant.withValues(alpha: 0.7),
          VerbMastery.learning => cs.onSurface,
          VerbMastery.known => cs.onPrimaryContainer,
          VerbMastery.mastered => _dark(cs) ? Colors.black : Colors.white,
        };

  /// Heatmap cell color for [bucket] in 0..[maxBucket].
  static Color heat(int bucket, int maxBucket, ColorScheme cs) {
    if (isMonochrome(cs)) return kBwWhite; // the heatmap draws dots instead
    if (bucket <= 0 || maxBucket <= 0) return cs.surfaceContainerHighest;
    final t = bucket / maxBucket;
    return cs.primary.withValues(alpha: 0.25 + 0.75 * t);
  }
}

/// Human-readable tier name.
String tierLabel(SkillTier tier) => switch (tier) {
  SkillTier.locked => 'Locked',
  SkillTier.available => 'Not started',
  SkillTier.started => 'Started',
  SkillTier.bronze => 'Bronze',
  SkillTier.silver => 'Silver',
  SkillTier.gold => 'Gold',
};

String masteryLabel(VerbMastery m) => switch (m) {
  VerbMastery.unseen => 'Unseen',
  VerbMastery.learning => 'Learning',
  VerbMastery.known => 'Known',
  VerbMastery.mastered => 'Mastered',
};

const List<String> kMonthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];
