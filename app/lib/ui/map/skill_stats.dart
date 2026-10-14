import 'package:flutter/foundation.dart';

/// Display tier of a skill on the map. Mirrors progression's `SkillTier`
/// (same names and order; see `skillStatsProvider`).
enum MapTier { locked, available, started, bronze, silver, gold }

/// What the map needs to draw one skill node.
@immutable
class SkillStats {
  const SkillStats({
    this.strength = 0,
    this.lastPracticed,
    this.tier = MapTier.available,
    this.practicedFacets = 0,
    this.totalFacets = 0,
    this.fading,
  });

  /// Mean predicted recall across the skill's facets (0..1).
  final double strength;
  final DateTime? lastPracticed;
  final MapTier tier;
  final int practicedFacets;
  final int totalFacets;

  /// Progression's fading signal (0 = fresh … 1 = badly faded, over reviewed
  /// facets). Null falls back to `1 - strength`.
  final double? fading;

  bool get practiced => lastPracticed != null;

  /// How much the skill has faded (0 = fresh, 1 = forgotten). Never-practiced skills don't fade.
  double get decay => practiced ? (fading ?? 1 - strength).clamp(0.0, 1.0) : 0;

  /// Whole days since [lastPracticed] (null when never practiced).
  int? daysSince(DateTime now) {
    final last = lastPracticed;
    if (last == null) return null;
    final d = now.difference(last).inHours ~/ 24;
    return d < 0 ? 0 : d;
  }

  static const empty = SkillStats();
}

/// "today", "1 day ago", "12 days ago".
String daysAgoLabel(int days) => switch (days) {
  0 => 'today',
  1 => '1 day ago',
  _ => '$days days ago',
};

/// Compact form for map nodes: "today", "1d", "12d".
String daysAgoShort(int days) => days == 0 ? 'today' : '${days}d';

/// The unit to jump to on a long map: the first unit (in course order) with
/// a skill that is unlocked but not finished yet (available or started,
/// below bronze). Null when every skill is finished or locked.
String? currentUnitId(List<({String unitId, String skillId})> skills, Map<String, SkillStats> stats) {
  for (final s in skills) {
    final tier = stats[s.skillId]?.tier ?? MapTier.available;
    if (tier == MapTier.available || tier == MapTier.started) return s.unitId;
  }
  return null;
}
