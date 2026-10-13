import 'package:flutter/material.dart';

import '../../progression/progression.dart';
import 'level_badge.dart';
import 'progression_colors.dart';
import 'tier_badge.dart';

/// End-of-session card: XP earned, accuracy, level-up, improved words, tier changes.
class SessionSummaryCard extends StatelessWidget {
  const SessionSummaryCard({
    super.key,
    required this.summary,
    this.itemLabel,
    this.skillLabel,
    this.reduceMotion = false,
    this.onContinue,
    this.maxWords = 12,
  });

  final SessionProgressSummary summary;

  /// Display text for an item id (e.g. its lemma); null (or no function) falls back to
  /// the id without the course prefix.
  final String? Function(String itemId)? itemLabel;

  /// Display name of a skill id; defaults to the id.
  final String Function(String skillId)? skillLabel;
  final bool reduceMotion;
  final VoidCallback? onContinue;
  final int maxWords;

  String _item(String id) {
    final custom = itemLabel?.call(id);
    if (custom != null) return custom;
    final i = id.indexOf(':');
    return i < 0 ? id : id.substring(i + 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = summary;
    final words = s.improvedItemIds;
    final xpStyle = theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: cs.primary);
    final xp = reduceMotion
        ? Text('+${s.xpEarned} XP', style: xpStyle)
        : TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: s.xpEarned.toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text('+${v.round()} XP', style: xpStyle),
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(label: '${s.xpEarned} XP earned', excludeSemantics: true, child: xp),
                      const SizedBox(height: 4),
                      Text(
                        '${(s.accuracy * 100).round()}% correct · ${s.correct}/${s.reviews} answers',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                LevelBadge(level: s.levelAfter, size: 56, reduceMotion: reduceMotion, showXp: false),
              ],
            ),
            if (s.leveledUp) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: ProgressionColors.gold(cs).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.trending_up, color: ProgressionColors.gold(cs)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('Level up! ${s.levelBefore.level} → ${s.levelAfter.level}',
                        style: theme.textTheme.titleSmall),
                  ),
                ]),
              ),
            ],
            if (s.tierChanges.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Skills', style: theme.textTheme.titleSmall),
              for (final c in s.tierChanges)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text(skillLabel?.call(c.skillId) ?? c.skillId)),
                    TierBadge(tier: c.from, size: 24, reduceMotion: true),
                    Icon(Icons.arrow_forward, size: 16, color: c.isUp ? cs.primary : cs.error),
                    TierBadge(tier: c.to, size: 24, reduceMotion: reduceMotion),
                    const SizedBox(width: 6),
                    SizedBox(width: 72, child: Text(tierLabel(c.to), style: theme.textTheme.labelMedium)),
                  ]),
                ),
            ],
            if (words.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Stronger now (${words.length})', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in words.take(maxWords))
                    Chip(label: Text(_item(id)), visualDensity: VisualDensity.compact),
                  if (words.length > maxWords)
                    Chip(label: Text('+${words.length - maxWords}'), visualDensity: VisualDensity.compact),
                ],
              ),
            ],
            if (onContinue != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onContinue, child: const Text('Continue')),
            ],
          ],
        ),
      ),
    );
  }
}
