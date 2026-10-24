// Review screenshots of the "ready for testers" screens with real fonts (no
// `_test` suffix, so not in the default run):
//   QA_OUT=<dir> flutter test test/qa/reports_preview.dart
// Settings → Feedback and About (signed in), Send feedback signed in and
// signed out, the flag sheet signed in, the crash screen, the Unverified
// explanation and the delete dialog, on a 390×844 phone (colour, dark, black
// & white) and a 320×568 phone with text 1.3.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/ui/shell/course_switcher.dart';

import '../ui/ai_flags_sounds_test.dart' show answerConjPick, scrollSettingsTo;
import '../ui/helpers.dart';
import '../ui/reports_ui_test.dart' show reporting, withSync;
import 'brand_preview.dart' show loadQaFonts;

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa-reports');

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(appRootKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
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
    testWidgets('settings and feedback $mode', (tester) async {
      final r = await reporting(tester);
      await pumpApp(
        tester,
        size: const Size(390, 844),
        store: TestProgressStore(settings: settings),
        initialLocation: Routes.settings,
        overrides: withSync(r),
      );
      await scrollSettingsTo(tester, 'open-feedback');
      await _shot(tester, 'settings-feedback-$mode');
      await scrollSettingsTo(tester, 'show-welcome');
      await _shot(tester, 'settings-about-$mode');
      await tapKey(tester, 'open-feedback');
      await tester.enterText(find.byKey(const ValueKey('feedback-text')), 'The map is lovely, but I miss a dark mode.');
      await tester.pumpAndSettle();
      await _shot(tester, 'feedback-signed-in-$mode');
    });
  }

  testWidgets('signed out and small', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final r = await reporting(tester, signIn: false);
    await pumpApp(tester, size: const Size(320, 568), initialLocation: Routes.feedback, overrides: withSync(r));
    await _shot(tester, 'feedback-signed-out-small');
  });

  testWidgets('flag sheet signed in, unverified, delete dialog', (tester) async {
    final r = await reporting(tester);
    await pumpApp(
      tester,
      size: const Size(390, 844),
      initialLocation: '/play/lab?skills=present-are&types=conj_pick&length=1',
      overrides: withSync(r),
    );
    await answerConjPick(tester, wrong: true);
    await tapKey(tester, 'flag-button');
    await _shot(tester, 'flag-sheet-signed-in');
  });

  testWidgets('unverified and delete dialog', (tester) async {
    final r = await reporting(tester);
    await pumpApp(tester, size: const Size(390, 844), initialLocation: Routes.settings, overrides: withSync(r));
    unawaited(showUnverifiedInfo(tester.element(find.byKey(const ValueKey('settings-list')))));
    await tester.pumpAndSettle();
    await _shot(tester, 'unverified-info');
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    await scrollSettingsTo(tester, 'sync-delete');
    await tapKey(tester, 'sync-delete');
    await _shot(tester, 'sync-delete-dialog');
  });
}
