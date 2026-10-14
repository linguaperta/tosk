/// Daily goal and reminder wiring: today's progress, the days the goal was
/// met (heatmap) and the reminder plan, plus the notification backend.
library;

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../progression/progression.dart';
import '../../providers.dart';
import '../../reminders/reminder_backend.dart';
import '../settings/learner_settings.dart';

/// Local notifications (a [NullReminderBackend] under `flutter test` and on
/// platforms without reminders; tests override it with a fake).
final reminderBackendProvider = Provider<ReminderBackend>((ref) => defaultReminderBackend());

/// Whether Settings offers the reminder on this device.
final remindersSupportedProvider = Provider<bool>((ref) => ref.watch(reminderBackendProvider).supported);

/// Today's progress toward the daily goal (null while loading).
final dailyGoalStatusProvider = Provider<DailyGoalStatus?>((ref) {
  final profile = ref.watch(progressProfileProvider).value;
  final settings = ref.watch(learnerSettingsProvider).value;
  if (profile == null || settings == null) return null;
  // The goal is account-wide: today's XP over every course.
  return DailyGoalStatus(goalXp: settings.dailyGoalXp, todayXp: profile.accountTodayXp);
});

/// XP per local date (whole log, every course).
final dailyXpProvider = FutureProvider<Map<LocalDate, int>>((ref) async {
  ref.watch(progressRevisionProvider);
  final svc = await ref.watch(progressionServiceProvider.future);
  return svc.xpByDay();
});

/// Local dates on which the current goal was reached (heatmap markers).
final goalMetDaysProvider = Provider<Set<LocalDate>>((ref) {
  final goal = ref.watch(dailyGoalXpProvider);
  final xp = ref.watch(dailyXpProvider).value;
  return xp == null ? const {} : goalMetDays(xp, goal);
});

/// The reminders that should be scheduled now (null until settings and
/// progress are loaded). See [planReminders].
final reminderPlanProvider = Provider<List<ReminderSlot>?>((ref) {
  final settings = ref.watch(learnerSettingsProvider).value;
  if (settings == null) return null;
  if (!settings.reminderEnabled || !settings.hasGoal) return const [];
  final profile = ref.watch(progressProfileProvider).value;
  if (profile == null) return null;
  final now = ref.watch(clockProvider)();
  return planReminders(
    enabled: true,
    goalXp: settings.dailyGoalXp,
    todayXp: profile.accountTodayXp,
    today: profile.today,
    now: now,
    hour: settings.reminderTime.hour,
    minute: settings.reminderTime.minute,
  );
});

/// Text of the reminder notification.
({String title, String body}) reminderText(int goalXp) => (
  title: 'Time for a little practice',
  body: 'Your daily goal is $goalXp XP. A short lesson keeps your streak going.',
);

/// Keeps the scheduled notifications in line with [reminderPlanProvider]:
/// call once from the app shell. Re-schedules when the plan changes (app
/// start, settings, every session through the progress revision).
void syncReminders(WidgetRef ref) {
  List<ReminderSlot>? applied;
  ref.listenManual<List<ReminderSlot>?>(reminderPlanProvider, (_, plan) {
    if (plan == null) return;
    // Nothing scheduled and nothing to schedule: no plugin calls at start.
    if (applied == null && plan.isEmpty) {
      applied = plan;
      return;
    }
    if (applied != null && const ListEquality<ReminderSlot>().equals(applied, plan)) return;
    applied = plan;
    final backend = ref.read(reminderBackendProvider);
    if (!backend.supported) return;
    final text = reminderText(ref.read(dailyGoalXpProvider));
    backend.replaceAll(plan, title: text.title, body: text.body);
  }, fireImmediately: true);
}
