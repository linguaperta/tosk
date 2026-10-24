// Review screenshots of the first-run welcome with real fonts (no `_test`
// suffix, so not in the default run):
//   QA_OUT=../docs/screenshots/welcome flutter test test/qa/welcome_preview.dart
// Every page (Tosk, how it works, sign-in, Claude key) in colour, dark and
// black & white on a phone; a 320 px phone with text 1.3; desktop; and the
// course picker that follows on a fresh web-like start (downloads only).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/sync/sync_providers.dart';
import 'package:tosk/ui/courses/course_updates.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

import '../ui/course_downloads_test.dart' show FakeRemote, TestCatalog;
import '../ui/helpers.dart';
import '../ui/welcome_test.dart' show fakeSync, freshStore, key;
import 'brand_preview.dart' show loadQaFonts;

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa-welcome');
final _ratio = double.tryParse(Platform.environment['QA_RATIO'] ?? '') ?? 1;

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
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
    testWidgets('pages $mode', (tester) async {
      final service = await fakeSync(tester);
      await pumpApp(
        tester,
        size: const Size(390, 844),
        store: freshStore(settings),
        overrides: [syncServiceProvider.overrideWithValue(service)],
      );
      await _shot(tester, '1-tosk-$mode');
      await tapKey(tester, 'welcome-next');
      await _shot(tester, '2-how-$mode');
      await tapKey(tester, 'welcome-next');
      await _shot(tester, '3-sign-in-$mode');
      await tapKey(tester, 'welcome-sync-skip');
      await _shot(tester, '4-key-$mode');
      await tester.enterText(key('welcome-key-field'), 'sk-proj-123');
      await tapKey(tester, 'welcome-key-save');
      await _shot(tester, '5-key-invalid-$mode');
    });
  }

  testWidgets('small phone, text 1.3', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, size: const Size(320, 568), store: freshStore());
    await _shot(tester, 'small-1-tosk');
    await tapKey(tester, 'welcome-next');
    await _shot(tester, 'small-2-how');
    await tapKey(tester, 'welcome-next');
    await _shot(tester, 'small-4-key');
  });

  testWidgets('desktop', (tester) async {
    await pumpApp(tester, size: const Size(1280, 800), store: freshStore());
    await _shot(tester, 'desktop-1-tosk');
    await tapKey(tester, 'welcome-next');
    await _shot(tester, 'desktop-2-how');
    await tapKey(tester, 'welcome-next');
    await _shot(tester, 'desktop-4-key');
  });

  testWidgets('then the course picker (fresh web-like start)', (tester) async {
    await pumpApp(
      tester,
      size: const Size(390, 844),
      store: freshStore(),
      overrides: [
        courseCatalogProvider.overrideWithValue(DemoCourseCatalog()),
        remotePacksProvider.overrideWithValue(FakeRemote(TestCatalog())),
      ],
    );
    await tapKey(tester, 'welcome-skip-intro');
    await tapKey(tester, 'welcome-key-skip');
    await _shot(tester, '6-picker-colour');
  });
}
