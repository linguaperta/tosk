/// Where progression's widgets (`lib/ui/progression/`) plug into the screens.
///
/// The hosting screens only know these slots; each slot reads its data from the
/// progression providers in `providers.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../progression/progression.dart';
import '../../providers.dart';
import '../map/skill_sheet.dart' show itemLabel;
import '../progression/progression_widgets.dart';
import '../goal/daily_goal_bar.dart';
import '../goal/daily_goal_providers.dart';
import '../routes.dart';

/// Top of the skill map: level ring, today's XP and the streak. Tapping it
/// opens the progress page.
class MapHeaderSlot extends ConsumerWidget {
  const MapHeaderSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(progressProfileProvider).value;
    if (profile == null) return const SizedBox.shrink();
    final reduce = ref.watch(reduceMotionProvider);
    final theme = Theme.of(context);
    final level = profile.level;
    final goal = ref.watch(dailyGoalStatusProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              key: const ValueKey('map-header'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.go(Routes.progress),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                  children: [
                    LevelBadge(level: level, size: 44, showXp: false, reduceMotion: reduce),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Level ${level.level}',
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${level.xpIntoLevel} / ${level.xpForNext} XP · +${profile.todayXp} today',
                            key: const ValueKey('map-header-xp'),
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StreakCounter(streak: profile.streak, reduceMotion: reduce),
                  ],
                ),
                    // Today's progress toward the daily goal (none when the goal is off).
                    if (goal != null && goal.enabled) ...[
                      const SizedBox(height: 6),
                      DailyGoalBar(status: goal),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// On the session summary: XP earned, level-up, words that improved, tier changes.
class SummaryProgressSlot extends ConsumerWidget {
  const SummaryProgressSlot({super.key, required this.summary});
  final SessionSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(sessionProgressSummaryProvider(summary.sessionId)).value;
    if (progress == null) return const SizedBox.shrink();
    final course = ref.watch(courseDataProvider).value;
    final lang = ref.watch(sourceLangProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SessionSummaryCard(
        key: const ValueKey('session-progress-card'),
        summary: progress,
        reduceMotion: ref.watch(reduceMotionProvider),
        itemLabel: (id) {
          final item = course?.item(id);
          return item == null ? null : itemLabel(item);
        },
        skillLabel: (id) {
          final skill = course?.skill(id);
          return skill == null ? id : pickLang(skill.title, lang);
        },
      ),
    );
  }
}

/// Above the non-stop player: score, combo multiplier and the bonus-round HUD.
class NonStopHudSlot extends ConsumerWidget {
  const NonStopHudSlot({super.key, required this.run});
  final NonStopRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: NonStopHud(
            key: const ValueKey('nonstop-hud'),
            run: run,
            best: ref.watch(bestNonStopRunProvider).value,
            clock: ref.watch(clockProvider),
            reduceMotion: ref.watch(reduceMotionProvider),
          ),
        ),
      ),
    );
  }
}

/// On the non-stop start screen: the best run so far.
class NonStopRecordSlot extends ConsumerWidget {
  const NonStopRecordSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final best = ref.watch(bestNonStopRunProvider).value;
    final theme = Theme.of(context);
    if (best == null) {
      return Text(
        'No runs yet. Your best score will show here.',
        key: const ValueKey('nonstop-record-empty'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    final date = best.startedAt.toLocal();
    return Card(
      key: const ValueKey('nonstop-record'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Best run', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${best.score}', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Best combo ${best.bestCombo} · ${best.correct}/${best.answered} correct'
              '${best.bonusRoundsCompleted > 0 ? ' · ${best.bonusRoundsCompleted} bonus' : ''}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            Text(
              '${date.year}-${_two(date.month)}-${_two(date.day)}',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
