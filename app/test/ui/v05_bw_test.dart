// v0.5 screens and states in black & white (pixel scan) and their layout (no
// overflow) at every e-ink harness size, plus color, dark mode and large text
// on phones and desktop: the writing pad (empty, written, checked, the model
// download, the keyboard fallback) in cloze, grid and sentence exercises,
// listen and pick (new and checked), the pronounce buttons (word page,
// flashcard, word popover) and the Settings additions (Write, the model,
// listening, the E-reader section).
import 'package:tosk/core/core.dart';
import 'package:tosk/ink/ink_recognizer.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/learner_settings.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bw_helpers.dart';
import 'bw_mode_test.dart' show bwSizes;
import 'fakes/v05_fakes.dart';
import 'helpers.dart';
import 'v05_features_test.dart' show write;

typedef Check = Future<void> Function(String what);

Future<void> walkInk(WidgetTester tester, Size size, Map<String, String> settings, Check check) async {
  final all = {...settings, LearnerSettingKeys.answerInput: 'handwrite'};
  for (final (skill, type, pad) in const [
    ('passato', ExerciseType.cloze, 'ink-pad'),
    ('essere-avere', ExerciseType.conjGrid, 'grid-ink-pad'),
    ('present-ere', ExerciseType.sentenceBuilder, 'ink-pad'),
    ('present-ire', ExerciseType.conjPick, 'ink-pad'),
  ]) {
    final ink = FakeInkRecognizer(reading: ['xyz', 'xy']);
    await pumpApp(
      tester,
      size: size,
      store: TestProgressStore(settings: all),
      overrides: v05Overrides(ink: ink, speaker: FakeSpeaker()),
      initialLocation: Routes.labPlay(skills: [skill], types: [type], length: 1),
    );
    await check('ink ${type.id}: empty pad');
    await write(tester, padKey: pad);
    await check('ink ${type.id}: written');
    if (type == ExerciseType.sentenceBuilder) {
      await tapKey(tester, 'ink-space');
      await write(tester, padKey: pad);
      await check('ink ${type.id}: two parts');
    }
    if (find.byKey(const ValueKey('check-button')).evaluate().isNotEmpty &&
        tester.widget<FilledButton>(find.byKey(const ValueKey('check-button'))).onPressed != null) {
      await tapKey(tester, 'check-button');
      await check('ink ${type.id}: checked (wrong)');
    }
    await tester.pumpWidget(const SizedBox());
  }

  // The model download in the pad, then the keyboard fallback.
  await pumpApp(
    tester,
    size: size,
    store: TestProgressStore(settings: all),
    overrides: v05Overrides(ink: FakeInkRecognizer(status: InkModelStatus.missing)),
    initialLocation: Routes.labPlay(skills: ['passato'], types: [ExerciseType.cloze], length: 1),
  );
  await check('ink: model download');
  await tapKey(tester, 'ink-keyboard');
  await check('ink: keyboard fallback');
  await tester.pumpWidget(const SizedBox());
}

Future<void> walkListening(WidgetTester tester, Size size, Map<String, String> settings, Check check) async {
  final speaker = FakeSpeaker();
  await pumpApp(
    tester,
    size: size,
    store: TestProgressStore(settings: settings),
    overrides: v05Overrides(speaker: speaker),
    initialLocation: Routes.labPlay(skills: ['time'], types: [ExerciseType.listenPick], length: 1),
  );
  await check('listen: new');
  await answerCurrentNoContinue(tester, wrong: true);
  await check('listen: wrong, translation');
  await tester.pumpWidget(const SizedBox());

  await pumpApp(
    tester,
    size: size,
    store: TestProgressStore(settings: settings),
    overrides: v05Overrides(speaker: speaker),
    initialLocation: Routes.labPlay(skills: ['time'], types: [ExerciseType.flashcard], length: 1),
  );
  await check('flashcard with pronounce');
  await tester.pumpWidget(const SizedBox());

  await pumpApp(
    tester,
    size: size,
    store: TestProgressStore(settings: settings),
    overrides: v05Overrides(speaker: speaker),
    initialLocation: Routes.word('it:pane'),
  );
  await check('word page with pronounce');
  await tester.pumpWidget(const SizedBox());

  await pumpApp(
    tester,
    size: size,
    store: TestProgressStore(settings: settings),
    overrides: v05Overrides(speaker: speaker),
    initialLocation: Routes.labPlay(skills: ['passato'], types: [ExerciseType.cloze], length: 1),
  );
  await tapKey(tester, 'word-0');
  expect(find.byKey(const ValueKey('word-popover-pronounce')), findsOneWidget);
  await check('word popover with pronounce');
  await tester.pumpWidget(const SizedBox());
}

Future<void> walkSettings(WidgetTester tester, Size size, Map<String, String> settings, Check check) async {
  await pumpApp(
    tester,
    size: size,
    store: TestProgressStore(settings: {...settings, LearnerSettingKeys.answerInput: 'handwrite'}),
    overrides: v05Overrides(
      ink: FakeInkRecognizer(status: InkModelStatus.missing),
      speaker: FakeSpeaker(),
      onyx: true,
      eink: FakeEinkScreen(),
    ),
    initialLocation: Routes.settings,
  );
  for (final key in ['setting-answer-input', 'setting-ink-model', 'setting-listening', 'setting-onyx-pen']) {
    await scrollToFind(tester, find.byKey(ValueKey(key)));
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await check('settings: $key');
  }
  await tester.pumpWidget(const SizedBox());
}

void main() {
  for (final entry in bwSizes.entries) {
    group('black & white ${entry.key}', () {
      Future<void> bwCheck(WidgetTester tester, String what) async {
        await expectGrayscale(tester, what);
        expect(tester.takeException(), isNull, reason: what);
      }

      const bw = {SettingKeys.display: 'bw'};
      testWidgets('writing pad in every handwritten exercise', (tester) async {
        await walkInk(tester, entry.value, bw, (w) => bwCheck(tester, w));
      });
      testWidgets('listen and pick, pronounce buttons', (tester) async {
        await walkListening(tester, entry.value, bw, (w) => bwCheck(tester, w));
      });
      testWidgets('settings: write, model, listening, e-reader', (tester) async {
        await walkSettings(tester, entry.value, bw, (w) => bwCheck(tester, w));
      });
    });
  }

  group('color, dark and large text', () {
    for (final size in const [Size(320, 568), Size(360, 640), Size(1280, 800)]) {
      testWidgets('v0.5 at ${size.width.toInt()}x${size.height.toInt()}, text 1.3, dark', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const dark = {SettingKeys.themeMode: 'dark'};
        Future<void> check(String what) async => expect(tester.takeException(), isNull, reason: what);
        await walkInk(tester, size, dark, check);
        await walkListening(tester, size, dark, check);
        await walkSettings(tester, size, dark, check);
      });
    }
  });
}
