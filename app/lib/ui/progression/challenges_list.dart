import 'package:flutter/material.dart';

import '../../progression/progression.dart';
import '../theme/bw_skin.dart';
import 'progression_colors.dart';

IconData challengeIcon(ChallengeMetric m) => switch (m) {
      ChallengeMetric.reviews => Icons.repeat,
      ChallengeMetric.correctAnswers => Icons.check_circle_outline,
      ChallengeMetric.conjugations => Icons.table_chart_outlined,
      ChallengeMetric.practiceDays => Icons.calendar_month,
      ChallengeMetric.perfectLessons => Icons.verified_outlined,
      ChallengeMetric.newWords => Icons.auto_stories_outlined,
      ChallengeMetric.xp => Icons.bolt,
      ChallengeMetric.strongVerbTables => Icons.fitness_center,
      ChallengeMetric.masteredVerbTables => Icons.workspace_premium_outlined,
      ChallengeMetric.nonStopCombo => Icons.whatshot,
    };

IconData badgeIcon(EarnedBadge b) => switch (b.kind) {
      BadgeKind.streak => Icons.local_fire_department,
      BadgeKind.level => Icons.trending_up,
      BadgeKind.challenge => b.metric == null ? Icons.emoji_events : challengeIcon(b.metric!),
    };

/// This week's and month's challenges with progress bars, then the badge shelf.
/// Not scrollable itself; put it in a scroll view.
class ChallengesList extends StatelessWidget {
  const ChallengesList({
    super.key,
    required this.board,
    this.today,
    this.reduceMotion = false,
    this.showBadges = true,
    this.maxBadges = 24,
  });

  final ChallengeBoard board;

  /// Used for "N days left"; omitted when null.
  final LocalDate? today;
  final bool reduceMotion;
  final bool showBadges;

  /// Most recent badges shown.
  final int maxBadges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String? left(int days) => today == null ? null : '$days day${days == 1 ? '' : 's'} left';
    final recent = board.badges.reversed.take(maxBadges).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header('This week', today == null ? null : left(board.daysLeftInWeek(today!))),
        for (final c in board.weekly) ChallengeTile(challenge: c, reduceMotion: reduceMotion),
        const SizedBox(height: 12),
        _Header('This month', today == null ? null : left(board.daysLeftInMonth(today!))),
        for (final c in board.monthly) ChallengeTile(challenge: c, reduceMotion: reduceMotion),
        if (showBadges) ...[
          const SizedBox(height: 12),
          _Header('Badges', '${board.badges.length}'),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Complete a challenge to earn your first badge.', style: theme.textTheme.bodySmall),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final b in recent) BadgeChip(badge: b)],
              ),
            ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, this.trailing);
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          if (trailing != null) Text(trailing!, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

/// One challenge with an icon, description and progress bar.
class ChallengeTile extends StatelessWidget {
  const ChallengeTile({super.key, required this.challenge, this.reduceMotion = false});

  final Challenge challenge;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final done = challenge.completed;
    final accent = done ? ProgressionColors.gold(cs) : cs.primary;
    Widget bar(double v) => LinearProgressIndicator(
          value: v,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
          color: accent,
          backgroundColor: isMonochrome(cs) ? kBwGray : cs.surfaceContainerHighest,
        );
    final shown = challenge.progress > challenge.target ? challenge.target : challenge.progress;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: ProgressionColors.tint(accent, 0.15, cs),
              foregroundColor: accent,
              child: Icon(done ? Icons.emoji_events : challengeIcon(challenge.template.metric)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(challenge.template.title, style: theme.textTheme.titleSmall),
                  Text(challenge.template.description, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Semantics(
                    label: '${challenge.template.title}: $shown of ${challenge.target}',
                    excludeSemantics: true,
                    child: reduceMotion
                        ? bar(challenge.fraction)
                        : TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: challenge.fraction),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => bar(v),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 64),
              child: Align(
                alignment: Alignment.centerRight,
                widthFactor: 1,
                child: done
                    ? Icon(Icons.check_circle, color: accent, semanticLabel: 'Completed')
                    : Text('$shown/${challenge.target}', style: theme.textTheme.labelMedium),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small earned-badge chip.
class BadgeChip extends StatelessWidget {
  const BadgeChip({super.key, required this.badge});
  final EarnedBadge badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = ProgressionColors.gold(cs);
    return Tooltip(
      message: '${badge.description} · ${badge.earnedOn}',
      child: Chip(
        avatar: Icon(badgeIcon(badge), size: 18, color: gold),
        label: Text(badge.title),
        side: BorderSide(color: ProgressionColors.soft(gold, 0.6, cs), width: isMonochrome(cs) ? kBwBorder : 1),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
