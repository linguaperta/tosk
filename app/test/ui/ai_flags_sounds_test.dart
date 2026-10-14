// v0.3 answer-panel features in the app: "Explain answer with AI" (only with
// a configured provider and key), flags (Report → sheet → Submit / Confer
// with AI → Settings → Feedback & flags → export), the AI settings section,
// the mistakes list's cached explanations, and sounds. Every new widget is
// also checked for layout overflow at phone sizes and for colored pixels in
// black & white mode. HTTP is a MockClient; no real API is called.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:tosk/ai/ai_config.dart';
import 'package:tosk/ai/secret_store.dart';
import 'package:tosk/audio/sound_service.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/feedback_store.dart';
import 'package:tosk/feedback/flags_export.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/feedback/flags_screen.dart';
import 'package:tosk/ui/map/map_screen.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../ai/ai_fixtures.dart' show anthropicStream, fakeKey;
import '../audio/fake_audio.dart';
import '../feedback/feedback_fixtures.dart' show sampleFlag;
import 'bw_helpers.dart';
import 'helpers.dart';

const _lab = '/play/lab?skills=present-are&types=conj_pick&length=1';
const _bw = {SettingKeys.display: 'bw'};
const _ai = {AiSettingKeys.provider: 'anthropic'};

/// A fake Anthropic API: explanations, flag verdicts, or an error status.
class FakeAi {
  int requests = 0;
  int status = 200;
  bool offline = false;
  final List<Map<String, Object?>> bodies = [];

  late final MockClient client = MockClient((req) async {
    requests++;
    if (offline) throw http.ClientException('Failed host lookup');
    final body = jsonDecode(req.body) as Map<String, Object?>;
    bodies.add(body);
    if (status != 200) {
      return http.Response('{"type":"error","error":{"type":"authentication_error","message":"invalid"}}', status);
    }
    final system = body['system']! as String;
    if (system.contains('VERDICT')) {
      return http.Response(
        anthropicStream(['VERDICT: exercise_correct\n', 'For **noi** the ending is **-iamo**: ', 'mangiamo.']),
        200,
      );
    }
    return http.Response(anthropicStream(['For **noi**, -are verbs ', 'take **-iamo**: mangiamo.']), 200);
  });
}

List<Override> aiOverrides(FakeAi ai, {FeedbackStore? feedback, FakeAudioBackend? audio}) => [
  secretStoreProvider.overrideWithValue(MemorySecretStore({AiSettingKeys.apiKeySecret: fakeKey})),
  httpClientProvider.overrideWithValue(ai.client),
  if (feedback != null) feedbackStoreProvider.overrideWithValue(feedback),
  if (audio != null) audioBackendProvider.overrideWithValue(audio),
];

/// Lets the mock AI stream finish. Under the test clock a stream's done event
/// needs a turn of the real event loop, so alternate real waits and pumps.
Future<void> settleAi(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Taps [key] (which starts an AI request) and lets the reply finish.
Future<void> aiTap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await settleAi(tester);
}

/// Scrolls the (lazy) settings list until [key] is built and visible.
Future<void> scrollSettingsTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    200,
    scrollable: find.descendant(of: find.byKey(const ValueKey('settings-list')), matching: find.byType(Scrollable)).first,
  );
  await tester.pumpAndSettle();
}

Future<void> answerConjPick(WidgetTester tester, {required bool wrong}) async {
  final ex = currentExercise(tester) as ConjPickExercise;
  await tapKey(tester, 'ending-${wrong ? (ex.correctIndex + 1) % ex.endings.length : ex.correctIndex}');
  await tapKey(tester, 'check-button');
}

