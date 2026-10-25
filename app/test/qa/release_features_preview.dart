// Review screenshots of the release features with real fonts (no `_test`
// suffix, so not in the default run):
//   QA_OUT=../docs/screenshots/release-features flutter test test/qa/release_features_preview.dart
// The update notice (sideloaded) and the web's reload notice and "What's new"
// sheet; the reminder's permission states (explanation, notifications off,
// allowed, the web note). Phone, colour, dark and black & white.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/reminders/reminder_backend.dart';
import 'package:tosk/ui/goal/daily_goal_providers.dart';
import 'package:tosk/ui/settings/learner_settings.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/updates/web_update.dart';

import '../ui/helpers.dart';
import '../ui/reminder_permission_test.dart' show openReminderSettings;
import '../ui/update_notice_test.dart' show githubOverrides, update077, webOverrides;
import '../ui/v03b_features_test.dart' show FakeReminderBackend;
import '../updates/update_check_test.dart' show FakeReleaseSource;
import '../updates/web_update_test.dart' show FakeWebUpdateSource, whatsNew;
import 'brand_preview.dart' show loadQaFonts;

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa-release-features');
final _ratio = double.tryParse(Platform.environment['QA_RATIO'] ?? '') ?? 1;
const _phone = Size(390, 844);

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(appRootKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _ratio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    _out.createSync(recursive: true);
    File('${_out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(loadQaFonts);

  for (final (mode, settings) in [
    ('colour', <String, String>{}),
    ('dark', {SettingKeys.themeMode: 'dark'}),
    ('bw', {SettingKeys.display: 'bw'}),
  ]) {
    testWidgets('update notice $mode', (tester) async {
      final source = FakeReleaseSource([update077()]);
      await pumpApp(
        tester,
        size: _phone,
        store: TestProgressStore(settings: settings),
        overrides: githubOverrides(source),
      );
      await _shot(tester, '1-update-notice-$mode');
      await goTab(tester, 'Settings');
      await scrollToFind(tester, find.byKey(const ValueKey('check-updates')));
      await tester.ensureVisible(find.byKey(const ValueKey('check-updates')));
      await _shot(tester, '2-check-for-updates-$mode');
    });

    testWidgets('web $mode', (tester) async {
      final web = FakeWebUpdateSource(deployed: whatsNew('0.7.7', build: 'bbb222'));
      await pumpApp(
        tester,
        size: _phone,
        store: TestProgressStore(settings: {...settings, kWhatsNewSeenKey: '0.7.6'}),
        overrides: webOverrides(web),
      );
      web.workerTakesOver();
      await _shot(tester, '3-web-reload-$mode');
      await tester.pumpWidget(const SizedBox());
      final after = FakeWebUpdateSource(
        deployed: whatsNew(
          '0.7.7',
          build: 'aaa111',
          notes:
              'Preview (arm64). Restructured courses with topic trees:\n\n'
              '- slim main trees (grammar and core vocabulary)\n'
              '- themed topics on tappable branches, the name carved into the bark\n'
              '- a tree menu, and "needs …" notes on locked topic skills',
        ),
      );
      await pumpApp(
        tester,
        size: _phone,
        store: TestProgressStore(settings: {...settings, kWhatsNewSeenKey: '0.7.6'}),
        overrides: webOverrides(after, version: '0.7.7'),
      );
      await _shot(tester, '4-whats-new-$mode');
    });

    testWidgets('reminder $mode', (tester) async {
      final backend = FakeReminderBackend(grant: false);
      await pumpApp(
        tester,
        size: _phone,
        store: TestProgressStore(settings: settings),
        overrides: [reminderBackendProvider.overrideWithValue(backend)],
      );
      await openReminderSettings(tester);
      await _shot(tester, '5-reminder-off-$mode');
      await tapKey(tester, 'reminder-switch');
      await _shot(tester, '6-reminder-explain-$mode');
      await tapKey(tester, 'reminder-explain-continue');
      await tester.ensureVisible(find.byKey(const ValueKey('reminder-denied')));
      await _shot(tester, '7-reminder-denied-$mode');
      await tester.pumpWidget(const SizedBox());

      await pumpApp(
        tester,
        size: _phone,
        store: TestProgressStore(settings: {...settings, LearnerSettingKeys.reminderEnabled: 'true'}),
        overrides: [reminderBackendProvider.overrideWithValue(FakeReminderBackend(access: NotificationAccess.granted))],
      );
      await openReminderSettings(tester);
      await _shot(tester, '8-reminder-on-$mode');
    });

    testWidgets('reminder on the web $mode', (tester) async {
      await pumpApp(
        tester,
        size: _phone,
        store: TestProgressStore(settings: settings),
        overrides: [
          reminderBackendProvider.overrideWithValue(FakeReminderBackend(supported: false)),
          remindersUnavailableNoteProvider.overrideWithValue(
            "Daily reminders need the Android app: a browser can't reliably send a notification at a set time.",
          ),
        ],
      );
      await goTab(tester, 'Settings');
      await scrollToFind(tester, find.byKey(const ValueKey('reminder-unavailable')));
      await tester.ensureVisible(find.byKey(const ValueKey('reminder-unavailable')));
      await _shot(tester, '9-reminder-web-$mode');
    });
  }
}
