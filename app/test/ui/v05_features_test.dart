// v0.5: handwriting (the writing pad in every production exercise, the model
// download, the keyboard fallback, palm rejection, the Onyx pen surface),
// listening (listen_pick, the voice capability, pronounce buttons), and the
// e-ink full refresh on ONYX devices. ML Kit, text-to-speech and the Onyx
// channels are fakes (test/ui/fakes/v05_fakes.dart).
import 'dart:ui' show PointerDeviceKind;

import 'package:tosk/core/core.dart';
import 'package:tosk/device/device_providers.dart';
import 'package:tosk/ink/ink_recognizer.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/ink/ink_pad.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/learner_settings.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/v05_fakes.dart';
import 'helpers.dart';

const _write = {LearnerSettingKeys.answerInput: 'handwrite'};

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byKey(appRootKey)));

/// Writes one stroke on the pad [padKey] and waits for the recognition.
Future<void> write(WidgetTester tester, {String padKey = 'ink-pad', PointerDeviceKind kind = PointerDeviceKind.touch}) async {
  final pad = find.byKey(ValueKey(padKey));
  await tester.ensureVisible(pad);
  await tester.pumpAndSettle();
  final c = tester.getCenter(pad);
  final g = await tester.startGesture(c - const Offset(40, 0), kind: kind);
  for (var i = 1; i <= 8; i++) {
    await g.moveTo(c - const Offset(40, 0) + Offset(i * 10.0, (i % 2) * 8.0));
  }
  await g.up();
  await tester.pump(const Duration(milliseconds: 500)); // the recognition debounce
  await tester.pumpAndSettle();
}

Future<void> check(WidgetTester tester) => tapKey(tester, 'check-button');

bool _correct(WidgetTester tester) => find.text('Correct!').evaluate().isNotEmpty;