void main() {
  group('Explain answer with AI', () {
    testWidgets('does not exist without a configured provider and key', (tester) async {
      await pumpApp(tester, initialLocation: _lab, store: TestProgressStore(settings: _ai)); // no key
      await answerConjPick(tester, wrong: true);
      expect(find.byKey(const ValueKey('ai-explain-button')), findsNothing);
      expect(find.byKey(const ValueKey('why-button')), findsNothing);
      expect(find.byKey(const ValueKey('flag-button')), findsOneWidget);
    });

    testWidgets('wrong answer: streams the explanation, then serves it from the cache', (tester) async {
      final ai = FakeAi();
      final feedback = InMemoryFeedbackStore();
      await pumpApp(
        tester,
        initialLocation: _lab,
        store: TestProgressStore(settings: _ai),
        overrides: aiOverrides(ai, feedback: feedback),
      );
      await answerConjPick(tester, wrong: true);
      await aiTap(tester, 'ai-explain-button');
      expect(find.byKey(const ValueKey('ai-explanation-text')), findsOneWidget);
      expect(find.textContaining('take', findRichText: true), findsWidgets);
      expect(ai.requests, 1);
      final user = ((ai.bodies.single['messages']! as List).single as Map)['content'] as String;
      expect(user, contains('marked wrong'));
      expect(user, contains('Grammar note'));

      // Close and ask again: no second request.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await aiTap(tester, 'ai-explain-button');
      expect(find.byKey(const ValueKey('ai-explanation-text')), findsOneWidget);
      expect(ai.requests, 1);
    });

    testWidgets('right answers can be explained too', (tester) async {
      final ai = FakeAi();
      await pumpApp(tester, initialLocation: _lab, store: TestProgressStore(settings: _ai), overrides: aiOverrides(ai));
      await answerConjPick(tester, wrong: false);
      expect(find.text('Correct!'), findsOneWidget);
      await aiTap(tester, 'ai-explain-button');
      final user = ((ai.bodies.single['messages']! as List).single as Map)['content'] as String;
      expect(user, contains('accepted as correct'));
    });

    testWidgets('offline: shows the bundled grammar note instead', (tester) async {
      final ai = FakeAi()..offline = true;
      await pumpApp(tester, initialLocation: _lab, store: TestProgressStore(settings: _ai), overrides: aiOverrides(ai));
      await answerConjPick(tester, wrong: true);
      await aiTap(tester, 'ai-explain-button');
      expect(find.byKey(const ValueKey('ai-explanation-error')), findsOneWidget);
      expect(find.textContaining("Couldn't reach"), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-explanation-note')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-explanation-retry')), findsOneWidget);
    });

    testWidgets('401: says to check the API key', (tester) async {
      final ai = FakeAi()..status = 401;
      await pumpApp(tester, initialLocation: _lab, store: TestProgressStore(settings: _ai), overrides: aiOverrides(ai));
      await answerConjPick(tester, wrong: true);
      await aiTap(tester, 'ai-explain-button');
      expect(find.textContaining('check your API key'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-explanation-retry')), findsNothing);
    });
  });

  group('flags', () {
    testWidgets('Report → reasons + comment → Submit saves a full flag; the button shows "Reported"', (tester) async {
      final feedback = InMemoryFeedbackStore();
      await pumpApp(tester, initialLocation: _lab, overrides: [feedbackStoreProvider.overrideWithValue(feedback)]);
      final ex = currentExercise(tester) as ConjPickExercise;
      await answerConjPick(tester, wrong: true);
      await tapKey(tester, 'flag-button');
      expect(find.byKey(const ValueKey('flag-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('flag-confer')), findsNothing, reason: 'AI not configured');
      final submit = find.byKey(const ValueKey('flag-submit'));
      expect(tester.widget<ButtonStyleButton>(submit).onPressed, isNull, reason: 'nothing chosen yet');

      await tapKey(tester, 'flag-reason-multiple_answers');
      await tester.enterText(find.byKey(const ValueKey('flag-comment')), 'mangiate should work too');
      await tester.pumpAndSettle();
      await tapIt(tester, submit);
      expect(find.byKey(const ValueKey('flag-sheet')), findsNothing);
      expect(find.text('Reported'), findsOneWidget);

      final flag = (await feedback.flags()).single;
      expect(flag.reasons, [FlagReason.multipleAnswers]);
      expect(flag.comment, 'mangiate should work too');
      expect(flag.correct, isFalse);
      expect(flag.expected, ex.fullForm);
      expect(flag.exerciseType, 'conj_pick');
      expect(flag.exercise['endings'], ex.endings);
      expect(flag.exercise['correct_index'], ex.correctIndex);
      expect(flag.appVersion, isNotEmpty);
      expect(flag.aiVerdict, isNull);
    });

    testWidgets('Confer with AI shows the verdict and stores it with the flag', (tester) async {
      final ai = FakeAi();
      final feedback = InMemoryFeedbackStore();
      await pumpApp(
        tester,
        initialLocation: _lab,
        store: TestProgressStore(settings: _ai),
        overrides: aiOverrides(ai, feedback: feedback),
      );
      await answerConjPick(tester, wrong: true);
      await tapKey(tester, 'flag-button');
      await tapKey(tester, 'flag-reason-answer_wrong');
      await aiTap(tester, 'flag-confer');
      expect(find.byKey(const ValueKey('flag-verdict-exercise_correct')), findsOneWidget);
      expect(find.text('AI: the exercise is correct'), findsOneWidget);
      final user = ((ai.bodies.single['messages']! as List).single as Map)['content'] as String;
      expect(user, contains('The answer is wrong'));
      expect(user, contains('Full exercise data'));

      await tapKey(tester, 'flag-submit');
      final flag = (await feedback.flags()).single;
      expect(flag.aiVerdict, FlagVerdict.exerciseCorrect);
      expect(flag.aiReasoning, contains('-iamo'));
    });

    testWidgets('Discard after the verdict saves nothing', (tester) async {
      final ai = FakeAi();
      final feedback = InMemoryFeedbackStore();
      await pumpApp(
        tester,
        initialLocation: _lab,
        store: TestProgressStore(settings: _ai),
        overrides: aiOverrides(ai, feedback: feedback),
      );
      await answerConjPick(tester, wrong: false);
      await tapKey(tester, 'flag-button');
      await tapKey(tester, 'flag-reason-unclear');
      await aiTap(tester, 'flag-confer');
      await tapKey(tester, 'flag-discard');
      expect(await feedback.flags(), isEmpty);
      expect(find.text('Report'), findsOneWidget);
    });

    testWidgets('Settings → Feedback & flags: list, export as JSON Lines, delete', (tester) async {
      final feedback = InMemoryFeedbackStore();
      await feedback.saveFlag(sampleFlag(id: 'a', at: DateTime.utc(2026, 10, 1)));
      await feedback.saveFlag(sampleFlag(id: 'b', at: DateTime.utc(2026, 10, 2), verdict: FlagVerdict.ambiguous));
      String? savedName;
      Uint8List? savedBytes;
      await pumpApp(
        tester,
        initialLocation: Routes.settings,
        overrides: [
          feedbackStoreProvider.overrideWithValue(feedback),
          flagsSaverProvider.overrideWithValue((name, bytes) async {
            savedName = name;
            savedBytes = bytes;
            return Uri.parse('content://downloads/$name');
          }),
        ],
      );
      await scrollSettingsTo(tester, 'open-flags');
      expect(find.text('2 flags on this device · export'), findsOneWidget);
      await tapKey(tester, 'open-flags');
      expect(find.byKey(const ValueKey('flag-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('flag-b')), findsOneWidget);
      expect(find.text('The exercise is ambiguous'), findsOneWidget);

      await tapKey(tester, 'flags-export');
      expect(savedName, flagsFileName(testNow));
      final lines = const LineSplitter().convert(utf8.decode(savedBytes!));
      expect(lines.map((l) => (jsonDecode(l) as Map)['id']), ['a', 'b']);
      expect(find.text('Exported 2 flags'), findsOneWidget);

      await tapKey(tester, 'flag-delete-a');
      await tapKey(tester, 'flag-delete-confirm');
      expect(find.byKey(const ValueKey('flag-a')), findsNothing);
      expect((await feedback.flags()).map((f) => f.id), ['b']);
    });

    testWidgets('no flags: an empty state and no export button', (tester) async {
      await pumpApp(tester, initialLocation: Routes.flags);
      expect(find.byKey(const ValueKey('flags-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('flags-export')), findsNothing);
    });
  });

  group('AI settings', () {
    testWidgets('provider, key in secure storage (not in settings), model, test connection', (tester) async {
      final ai = FakeAi();
      final secrets = MemorySecretStore();
      final store = await pumpApp(
        tester,
        initialLocation: Routes.settings,
        overrides: [secretStoreProvider.overrideWithValue(secrets), httpClientProvider.overrideWithValue(ai.client)],
      );
      await scrollSettingsTo(tester, 'ai-provider');
      final provider = find.byKey(const ValueKey('ai-provider'));
      expect(find.byKey(const ValueKey('ai-api-key')), findsNothing);
      await tester.tap(provider);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anthropic Claude').last);
      await tester.pumpAndSettle();
      expect(store.settings[AiSettingKeys.provider], 'anthropic');
      expect(find.text('Add your API key to turn AI explanations on.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('ai-api-key')), fakeKey);
      await scrollSettingsTo(tester, 'ai-test');
      await aiTap(tester, 'ai-test');
      expect(find.byKey(const ValueKey('ai-test-ok')), findsOneWidget);
      expect(find.text('Connected to claude-haiku-5-5.'), findsOneWidget);
      expect(await secrets.read(AiSettingKeys.apiKeySecret), fakeKey);
      expect(store.settings.values, isNot(contains(fakeKey)));
      expect(ai.bodies.single['model'], 'claude-haiku-5-5');
      expect(find.textContaining('On: "Explain answer with AI"'), findsOneWidget);

      await tapKey(tester, 'ai-remove-key');
      expect(await secrets.read(AiSettingKeys.apiKeySecret), isNull);
    });

    testWidgets('test connection reports a rejected key', (tester) async {
      final ai = FakeAi()..status = 401;
      await pumpApp(
        tester,
        initialLocation: Routes.settings,
        store: TestProgressStore(settings: _ai),
        overrides: aiOverrides(ai),
      );
      await scrollSettingsTo(tester, 'ai-test');
      await aiTap(tester, 'ai-test');
      expect(find.byKey(const ValueKey('ai-test-failed')), findsOneWidget);
      expect(find.textContaining('check your API key'), findsOneWidget);
    });
  });

  group('mistakes list', () {
    testWidgets('a cached explanation shows without AI (offline, no key)', (tester) async {
      final feedback = InMemoryFeedbackStore();
      final store = await pumpApp(
        tester,
        initialLocation: _lab,
        overrides: [feedbackStoreProvider.overrideWithValue(feedback)],
      );
      await answerCurrent(tester, wrong: true);
      await playToSummary(tester);
      await tapKey(tester, 'summary-done');
      final m = (await store.mistakes()).single;
      final ctx = MistakeContext(
        courseId: 'it',
        facetId: m.facetId,
        exerciseType: ExerciseType.tryParse(m.exerciseType)!,
        prompt: m.prompt,
        expected: m.expected,
        given: m.given,
        sourceLang: 'en',
        targetLang: 'it',
      );
      await feedback.saveExplanation(
        CachedExplanation(fingerprint: ctx.fingerprint, given: m.given, lang: 'en', text: 'Cached why.', createdAt: testNow),
      );
      unawaited(GoRouter.of(tester.element(find.byType(MapScreen))).push(Routes.mistakes));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('mistake-why-${m.facetId}')), findsNothing, reason: 'AI not configured');
      await tapKey(tester, 'mistake-explanation-${m.facetId}');
      expect(find.text('Cached why.'), findsOneWidget);
    });

    testWidgets('with AI configured the list offers "Explain with AI"', (tester) async {
      final ai = FakeAi();
      await pumpApp(tester, initialLocation: _lab, store: TestProgressStore(settings: _ai), overrides: aiOverrides(ai));
      await answerCurrent(tester, wrong: true);
      await playToSummary(tester);
      await tapKey(tester, 'summary-done');
      unawaited(GoRouter.of(tester.element(find.byType(MapScreen))).push(Routes.mistakes));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explain with AI'));
      await settleAi(tester);
      expect(find.byKey(const ValueKey('ai-explanation-text')), findsOneWidget);
      expect(ai.requests, 1);
    });
  });

  group('sounds', () {
    testWidgets('select tick on taps, correct/wrong on check, complete at the end', (tester) async {
      final audio = FakeAudioBackend();
      await pumpApp(tester, initialLocation: _lab, overrides: [audioBackendProvider.overrideWithValue(audio)]);
      expect(audio.preloaded, Sfx.values.toSet());
      await answerConjPick(tester, wrong: true);
      expect(audio.played, [Sfx.select, Sfx.wrong]);
      await tapKey(tester, 'continue-button');
      await playToSummary(tester);
      expect(audio.played, containsAllInOrder([Sfx.select, Sfx.wrong, Sfx.select, Sfx.correct, Sfx.complete]));
      expect(audio.played.where((s) => s == Sfx.complete), hasLength(1));
    });

    testWidgets('match pairs cards tick too', (tester) async {
      final audio = FakeAudioBackend();
      await pumpApp(
        tester,
        initialLocation: '/play/lab?skills=greetings&types=match_pairs&length=1',
        overrides: [audioBackendProvider.overrideWithValue(audio)],
      );
      await tapKey(tester, 'match-left-0');
      expect(audio.played, [Sfx.select]);
    });

    testWidgets('the "Sound effects" switch persists', (tester) async {
      final audio = FakeAudioBackend();
      final store = await pumpApp(
        tester,
        initialLocation: Routes.settings,
        overrides: [audioBackendProvider.overrideWithValue(audio)],
      );
      await scrollSettingsTo(tester, 'sound-effects');
      await tapKey(tester, 'sound-effects');
      expect(store.settings[SettingKeys.soundEffects], 'false');
    });

    testWidgets('"Sound effects" off: silent in the player', (tester) async {
      final audio = FakeAudioBackend();
      await pumpApp(
        tester,
        initialLocation: _lab,
        store: TestProgressStore(settings: {SettingKeys.soundEffects: 'false'}),
        overrides: [audioBackendProvider.overrideWithValue(audio)],
      );
      await answerConjPick(tester, wrong: true);
      expect(audio.played, isEmpty);
    });

    testWidgets('reduce motion does not mute sounds', (tester) async {
      final audio = FakeAudioBackend();
      await pumpApp(
        tester,
        initialLocation: _lab,
        store: TestProgressStore(settings: {SettingKeys.reduceMotion: 'true'}),
        overrides: [audioBackendProvider.overrideWithValue(audio)],
      );
      await answerConjPick(tester, wrong: false);
      expect(audio.played, [Sfx.select, Sfx.correct]);
    });
  });

  // Layout and black & white for every new widget.
  const sizes = {'small phone 320x568': Size(320, 568), 'phone 360x640': Size(360, 640), 'desktop': Size(1280, 800)};
  for (final bw in [false, true]) {
    for (final e in sizes.entries) {
      final label = '${bw ? 'black & white' : 'color'} ${e.key}';
      testWidgets('$label: feedback actions, AI sheet, flag sheet with verdict', (tester) async {
        final ai = FakeAi();
        await pumpApp(
          tester,
          size: e.value,
          initialLocation: _lab,
          store: TestProgressStore(settings: {..._ai, if (bw) ..._bw}),
          overrides: aiOverrides(ai),
        );
        await answerConjPick(tester, wrong: true);
        expect(find.byKey(const ValueKey('ai-explain-button')), findsOneWidget);
        if (bw) await expectGrayscale(tester, 'feedback with AI + Report');
        await aiTap(tester, 'ai-explain-button');
        if (bw) await expectGrayscale(tester, 'AI sheet');
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        await tapKey(tester, 'flag-button');
        await tapKey(tester, 'flag-reason-translation_wrong');
        await aiTap(tester, 'flag-confer');
        if (bw) await expectGrayscale(tester, 'flag sheet with verdict');
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'flag-submit');
        expect(find.text('Reported'), findsOneWidget);
        if (bw) await expectGrayscale(tester, 'feedback: Reported');
        expect(tester.takeException(), isNull);
      });

      testWidgets('$label: AI sheet offline (note fallback)', (tester) async {
        final ai = FakeAi()..offline = true;
        await pumpApp(
          tester,
          size: e.value,
          initialLocation: _lab,
          store: TestProgressStore(settings: {..._ai, if (bw) ..._bw}),
          overrides: aiOverrides(ai),
        );
        await answerConjPick(tester, wrong: true);
        await aiTap(tester, 'ai-explain-button');
        expect(find.byKey(const ValueKey('ai-explanation-note')), findsOneWidget);
        if (bw) await expectGrayscale(tester, 'AI sheet offline');
        expect(tester.takeException(), isNull);
      });

      testWidgets('$label: settings AI section and flags screen', (tester) async {
        final feedback = InMemoryFeedbackStore();
        await feedback.saveFlag(sampleFlag(id: 'a', verdict: FlagVerdict.exerciseWrong));
        await pumpApp(
          tester,
          size: e.value,
          initialLocation: Routes.settings,
          store: TestProgressStore(settings: {..._ai, if (bw) ..._bw}),
          overrides: aiOverrides(FakeAi(), feedback: feedback),
        );
        await scrollSettingsTo(tester, 'ai-test');
      await aiTap(tester, 'ai-test');
        if (bw) await expectGrayscale(tester, 'settings: AI section');
        await scrollSettingsTo(tester, 'open-flags');
        if (bw) await expectGrayscale(tester, 'settings: feedback & flags');
        await tapKey(tester, 'open-flags');
        if (bw) await expectGrayscale(tester, 'flags screen');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
