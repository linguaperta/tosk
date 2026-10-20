// "No Italian voice": the one-time notice (snack bar, Android only) and the
// hint in Settings → Challenge, in color and black & white; a listening
// exercise is skipped once the voice turns out not to be installed.
import 'package:tosk/core/core.dart';
import 'package:tosk/speech/speaker.dart';
import 'package:tosk/speech/speech_providers.dart';
import 'package:tosk/ui/lesson/exercises/exercise_view.dart';
import 'package:tosk/ui/lesson/player_screen.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'bw_helpers.dart';
import 'fakes/v05_fakes.dart';
import 'helpers.dart';

List<Override> _noVoice({bool android = true, VoiceStatus status = VoiceStatus.notInstalled}) => [
  speakerProvider.overrideWithValue(FakeSpeaker(languages: const {}, statuses: {'it': status})),
  isAndroidProvider.overrideWithValue(android),
];

void main() {
  testWidgets('voice not installed (Android): the notice once, then never again for that language', (tester) async {
    final store = TestProgressStore();
    await pumpApp(tester, store: store, overrides: _noVoice());
    expect(find.byKey(const ValueKey('voice-notice')), findsOneWidget);
    expect(find.textContaining('Install an Italian voice in Android text-to-speech settings'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Settings'), findsOneWidget);
    expect(await store.getSetting(SettingKeys.voiceNoticeShown), 'it');

    // A restart: no second notice.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, store: store, overrides: _noVoice());
    expect(find.byKey(const ValueKey('voice-notice')), findsNothing);
  });

  testWidgets('no notice with a voice, off Android, or for Sarnami-like codes', (tester) async {
    await pumpApp(
      tester,
      overrides: [
        isAndroidProvider.overrideWithValue(true),
        ...v05Overrides(speaker: FakeSpeaker()),
      ],
    );
    expect(find.byKey(const ValueKey('voice-notice')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, overrides: _noVoice(android: false));
    expect(find.byKey(const ValueKey('voice-notice')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, overrides: _noVoice(status: VoiceStatus.unavailable));
    expect(find.byKey(const ValueKey('voice-notice')), findsNothing);
  });

  for (final bw in [false, true]) {
    for (final size in const [Size(320, 568), Size(360, 640), Size(1280, 800)]) {
      testWidgets(
        'notice and Settings hint, ${bw ? 'black & white' : 'color'} ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final settings = bw ? {SettingKeys.display: 'bw'} : const <String, String>{};
          await pumpApp(
            tester,
            size: size,
            store: TestProgressStore(settings: settings),
            overrides: _noVoice(),
          );
          expect(find.byKey(const ValueKey('voice-notice')), findsOneWidget);
          if (bw) await expectGrayscale(tester, 'voice notice');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());

          await pumpApp(
            tester,
            size: size,
            store: TestProgressStore(settings: {...settings, SettingKeys.voiceNoticeShown: 'it'}),
            overrides: _noVoice(status: VoiceStatus.missing),
            initialLocation: Routes.settings,
          );
          final tile = find.byKey(const ValueKey('voice-notice-tile'));
          await scrollToFind(tester, tile);
          expect(tile, findsOneWidget);
          expect(find.text('No Italian voice'), findsOneWidget);
          expect(find.byKey(const ValueKey('setting-listening')), findsNothing);
          expect(tester.getSize(find.byKey(const ValueKey('voice-notice-open'))).height, greaterThanOrEqualTo(48));
          if (bw) await expectGrayscale(tester, 'settings voice hint');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('a voice found not installed mid-session: its listening exercises are skipped', (tester) async {
    Future<Set<ExerciseType>> play(VoiceStatus? status) async {
      final speaker = status == null ? FakeSpeaker() : FakeSpeaker(languages: const {}, statuses: {'it': status});
      await pumpApp(
        tester,
        store: TestProgressStore(settings: {SettingKeys.voiceNoticeShown: 'it'}),
        overrides: [speakerProvider.overrideWithValue(speaker), isAndroidProvider.overrideWithValue(true)],
        initialLocation: Routes.labPlay(
          skills: const ['time'],
          types: const [ExerciseType.listenPick, ExerciseType.multipleChoice],
          length: 6,
        ),
      );
      expect(find.byType(PlayerScreen), findsOneWidget);
      final seen = <ExerciseType>{};
      for (var i = 0; i < 12 && find.byType(ExerciseView).evaluate().isNotEmpty; i++) {
        seen.add(currentExercise(tester).type);
        await answerCurrent(tester);
      }
      await tester.pumpWidget(const SizedBox());
      return seen;
    }

    // With the voice, the lab serves listening exercises ...
    expect(await play(null), contains(ExerciseType.listenPick));
    // ... and none once the voice is known not to be installed.
    final without = await play(VoiceStatus.notInstalled);
    expect(without, isNot(contains(ExerciseType.listenPick)));
    expect(without, contains(ExerciseType.multipleChoice));
  });
}
