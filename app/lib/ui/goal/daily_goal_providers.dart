/// Daily goal and reminder wiring: today's progress, the days the goal was
/// met (heatmap) and the reminder plan, plus the notification backend.
library;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

/// Why the reminder isn't offered here, for Settings (the web: browsers
/// can't reliably wake an app at a set time); null shows nothing.
final remindersUnavailableNoteProvider = Provider<String?>(
  (ref) => kIsWeb
      ? "Daily reminders need the Android app: a browser can't reliably send a notification at a set time."
      : null,
);

/// Bumped when the app comes back to the foreground: the permission is
/// checked again and the reminders re-planned (a new day, another time zone).
final reminderResumeProvider = NotifierProvider<ProgressRevision, int>(ProgressRevision.new);

/// Whether tosk may notify, checked without asking (again on every resume
/// and after a request).
final notificationAccessProvider = FutureProvider<NotificationAccess>((ref) async {
  ref.watch(reminderResumeProvider);
  final backend = ref.watch(reminderBackendProvider);
  if (!backend.supported) return NotificationAccess.unknown;
  return backend.checkPermission();
});

/// How asking for the notification permission ended.
enum ReminderPermissionOutcome {
  /// Allowed (already, or just now).
  granted,

  /// Refused (or the system no longer asks): Settings offers "Open settings".
  denied,

  /// The user said "Not now" to the explanation; nothing was asked.
  cancelled,
}

/// Asks for the notification permission at the moment it is needed (the
/// reminder is switched on, or its time is set): nothing when it is already
/// allowed; otherwise a one-line explanation first ([explain], true to go
/// on), then the system's request.
Future<ReminderPermissionOutcome> ensureReminderPermission(
  ReminderBackend backend, {
  required Future<bool> Function() explain,
}) async {
  if (await backend.checkPermission() == NotificationAccess.granted) return ReminderPermissionOutcome.granted;
  if (!await explain()) return ReminderPermissionOutcome.cancelled;
  return await backend.requestPermission() ? ReminderPermissionOutcome.granted : ReminderPermissionOutcome.denied;
}

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
  ref.watch(reminderResumeProvider);
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
