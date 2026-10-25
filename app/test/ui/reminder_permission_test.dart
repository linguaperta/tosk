// The daily reminder on Android 13+ (and iOS/macOS): the notification
// permission is asked for at the moment it is needed (switching the reminder
// on, setting its time while notifications are off) after a one-line
// explanation; "denied" keeps the reminder on with "Notifications are off for
// tosk — Open settings"; coming back to the app checks again and re-plans.
// The web shows a short note instead of the reminder.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/app.dart';
import 'package:tosk/progression/calendar.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/reminders/reminder_backend.dart';
import 'package:tosk/ui/goal/daily_goal_providers.dart';
import 'package:tosk/ui/settings/learner_settings.dart';

import 'helpers.dart';
import 'v03b_features_test.dart' show FakeReminderBackend;

Future<void> openReminderSettings(WidgetTester tester) async {
  await goTab(tester, 'Settings');
  await scrollToFind(tester, find.byKey(const ValueKey('reminder-switch')));
  await tester.ensureVisible(find.byKey(const ValueKey('reminder-switch')));
  await tester.pumpAndSettle();
}

/// The app going to the background and coming back.
Future<void> backgroundAndResume(WidgetTester tester) async {
  for (final s in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await tester.pumpAndSettle();
}

void main() {
  group('ensureReminderPermission', () {
    test('already allowed: no explanation, no request', () async {
      final b = FakeReminderBackend(access: NotificationAccess.granted);
      var explained = 0;
      final outcome = await ensureReminderPermission(b, explain: () async => ++explained > 0);
      expect(outcome, ReminderPermissionOutcome.granted);
      expect(explained, 0);
      expect(b.permissionRequests, 0);
    });

    test('not allowed: explanation first, then the request', () async {
      final yes = FakeReminderBackend();
      expect(await ensureReminderPermission(yes, explain: () async => true), ReminderPermissionOutcome.granted);
      expect(yes.permissionRequests, 1);

      final no = FakeReminderBackend(grant: false);
      expect(await ensureReminderPermission(no, explain: () async => true), ReminderPermissionOutcome.denied);

      final notNow = FakeReminderBackend();
      expect(await ensureReminderPermission(notNow, explain: () async => false), ReminderPermissionOutcome.cancelled);
      expect(notNow.permissionRequests, 0, reason: 'never asked without the explanation');
    });

    test('unknown (a failed check) is asked like denied', () async {
      final b = FakeReminderBackend(access: NotificationAccess.unknown);
      expect(await ensureReminderPermission(b, explain: () async => true), ReminderPermissionOutcome.granted);
      expect(b.permissionRequests, 1);
    });
  });

  group('settings', () {
    testWidgets('"Not now" leaves the reminder off and asks nothing', (tester) async {
      final backend = FakeReminderBackend();
      final store = await pumpApp(
        tester,
        size: const Size(390, 844),
        overrides: [reminderBackendProvider.overrideWithValue(backend)],
      );
      await openReminderSettings(tester);
      await tapKey(tester, 'reminder-switch');
      expect(find.byKey(const ValueKey('reminder-explain')), findsOneWidget);
      expect(find.textContaining('one notification at 7:00 PM'), findsOneWidget);
      await tapKey(tester, 'reminder-explain-cancel');
      expect(backend.permissionRequests, 0);
      expect(store.settings[LearnerSettingKeys.reminderEnabled], isNot('true'));
      expect(find.byKey(const ValueKey('reminder-denied')), findsNothing);
    });

    testWidgets('already allowed: switching on asks nothing', (tester) async {
      final backend = FakeReminderBackend(access: NotificationAccess.granted);
      final store = await pumpApp(
        tester,
        size: const Size(390, 844),
        overrides: [reminderBackendProvider.overrideWithValue(backend)],
      );
      await openReminderSettings(tester);
      await tapKey(tester, 'reminder-switch');
      expect(find.byKey(const ValueKey('reminder-explain')), findsNothing);
      expect(backend.permissionRequests, 0);
      expect(store.settings[LearnerSettingKeys.reminderEnabled], 'true');
      expect(backend.scheduled.last, hasLength(7));
    });

    testWidgets('denied: "Notifications are off" with Open settings; allowed there, it clears on resume', (
      tester,
    ) async {
      final backend = FakeReminderBackend(grant: false);
      final store = await pumpApp(
        tester,
        size: const Size(390, 844),
        overrides: [reminderBackendProvider.overrideWithValue(backend)],
      );
      await openReminderSettings(tester);
      await tapKey(tester, 'reminder-switch');
      await tapKey(tester, 'reminder-explain-continue');
      expect(store.settings[LearnerSettingKeys.reminderEnabled], 'true');
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('reminder-switch'))).value, isTrue);
      expect(find.text('Notifications are off for tosk'), findsOneWidget);
      expect(find.byKey(const ValueKey('reminder-denied')), findsOneWidget);
      // Scheduled anyway: the reminders appear as soon as they are allowed.
      expect(backend.scheduled.last, hasLength(7));

      await tapKey(tester, 'reminder-open-settings');
      expect(backend.settingsOpened, 1);
      // The learner allows notifications in the system settings and comes back.
      backend.access = NotificationAccess.granted;
      final checks = backend.permissionChecks;
      await backgroundAndResume(tester);
      expect(backend.permissionChecks, greaterThan(checks));
      expect(find.byKey(const ValueKey('reminder-denied')), findsNothing);
      expect(find.text('Notifications are off for tosk'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('turned off in the system settings later: the warning appears on resume', (tester) async {
      final backend = FakeReminderBackend(access: NotificationAccess.granted);
      await pumpApp(
        tester,
        size: const Size(390, 844),
        store: TestProgressStore(settings: {LearnerSettingKeys.reminderEnabled: 'true'}),
        overrides: [reminderBackendProvider.overrideWithValue(backend)],
      );
      await openReminderSettings(tester);
      expect(find.byKey(const ValueKey('reminder-denied')), findsNothing);
      backend.access = NotificationAccess.denied;
      await backgroundAndResume(tester);
      expect(find.byKey(const ValueKey('reminder-denied')), findsOneWidget);
    });

    testWidgets('setting the time while notifications are off asks again', (tester) async {
      final backend = FakeReminderBackend(grant: false);
      await pumpApp(
        tester,
        size: const Size(390, 844),
        store: TestProgressStore(settings: {LearnerSettingKeys.reminderEnabled: 'true'}),
        overrides: [reminderBackendProvider.overrideWithValue(backend)],
      );
      await openReminderSettings(tester);
      await tapKey(tester, 'reminder-time');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reminder-explain')), findsOneWidget);
      backend.grant = true;
      await tapKey(tester, 'reminder-explain-continue');
      expect(backend.permissionRequests, 1);
      expect(find.byKey(const ValueKey('reminder-denied')), findsNothing);

      // Allowed now: another time asks nothing.
      await tapKey(tester, 'reminder-time');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reminder-explain')), findsNothing);
      expect(backend.permissionRequests, 1);
    });

    testWidgets('the web: a short note instead of the reminder', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        overrides: [
          reminderBackendProvider.overrideWithValue(FakeReminderBackend(supported: false)),
          remindersUnavailableNoteProvider.overrideWithValue('Daily reminders need the Android app.'),
        ],
      );
      await goTab(tester, 'Settings');
      await scrollToFind(tester, find.byKey(const ValueKey('reminder-unavailable')));
      expect(find.byKey(const ValueKey('reminder-unavailable')), findsOneWidget);
      expect(find.text('Daily reminders need the Android app.'), findsOneWidget);
      expect(find.byKey(const ValueKey('reminder-switch')), findsNothing);
    });

    testWidgets('Windows and other platforms without a note: no reminder row at all', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        overrides: [reminderBackendProvider.overrideWithValue(FakeReminderBackend(supported: false))],
      );
      await goTab(tester, 'Settings');
      await scrollToFind(tester, find.byKey(const ValueKey('backup-import')));
      expect(find.byKey(const ValueKey('reminder-unavailable')), findsNothing);
      expect(find.byKey(const ValueKey('reminder-switch')), findsNothing);
    });
  });

  testWidgets('resume re-plans: a reminder whose time passed while away is dropped', (tester) async {
    var now = testNow; // 12:00 UTC; the reminder is at 19:00 local (UTC in tests).
    final backend = FakeReminderBackend(access: NotificationAccess.granted);
    setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          progressStoreProvider.overrideWithValue(
            TestProgressStore(settings: {LearnerSettingKeys.reminderEnabled: 'true'}),
          ),
          clockProvider.overrideWithValue(() => now),
          calendarProvider.overrideWithValue(LocalCalendar.utc),
          fakeSessionFactoryOverride,
          reminderBackendProvider.overrideWithValue(backend),
        ],
        child: const RepaintBoundary(key: appRootKey, child: ToskApp()),
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.scheduled.last, hasLength(7));
    final before = backend.scheduled.length;
    await backgroundAndResume(tester);
    expect(backend.scheduled.length, before, reason: 'nothing changed: no plugin calls');
    now = testNow.add(const Duration(hours: 8)); // 20:00, past today's 19:00
    await backgroundAndResume(tester);
    expect(backend.scheduled.length, before + 1);
    expect(backend.scheduled.last, hasLength(6));
    expect(backend.scheduled.last.first.at.isAfter(now), isTrue);
  });
}
