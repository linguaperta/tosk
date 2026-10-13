import 'package:flutter/material.dart';

import '../../progression/progression.dart';

/// Colors shared by the progression widgets, tuned for light and dark themes.
abstract final class ProgressionColors {
  static const _bronzeLight = Color(0xFFB0703A);
  static const _bronzeDark = Color(0xFFD9955A);
  static const _silverLight = Color(0xFF7D838C);
  static const _silverDark = Color(0xFFC3C8CF);
  static const _goldLight = Color(0xFFC79A00);
  static const _goldDark = Color(0xFFFFCF40);
  static const _freezeLight = Color(0xFF4FA3D9);
  static const _freezeDark = Color(0xFF7CC4F0);
  static const _flame = Color(0xFFFF7A1A);

  static bool _dark(ColorScheme cs) => cs.brightness == Brightness.dark;

  static Color bronze(ColorScheme cs) => _dark(cs) ? _bronzeDark : _bronzeLight;
  static Color silver(ColorScheme cs) => _dark(cs) ? _silverDark : _silverLight;
  static Color gold(ColorScheme cs) => _dark(cs) ? _goldDark : _goldLight;
  static Color freeze(ColorScheme cs) => _dark(cs) ? _freezeDark : _freezeLight;
  static Color flame(ColorScheme cs) => _flame;

  static Color tier(SkillTier tier, ColorScheme cs) => switch (tier) {
        SkillTier.locked => cs.outline,
        SkillTier.available => cs.primary,
        SkillTier.started => cs.primary,
        SkillTier.bronze => bronze(cs),
        SkillTier.silver => silver(cs),
        SkillTier.gold => gold(cs),
      };

  /// Background of a verb-table chip ("lights up" with mastery).
  static Color masteryFill(VerbMastery m, ColorScheme cs) => switch (m) {
        VerbMastery.unseen => cs.surfaceContainerHighest,
        VerbMastery.learning => cs.primaryContainer.withValues(alpha: 0.45),
        VerbMastery.known => cs.primaryContainer,
        VerbMastery.mastered => gold(cs),
      };

  static Color masteryText(VerbMastery m, ColorScheme cs) => switch (m) {
        VerbMastery.unseen => cs.onSurfaceVariant.withValues(alpha: 0.7),
        VerbMastery.learning => cs.onSurface,
        VerbMastery.known => cs.onPrimaryContainer,
        VerbMastery.mastered => _dark(cs) ? Colors.black : Colors.white,
      };

  /// Heatmap cell color for [bucket] in 0..[maxBucket].
  static Color heat(int bucket, int maxBucket, ColorScheme cs) {
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
