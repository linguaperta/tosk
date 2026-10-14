// Batch B screens and states in black & white (pixel scan) and their layout
// (no overflow) at every e-ink harness size, plus color, dark mode and large
// text on phones and desktop: typed exercises with the accent bar, "I was
// right" (button, dialog, after), the daily goal on the map and the
// heatmap, the Settings sections (challenge, goal and reminder, backup) with
// the backup dialogs, and the map's jump button.
import 'dart:convert';
import 'dart:typed_data';

import 'package:tosk/core/core.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/goal/daily_goal_providers.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/backup_section.dart';
import 'package:tosk/ui/settings/learner_settings.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/big_map_course.dart';
import 'bw_helpers.dart';
import 'bw_mode_test.dart' show bwSizes;
import 'helpers.dart';
import 'v03b_features_test.dart' show FakeBackupFiles, FakeReminderBackend, seedXpToday;

typedef Check = Future<void> Function(String what);

const _typedTypes = [
  ('present-are', ExerciseType.conjPick),
  ('present-are', ExerciseType.conjGrid),
  ('greetings', ExerciseType.sentenceBuilder),
  ('present-are', ExerciseType.transform),
  ('essere-avere', ExerciseType.cloze),
];

Future<void> walkTyped(WidgetTester tester, Size size, Map<String, String> settings, Check check) async {
  for (final (skill, type) in _typedTypes) {
    await pumpApp(
      tester,
      size: size,
      store: TestProgressStore(settings: {...settings, LearnerSettingKeys.answerInput: 'type'}),
      initialLocation: Routes.labPlay(skills: [skill], types: [type], length: 1),
    );
    await check('typed ${type.id}: empty');
    await answerCurrentNoContinue(tester, wrong: true);
    await check('typed ${type.id}: wrong, "I was right"');
    if (type == ExerciseType.conjPick) {
      await tapKey(tester, 'override-button');
      await check('override dialog');
      await tapKey(tester, 'override-confirm');
      await check('after "I was right"');
    }
    await tester.pumpWidget(const SizedBox());
  }
}

Future<void> walkScreens(
  WidgetTester tester,
  Size size,
  Map<String, String> settings,
  Check check, {
  List<Override> extra = const [],
}) async {
  final files = FakeBackupFiles();
  final store = TestProgressStore(settings: {...settings, LearnerSettingKeys.reminderEnabled: 'true'});
  await seedXpToday(store, 56);
  await pumpApp(
    tester,
    size: size,
    store: store,
    overrides: [
      reminderBackendProvider.overrideWithValue(FakeReminderBackend()),
      backupFilesProvider.overrideWithValue(files),
      ...extra,
    ],
  );
  await check('map with the goal met');
  await goTab(tester, 'Progress');
  await check('progress with goal notches');
  await goTab(tester, 'Settings');
  for (final key in ['setting-answer-input', 'reminder-time', 'backup-import']) {
    await scrollToFind(tester, find.byKey(ValueKey(key)));
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await check('settings: $key');
  }
  await tapKey(tester, 'backup-export');
  await check('backup saved');
  files.next = (name: 'b.jsonl', bytes: files.saved.values.first);
  await tapKey(tester, 'backup-import');
  await check('backup confirm');
  await tapKey(tester, 'backup-import-confirm');
  await check('backup result');
  await tapKey(tester, 'backup-result-ok');
  files.next = (name: 'notes.txt', bytes: Uint8List.fromList(utf8.encode('hello')));
  await tapKey(tester, 'backup-import');
  await check('backup refused');
  await tester.pumpWidget(const SizedBox());

  // A long map with the jump button; the goal not met yet.
  final course = bigMapCourse();
  await pumpApp(
    tester,
    size: size,
    store: TestProgressStore(
      settings: {...settings, SettingKeys.course: course.meta.id, SettingKeys.coursesAdded: course.meta.id},
    ),
    overrides: [courseCatalogProvider.overrideWithValue(BigCourseCatalog())],
  );
  expect(find.byKey(const ValueKey('jump-current-unit')), findsOneWidget);
  await check('long map with jump button and goal progress');
  await tester.pumpWidget(const SizedBox());
}

void main() {
  for (final entry in bwSizes.entries) {
    group('black & white ${entry.key}', () {
      Future<void> bwCheck(WidgetTester tester, String what) async {
        await expectGrayscale(tester, what);
        expect(tester.takeException(), isNull, reason: what);
      }

      testWidgets('typed exercises, accent bar, "I was right"', (tester) async {
        await walkTyped(tester, entry.value, {SettingKeys.display: 'bw'}, (w) => bwCheck(tester, w));
      });

      testWidgets('goal, settings sections, backup dialogs, jump button', (tester) async {
        await walkScreens(tester, entry.value, {SettingKeys.display: 'bw'}, (w) => bwCheck(tester, w));
      });
    });
  }

  group('color, dark and large text', () {
    for (final size in const [Size(320, 568), Size(360, 640), Size(1280, 800)]) {
      testWidgets('batch B at ${size.width.toInt()}x${size.height.toInt()}, text 1.3, dark', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const dark = {SettingKeys.themeMode: 'dark'};
        Future<void> check(String what) async => expect(tester.takeException(), isNull, reason: what);
        await walkTyped(tester, size, dark, check);
        await walkScreens(tester, size, dark, check);
      });
    }
  });
}
