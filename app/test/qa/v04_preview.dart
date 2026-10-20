// Review screenshots of the v0.4 extras with real fonts (no `_test` suffix,
// so not in the default run):
//   QA_OUT=<dir> [QA_RATIO=1] flutter test test/qa/v04_preview.dart
// Saves, in colour, dark and black & white at 360x640: the Progress stats
// card and Starred entry, the stats page (14 and 30 days, accuracy), the
// Starred list, the feedback panel's Star sheet, the Chat tab and a chat
// with a correction and a translation. HTTP is a MockClient.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:tosk/ai/ai_config.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/helpers.dart';
import '../ui/v04_bw_test.dart' show starredRepo;
import '../ui/v04_extras_test.dart' show FakeTutorAi, seededStore, settleAi, tutorOverrides;
import 'brand_preview.dart' show loadQaFonts;

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa-v04');
final _ratio = double.tryParse(Platform.environment['QA_RATIO'] ?? '') ?? 2;

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
  const size = Size(360, 640);
  for (final (mode, settings) in [
    ('color', <String, String>{}),
    ('dark', {SettingKeys.themeMode: 'dark'}),
    ('bw', {SettingKeys.display: 'bw'}),
  ]) {
    testWidgets('v0.4 extras, $mode', (tester) async {
      final marks = bookmarkRepoProvider.overrideWithValue(await starredRepo());
      await pumpApp(tester, size: size, store: await seededStore(settings), initialLocation: Routes.progress, overrides: [marks]);
      await scrollToFind(tester, find.byKey(const ValueKey('stats-summary')));
      await tester.ensureVisible(find.byKey(const ValueKey('stats-summary')));
      await tester.pumpAndSettle();
      await _shot(tester, '${mode}_progress_stats');
      await tester.pumpWidget(const SizedBox());

      await pumpApp(tester, size: size, store: await seededStore(settings), initialLocation: Routes.stats);
      await _shot(tester, '${mode}_stats_14');
      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();
      await _shot(tester, '${mode}_stats_30');
      await scrollToFind(tester, find.byKey(const ValueKey('stats-by-kind')));
      await tester.ensureVisible(find.byKey(const ValueKey('stats-by-kind')));
      await tester.pumpAndSettle();
      await _shot(tester, '${mode}_stats_accuracy');
      await tester.pumpWidget(const SizedBox());

      await pumpApp(tester, size: size, store: TestProgressStore(settings: settings), initialLocation: Routes.starred, overrides: [marks]);
      await _shot(tester, '${mode}_starred');
      await tester.pumpWidget(const SizedBox());

      final skills = buildDemoItalian().skills.map((s) => s.id).toList();
      await pumpApp(
        tester,
        size: size,
        store: TestProgressStore(settings: settings),
        initialLocation: Routes.labPlay(skills: skills, types: [ExerciseType.cloze], length: 1),
        overrides: [marks],
      );
      await answerCurrentNoContinue(tester, wrong: true);
      await _shot(tester, '${mode}_feedback_star');
      await tapKey(tester, 'star-button');
      await _shot(tester, '${mode}_star_sheet');
      await tester.pumpWidget(const SizedBox());

      final ai = FakeTutorAi();
      await pumpApp(
        tester,
        size: size,
        store: TestProgressStore(settings: {...settings, AiSettingKeys.provider: 'anthropic'}),
        initialLocation: Routes.chats,
        overrides: tutorOverrides(ai),
      );
      await _shot(tester, '${mode}_chat_tab');
      await tester.tap(find.byKey(const ValueKey('chat-start')));
      await settleAi(tester);
      await tapKey(tester, 'chat-translate-0');
      await _shot(tester, '${mode}_chat');
      await tester.pumpWidget(const SizedBox());
    });
  }
}
