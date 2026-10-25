import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../reminders/reminder_backend.dart';
import '../goal/daily_goal_providers.dart';
import '../theme/bw_skin.dart';
import 'learner_settings.dart';
import 'settings_parts.dart';

/// Settings → Daily goal: the XP goal and, where the platform has local
/// notifications (Android, iOS, macOS), a reminder at a chosen time on days
/// the goal isn't met yet.
///
/// The notification permission is asked for when it is needed: switching the
/// reminder on, or setting its time while notifications are off. A one-line
/// explanation comes first. Refused: the reminder stays on, and the switch
/// says "Notifications are off for tosk" with "Open settings"; the app checks
/// again whenever it comes back to the foreground. On the web the reminder
/// isn't offered (a short note says why).
class DailyGoalSection extends ConsumerWidget {
  const DailyGoalSection({super.key});

  /// The explanation before the system's question; true to go on.
  static Future<bool> _explain(BuildContext context, TimeOfDay time) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('reminder-explain'),
          icon: const Icon(Icons.notifications_active_outlined),
          title: const Text('Allow notifications?'),
          content: Text(
            'tosk sends one notification at ${time.format(context)} on days your goal isn\'t met yet. Nothing else.',
          ),
          actions: [
            TextButton(
              key: const ValueKey('reminder-explain-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              key: const ValueKey('reminder-explain-continue'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;

  /// Asks when needed; refreshes what Settings shows. Null when not mounted.
  static Future<ReminderPermissionOutcome?> _ask(BuildContext context, WidgetRef ref, TimeOfDay time) async {
    final outcome = await ensureReminderPermission(
      ref.read(reminderBackendProvider),
      explain: () => context.mounted ? _explain(context, time) : Future.value(false),
    );
    ref.invalidate(notificationAccessProvider);
    return context.mounted ? outcome : null;
  }

  Future<void> _setReminder(BuildContext context, WidgetRef ref, bool on, TimeOfDay time) async {
    final ctl = ref.read(learnerSettingsProvider.notifier);
    if (!on) {
      await ctl.change((s) => s.copyWith(reminderEnabled: false));
      return;
    }
    final outcome = await _ask(context, ref, time);
    // "Not now": the switch stays off. Refused: on, with the warning below,
    // so it starts working as soon as notifications are allowed.
    if (outcome == null || outcome == ReminderPermissionOutcome.cancelled) return;
    await ctl.change((s) => s.copyWith(reminderEnabled: true));
  }

  Future<void> _pickTime(BuildContext context, WidgetRef ref, TimeOfDay current) async {
    final t = await showTimePicker(context: context, initialTime: current, helpText: 'Reminder time');
    if (t == null) return;
    await ref.read(learnerSettingsProvider.notifier).change((s) => s.copyWith(reminderTime: t));
    if (!context.mounted) return;
    if (ref.read(notificationAccessProvider).value != NotificationAccess.granted) await _ask(context, ref, t);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(learnerSettingsProvider).value;
    if (s == null) return const SizedBox.shrink();
    final supported = ref.watch(remindersSupportedProvider);
    final note = ref.watch(remindersUnavailableNoteProvider);
    final time = s.reminderTime.format(context);
    final blocked =
        supported && s.reminderEnabled && ref.watch(notificationAccessProvider).value == NotificationAccess.denied;
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
            subtitle: Text(
              blocked ? 'Notifications are off for tosk' : 'A notification at $time on days your goal isn\'t met yet',
              key: const ValueKey('reminder-subtitle'),
            ),
            value: s.reminderEnabled,
            onChanged: (v) => _setReminder(context, ref, v, s.reminderTime),
          ),
          if (blocked) const _NotificationsOff(),
          if (s.reminderEnabled)
            ListTile(
              key: const ValueKey('reminder-time'),
              leading: const Icon(Icons.schedule),
              title: const Text('Reminder time'),
              trailing: Text(time, style: Theme.of(context).textTheme.titleMedium),
              onTap: () => _pickTime(context, ref, s.reminderTime),
            ),
        ] else if (!supported && s.hasGoal && note != null)
          ListTile(
            key: const ValueKey('reminder-unavailable'),
            leading: const Icon(Icons.notifications_off_outlined),
            title: const Text('Daily reminder'),
            subtitle: Text(note),
          ),
      ],
    );
  }
}

/// "Notifications are off for tosk — Open settings", under the switch.
class _NotificationsOff extends ConsumerWidget {
  const _NotificationsOff();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bw = isBw(context);
    return Padding(
      key: const ValueKey('reminder-denied'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bw ? kBwWhite : scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
          border: bw ? Border.all(color: kBwBlack, width: kBwBorder) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.notifications_off_outlined, color: bw ? kBwBlack : scheme.onTertiaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'The reminder can\'t appear until notifications for tosk are allowed in the system '
                        'settings.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: bw ? kBwBlack : scheme.onTertiaryContainer),
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        key: const ValueKey('reminder-open-settings'),
                        style: TextButton.styleFrom(
                          foregroundColor: bw ? kBwBlack : scheme.onTertiaryContainer,
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => unawaited(ref.read(reminderBackendProvider).openSettings()),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open settings'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
