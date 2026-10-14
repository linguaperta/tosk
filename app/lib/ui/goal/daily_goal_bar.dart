import 'package:flutter/material.dart';

import '../../progression/daily_goal.dart';
import '../theme/bw_skin.dart';

/// Today's progress toward the daily XP goal: a flag (a check once met), a
/// bar and "30 / 50 XP" (or "Goal met"). Fits at 320 px; black & white: a
/// black bar on the gray track, and the icon and words say whether it's met.
class DailyGoalBar extends StatelessWidget {
  const DailyGoalBar({super.key, required this.status});

  final DailyGoalStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = isMonochrome(scheme);
    final met = status.met;
    final label = met ? 'Goal met' : '${status.todayXp} / ${status.goalXp} XP';
    return Semantics(
      label: met
          ? 'Daily goal met: ${status.todayXp} XP today'
          : 'Daily goal: ${status.todayXp} of ${status.goalXp} XP today',
      excludeSemantics: true,
      child: Row(
        key: const ValueKey('daily-goal'),
        children: [
          Icon(
            met ? Icons.check_circle : Icons.flag_outlined,
            key: ValueKey(met ? 'daily-goal-met' : 'daily-goal-open'),
            size: 18,
            color: mono ? kBwBlack : (met ? scheme.primary : scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: status.progress,
                minHeight: 8,
                backgroundColor: mono ? kBwGray : scheme.surfaceContainerHighest,
                color: mono ? kBwBlack : scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            key: const ValueKey('daily-goal-label'),
            style: theme.textTheme.labelMedium?.copyWith(fontWeight: met ? FontWeight.w700 : null),
          ),
        ],
      ),
    );
  }
}