void main() {
  group('handwriting', () {
    testWidgets('Settings offers Write only where the recognizer runs; the model tile downloads', (tester) async {
      // Default (flutter test): no recognizer, so no Write option.
      await pumpApp(tester, initialLocation: Routes.settings);
      await scrollToFind(tester, find.byKey(const ValueKey('setting-answer-input')));
      expect(find.byKey(const ValueKey('setting-answer-input-Write')), findsNothing);
      await tester.pumpWidget(const SizedBox());

      final ink = FakeInkRecognizer(status: InkModelStatus.missing);
      final store = await pumpApp(tester, initialLocation: Routes.settings, overrides: v05Overrides(ink: ink));
      await scrollToFind(tester, find.byKey(const ValueKey('setting-answer-input-Write')));
      await tapKey(tester, 'setting-answer-input-Write');
      expect(store.settings[LearnerSettingKeys.answerInput], 'handwrite');
      expect(_container(tester).read(sessionOptionsProvider).preferredInput, InputMode.ink);
      await scrollToFind(tester, find.byKey(const ValueKey('setting-ink-model')));
      expect(find.text('Handwriting model: Italian'), findsOneWidget);
      await tapKey(tester, 'ink-model-download');
      expect(ink.downloads, ['it']);
      expect(find.textContaining('Downloaded: works offline'), findsOneWidget);
    });

    testWidgets('cloze: write the word; accepted when a lower candidate matches', (tester) async {
      final ink = FakeInkRecognizer(reading: ['bo', 'ho']);
      await pumpApp(
        tester,
        store: TestProgressStore(settings: _write),
        overrides: v05Overrides(ink: ink),
        initialLocation: Routes.labPlay(skills: ['passato'], types: [ExerciseType.cloze], length: 1),
      );
      expect(find.byKey(const ValueKey('ink-pad')), findsOneWidget);
      // Nothing written: no answer yet.
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('check-button'))).onPressed, isNull);
      await write(tester);
      expect(ink.calls.single.$2, 'Ieri ', reason: 'the words before the gap are the context');
      expect(find.text('Read as: bo'), findsOneWidget);
      await check(tester);
      expect(_correct(tester), isTrue);
    });

    testWidgets('undo and clear take the answer back', (tester) async {
      final ink = FakeInkRecognizer(reading: ['ho']);
      await pumpApp(
        tester,
        store: TestProgressStore(settings: _write),
        overrides: v05Overrides(ink: ink),
        initialLocation: Routes.labPlay(skills: ['passato'], types: [ExerciseType.cloze], length: 1),
      );
      await write(tester);
      await write(tester);
      expect(ink.calls.last.$1, 2);
      await tapKey(tester, 'ink-undo');
      await tester.pumpAndSettle();
      expect(ink.calls.last.$1, 1);
      await tapKey(tester, 'ink-clear');
      expect(find.text('Nothing written yet'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('check-button'))).onPressed, isNull);
    });

    testWidgets('conjugation pick: the stem is the context; the ending or the whole form counts', (tester) async {
      final ink = FakeInkRecognizer(reading: ['ono']);
      await pumpApp(
        tester,
        store: TestProgressStore(settings: _write),
        overrides: v05Overrides(ink: ink),
        initialLocation: Routes.labPlay(skills: ['present-ire'], types: [ExerciseType.conjPick], length: 1),
      );
      expect(find.byKey(const ValueKey('conj-pick-ink')), findsOneWidget);
      await write(tester);
      expect(ink.calls.single.$2, 'dorm');
      await check(tester);
      expect(_correct(tester), isTrue);
    });

    testWidgets('conjugation grid: one cell at a time with "Next cell"', (tester) async {
      final ink = FakeInkRecognizer();
      ink.readings.addAll([
        ['ho'],
        ['hai'],
        ['ha'],
        ['harmo', 'hanno'],
      ]);
      await pumpApp(
        tester,
        store: TestProgressStore(settings: _write),
        overrides: v05Overrides(ink: ink),
        initialLocation: Routes.labPlay(skills: ['essere-avere'], types: [ExerciseType.conjGrid], length: 1),
      );
      expect(find.byKey(const ValueKey('grid-tile-0')), findsNothing, reason: 'no tile bank');
      for (var k = 0; k < 4; k++) {
        await write(tester, padKey: 'grid-ink-pad');
        if (k < 3) await tapKey(tester, 'ink-action');
      }
      expect(find.text('harmo'), findsOneWidget, reason: 'the cell shows the best reading');
      await check(tester);
      expect(_correct(tester), isTrue, reason: 'hanno is a candidate of the last cell');
    });

    testWidgets('sentence builder: written in parts with "Next word"', (tester) async {
      final ink = FakeInkRecognizer();
      ink.readings.addAll([
        ['Leggo'],
        ['un', 'nn'],
        ['libro'],
      ]);
      await pumpApp(
        tester,
        store: TestProgressStore(settings: _write),
        overrides: v05Overrides(ink: ink),
        initialLocation: Routes.labPlay(skills: ['present-ere'], types: [ExerciseType.sentenceBuilder], length: 1),
      );
      await write(tester);
      await tapKey(tester, 'ink-space');
      await write(tester);
      await tapKey(tester, 'ink-space');
      await write(tester);
      expect(find.text('Read as: Leggo un libro'), findsOneWidget);
      expect(ink.calls.last.$2, 'Leggo un ', reason: 'the parts written so far are the context');
      await check(tester);
      expect(_correct(tester), isTrue);
    });

    testWidgets('a missing model shows the download in the pad; then writing works', (tester) async {
      final ink = FakeInkRecognizer(status: InkModelStatus.missing, reading: ['ho']);
      await pumpApp(
        tester,
        store: TestProgressStore(settings: _write),
        overrides: v05Overrides(ink: ink),
        initialLocation: Routes.labPlay(skills: ['passato'], types: [ExerciseType.cloze], length: 1),
      );
      expect(find.byKey(const ValueKey('ink-model')), findsOneWidget);
      expect(find.textContaining('about 20 MB'), findsOneWidget);
      expect(find.byKey(const ValueKey('ink-pad')), findsNothing);
      await tapKey(tester, 'ink-download');
      expect(find.byKey(const ValueKey('ink-pad')), findsOneWidget);
      await write(tester);
      await check(tester);
      expect(_correct(tester), isTrue);
    });

    testWidgets('a language without a model says so; Sarnami uses the Dutch model', (tester) async {
      final ink = FakeInkRecognizer(supportedTags: {'nl'});
      await pumpApp(
        tester,
        store: TestProgressStore(settings: _write),
        overrides: v05Overrides(ink: ink),
        initialLocation: Routes.labPlay(skills: ['passato'], types: [ExerciseType.cloze], length: 1),
      );
      expect(find.textContaining("Handwriting isn't available"), findsOneWidget);
      expect(inkLanguageTags('hns'), ['nl']);
      expect(inkLanguageTags('it'), ['it']);
    });

    testWidgets('"Type instead" switches the exercise to the keyboard', (tester) async {
      final ink = FakeInkRecognizer();
      await pumpApp(
        tester,
        store: TestProgressStore(settings: _write),
        overrides: v05Overrides(ink: ink),
        initialLocation: Routes.labPlay(skills: ['passato'], types: [ExerciseType.cloze], length: 1),
      );
      await tapKey(tester, 'ink-keyboard');
      await typeInto(tester, find.byKey(const ValueKey('ink-typed')), 'ho');
      await check(tester);
      expect(_correct(tester), isTrue);
      expect(ink.calls, isEmpty);
    });

    testWidgets('palm rejection: after a stylus stroke, fingers do not write', (tester) async {
      final ink = FakeInkRecognizer(reading: ['ho']);
      await pumpApp(
        tester,
        store: TestProgressStore(settings: _write),
        overrides: v05Overrides(ink: ink),
        initialLocation: Routes.labPlay(skills: ['passato'], types: [ExerciseType.cloze], length: 1),
      );
      await write(tester, kind: PointerDeviceKind.stylus);
      await write(tester); // a palm
      expect(ink.calls.last.$1, 1);
    });

    testWidgets('writing never scrolls the exercise', (tester) async {
      final ink = FakeInkRecognizer(reading: ['Leggo un libro']);
      await pumpApp(
        tester,
        size: const Size(360, 520),
        store: TestProgressStore(settings: _write),
        overrides: v05Overrides(ink: ink),
        initialLocation: Routes.labPlay(skills: ['present-ere'], types: [ExerciseType.sentenceBuilder], length: 1),
      );
      final pad = find.byKey(const ValueKey('ink-pad'));
      await tester.ensureVisible(pad);
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('exercise-scroll')), matching: find.byType(Scrollable)),
      );
      final before = scroll.position.pixels;
      await tester.dragFrom(tester.getCenter(pad), const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, before);
      expect(ink.calls, isNotEmpty);
    });

    test('combined readings of written parts', () {
      expect(combineSegments([
        ['a', 'b'],
        ['c', 'd'],
      ]), ['a c', 'a d', 'b c', 'b d']);
      expect(combineSegments(const []), isEmpty);
      expect(const InkResult(['x', 'y', 'z', 'w']).toAnswer().candidates, ['y', 'z']);
    });
  });

  group('Onyx pen', () {
    testWidgets('raw drawing opens on the pad; its strokes are recognized; paused under a dialog', (tester) async {
      final ink = FakeInkRecognizer(reading: ['ho']);
      final pen = FakePenSurface();
      await pumpApp(
        tester,
        store: TestProgressStore(settings: _write),
        overrides: v05Overrides(ink: ink, onyx: true, pen: pen),
        initialLocation: Routes.labPlay(skills: ['passato'], types: [ExerciseType.cloze], length: 1),
      );
      await tester.pump();
      expect(pen.log.first, 'open');
      final padRect = tester.getRect(find.byKey(const ValueKey('ink-pad')));
      expect(pen.rect!.overlaps(padRect), isTrue, reason: 'physical = logical at dpr 1');
      // The SDK draws stylus strokes; Flutter ignores the stylus then.
      await write(tester, kind: PointerDeviceKind.stylus);
      expect(ink.calls, isEmpty);
      final c = padRect.center;
      pen.emitStroke([for (var i = 0; i < 6; i++) (c.dx - 30 + i * 10, c.dy, 1000 + i * 10)]);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(ink.calls.single.$1, 1);
      expect(ink.inks.single.single.first.x, closeTo(c.dx - 30 - padRect.left - 1.5, 2), reason: 'pad-local');
      expect(find.text('Read as: ho'), findsOneWidget);
      // Undo drops the SDK's overlay.
      await tapKey(tester, 'ink-undo');
      expect(pen.log, contains('clear'));
      // A dialog over the pad pauses raw drawing.
      await tapKey(tester, 'player-close');
      await tester.pump();
      expect(pen.enabled, isFalse);
      await tapKey(tester, 'exit-cancel');
      await tester.pump();
      expect(pen.enabled, isTrue);
      // Leaving closes it.
      await tester.pumpWidget(const SizedBox());
      expect(pen.log.last, 'close');
    });

    testWidgets('when the SDK fails to open, the pad draws with Flutter', (tester) async {
      final ink = FakeInkRecognizer(reading: ['ho']);
      final pen = FakePenSurface(opens: false);
      await pumpApp(
        tester,
        store: TestProgressStore(settings: _write),
        overrides: v05Overrides(ink: ink, onyx: true, pen: pen),
        initialLocation: Routes.labPlay(skills: ['passato'], types: [ExerciseType.cloze], length: 1),
      );
      await tester.pump();
      expect(pen.log, ['open']);
      await write(tester, kind: PointerDeviceKind.stylus);
      expect(ink.calls.single.$1, 1);
    });
  });

  group('e-ink full refresh (ONYX)', () {
    Future<FakeEinkScreen> play(WidgetTester tester, {required bool onyx, Map<String, String> settings = const {}}) async {
      final eink = FakeEinkScreen();
      await pumpApp(
        tester,
        store: TestProgressStore(settings: settings),
        overrides: [
          if (onyx) deviceInfoProvider.overrideWith((ref) async => onyxDevice),
          if (onyx) einkScreenProvider.overrideWithValue(eink),
        ],
        initialLocation: Routes.labPlay(skills: ['greetings'], types: [ExerciseType.multipleChoice], length: 1),
      );
      await answerCurrent(tester);
      expect(find.byKey(const ValueKey('session-summary')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      return eink;
    }

    testWidgets('after the summary and when leaving, in black & white', (tester) async {
      final eink = await play(tester, onyx: true, settings: {SettingKeys.display: 'bw'});
      expect(eink.refreshes, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 400));
      expect(eink.refreshes, 2);
    });

    testWidgets('off in color by default, on when set; never off ONYX', (tester) async {
      var eink = await play(tester, onyx: true);
      expect(eink.refreshes, 0);
      await tester.pumpWidget(const SizedBox());
      eink = await play(tester, onyx: true, settings: {LearnerSettingKeys.einkFullRefresh: 'true'});
      expect(eink.refreshes, 1);
      await tester.pumpWidget(const SizedBox());
      eink = await play(tester, onyx: false, settings: {SettingKeys.display: 'bw'});
      expect(eink.refreshes, 0);
    });

    testWidgets('Settings: the E-reader section only on ONYX', (tester) async {
      await pumpApp(tester, initialLocation: Routes.settings);
      await scrollToFind(tester, find.byKey(const ValueKey('setting-answer-input')));
      expect(find.byKey(const ValueKey('setting-full-refresh')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      final store = await pumpApp(
        tester,
        store: TestProgressStore(settings: {SettingKeys.display: 'bw'}),
        initialLocation: Routes.settings,
        overrides: v05Overrides(onyx: true, eink: FakeEinkScreen()),
      );
      await scrollToFind(tester, find.byKey(const ValueKey('setting-full-refresh')));
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('setting-full-refresh'))).value, isTrue);
      await tapKey(tester, 'setting-full-refresh');
      expect(store.settings[LearnerSettingKeys.einkFullRefresh], 'false');
      await scrollToFind(tester, find.byKey(const ValueKey('setting-onyx-pen')));
      await tapKey(tester, 'setting-onyx-pen');
      expect(store.settings[LearnerSettingKeys.onyxPen], 'false');
      expect(_container(tester).read(penSurfaceProvider), isNull, reason: 'the real provider honours the switch');
    });
  });

  group('listening', () {
    testWidgets('no voice: listening is off and the lab hides the type', (tester) async {
      await pumpApp(tester, initialLocation: Routes.lab);
      await scrollToFind(tester, find.byKey(const ValueKey('lab-type-transform')));
      expect(find.byKey(const ValueKey('lab-type-transform')), findsOneWidget);
      expect(find.byKey(const ValueKey('lab-type-listen_pick')), findsNothing);
      expect(_container(tester).read(sessionOptionsProvider).listening, isFalse);
    });

    testWidgets('with a voice: the lab offers it; it plays by itself, slower on demand', (tester) async {
      final speaker = FakeSpeaker();
      await pumpApp(tester, overrides: v05Overrides(speaker: speaker), initialLocation: Routes.lab);
      expect(_container(tester).read(sessionOptionsProvider).listening, isTrue);
      await scrollToFind(tester, find.byKey(const ValueKey('lab-type-listen_pick')));
      expect(find.byKey(const ValueKey('lab-type-listen_pick')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await pumpApp(
        tester,
        overrides: v05Overrides(speaker: speaker),
        initialLocation: Routes.labPlay(skills: ['time'], types: [ExerciseType.listenPick], length: 1),
      );
      expect(speaker.spoken.last, ('Ci vediamo domani.', 'it', false));
      // Never shown before checking: only as an option.
      expect(find.byKey(const ValueKey('listen-translation')), findsNothing);
      await tapKey(tester, 'listen-slow');
      expect(speaker.spoken.last.$3, isTrue);
      await tapKey(tester, 'listen-play');
      expect(speaker.spoken.length, 3);
      await tapKey(tester, 'option-0');
      await check(tester);
      expect(_correct(tester), isTrue);
      expect(find.byKey(const ValueKey('listen-translation')), findsOneWidget);
      expect(find.byKey(const ValueKey('listen-answer-sentence')), findsOneWidget);
    });

    testWidgets('the Listening exercises setting switches it off', (tester) async {
      final speaker = FakeSpeaker();
      final store = await pumpApp(tester, overrides: v05Overrides(speaker: speaker), initialLocation: Routes.settings);
      await scrollToFind(tester, find.byKey(const ValueKey('setting-listening')));
      await tapKey(tester, 'setting-listening');
      expect(store.settings[LearnerSettingKeys.listening], 'false');
      expect(_container(tester).read(sessionOptionsProvider).listening, isFalse);
    });

    testWidgets('pronounce buttons: word page, flashcard, word popover; none without a voice', (tester) async {
      final speaker = FakeSpeaker();
      await pumpApp(tester, overrides: v05Overrides(speaker: speaker), initialLocation: Routes.word('it:pane'));
      await tapKey(tester, 'word-pronounce');
      expect(speaker.spoken.last.$1, 'il pane');
      await tester.pumpWidget(const SizedBox());

      await pumpApp(
        tester,
        overrides: v05Overrides(speaker: speaker),
        initialLocation: Routes.labPlay(skills: ['time'], types: [ExerciseType.flashcard], length: 1),
      );
      await tapKey(tester, 'pronounce');
      expect(speaker.spoken.last.$1, 'domani');
      await tester.pumpWidget(const SizedBox());

      await pumpApp(
        tester,
        overrides: v05Overrides(speaker: speaker),
        initialLocation: Routes.labPlay(skills: ['present-ere'], types: [ExerciseType.sentenceBuilder], length: 1),
      );
      await answerCurrentNoContinue(tester);
      await tapKey(tester, 'word-0');
      await tapKey(tester, 'word-popover-pronounce');
      expect(speaker.spoken.last.$1, 'Leggo');
      await tester.pumpWidget(const SizedBox());

      await pumpApp(tester, initialLocation: Routes.word('it:pane'));
      expect(find.byKey(const ValueKey('word-pronounce')), findsNothing);
    });
  });
}
