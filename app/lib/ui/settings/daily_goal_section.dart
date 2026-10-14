import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../goal/daily_goal_providers.dart';
import 'learner_settings.dart';
import 'settings_parts.dart';

/// Settings → Daily goal: the XP goal and, where the platform has local
/// notifications (Android, iOS, macOS), a reminder at a chosen time on days
/// the goal isn't met yet. Switching the reminder on asks for permission
/// (Android 13+, iOS, macOS); without it the switch stays off.
class DailyGoalSection extends ConsumerWidget {
  const DailyGoalSection({super.key});

  Future<void> _setReminder(BuildContext context, WidgetRef ref, bool on) async {
    final ctl = ref.read(learnerSettingsProvider.notifier);
    if (!on) {
      await ctl.change((s) => s.copyWith(reminderEnabled: false));
      return;
    }
    final granted = await ref.read(reminderBackendProvider).requestPermission();
    if (!context.mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: ValueKey('reminder-denied'),
          content: Text('Notifications are off for tosk. Allow them in the system settings to get reminders.'),
        ),
      );
      return;
    }
    await ctl.change((s) => s.copyWith(reminderEnabled: true));
  }

  Future<void> _pickTime(BuildContext context, WidgetRef ref, TimeOfDay current) async {
    final t = await showTimePicker(context: context, initialTime: current, helpText: 'Reminder time');
    if (t == null) return;
    await ref.read(learnerSettingsProvider.notifier).change((s) => s.copyWith(reminderTime: t));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(learnerSettingsProvider).value;
    if (s == null) return const SizedBox.shrink();
    final supported = ref.watch(remindersSupportedProvider);
    final time = s.reminderTime.format(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeader('Daily goal'),
        SettingsChoice<int>(
          keyName: 'daily-goal',
          title: 'Daily goal (XP a day)',
          subtitle: s.hasGoal
              ? 'XP to earn each day, shown on the map and the activity calendar. A lesson earns about 50'
              : 'No daily goal',
          values: kDailyGoalChoices,
          selected: s.dailyGoalXp,
          label: (v) => v == 0 ? 'Off' : '$v',
          onChanged: (v) => ref.read(learnerSettingsProvider.notifier).change((s) => s.copyWith(dailyGoalXp: v)),
        ),
        if (supported && s.hasGoal) ...[
          SwitchListTile(
            key: const ValueKey('reminder-switch'),
            title: const Text('Daily reminder'),
            subtitle: Text('A notification at $time on days your goal isn\'t met yet'),
            value: s.reminderEnabled,
            onChanged: (v) => _setReminder(context, ref, v),
          ),
          if (s.reminderEnabled)
            ListTile(
              key: const ValueKey('reminder-time'),
              leading: const Icon(Icons.schedule),
              title: const Text('Reminder time'),
              trailing: Text(time, style: Theme.of(context).textTheme.titleMedium),
              onTap: () => _pickTime(context, ref, s.reminderTime),
            ),
        ],
      ],
    );
  }
}
