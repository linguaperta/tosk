// Golden images of the release features: the update notice (sideloaded) and
// the web's reload notice, and the reminder's permission states (the
// explanation, "Notifications are off"), in colour and black & white on a
// phone. Test font (Ahem), like bw_golden_test.dart. Update with:
//   flutter test --update-goldens test/ui/release_features_golden_test.dart
// Rendered on Windows; CI (Linux) skips them with --exclude-tags golden.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/reminders/reminder_backend.dart';
import 'package:tosk/ui/goal/daily_goal_providers.dart';
import 'package:tosk/ui/settings/learner_settings.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/updates/web_update.dart';

import '../updates/update_check_test.dart' show FakeReleaseSource;
import '../updates/web_update_test.dart' show FakeWebUpdateSource, whatsNew;
import 'helpers.dart';
import 'reminder_permission_test.dart' show openReminderSettings;
import 'update_notice_test.dart' show githubOverrides, update077, webOverrides;
import 'v03b_features_test.dart' show FakeReminderBackend;

const _phone = Size(390, 844);

Future<void> _golden(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await expectLater(find.byKey(appRootKey), matchesGoldenFile('goldens/release_$name.png'));
}

void main() {
  for (final (mode, settings) in [
    ('colour', <String, String>{}),
    ('bw', {SettingKeys.display: 'bw'}),
  ]) {
    testWidgets('update notice $mode', (tester) async {
      await pumpApp(
        tester,
        size: _phone,
        store: TestProgressStore(settings: settings),
        overrides: githubOverrides(FakeReleaseSource([update077()])),
      );
      await _golden(tester, 'update_$mode');
    });

    testWidgets('web reload notice $mode', (tester) async {
      final web = FakeWebUpdateSource(deployed: whatsNew('0.7.7', build: 'bbb222'));
      await pumpApp(
        tester,
        size: _phone,
        store: TestProgressStore(settings: {...settings, kWhatsNewSeenKey: '0.7.6'}),
        overrides: webOverrides(web),
      );
      web.workerTakesOver();
      await _golden(tester, 'web_reload_$mode');
    });

    testWidgets('reminder permission $mode', (tester) async {
      final backend = FakeReminderBackend(grant: false);
      await pumpApp(
        tester,
        size: _phone,
        store: TestProgressStore(settings: settings),
        overrides: [reminderBackendProvider.overrideWithValue(backend)],
      );
      await openReminderSettings(tester);
      await tapKey(tester, 'reminder-switch');
      await _golden(tester, 'reminder_explain_$mode');
      await tapKey(tester, 'reminder-explain-continue');
      await tester.ensureVisible(find.byKey(const ValueKey('reminder-denied')));
      await _golden(tester, 'reminder_denied_$mode');
    });
  }

  testWidgets('reminder allowed (colour)', (tester) async {
    await pumpApp(
      tester,
      size: _phone,
      store: TestProgressStore(settings: {LearnerSettingKeys.reminderEnabled: 'true'}),
      overrides: [reminderBackendProvider.overrideWithValue(FakeReminderBackend(access: NotificationAccess.granted))],
    );
    await openReminderSettings(tester);
    await _golden(tester, 'reminder_on_colour');
  });
}
