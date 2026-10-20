// v0.4 extras in black & white (pixel scan) and their layout (no overflow)
// at every e-ink harness size (phones, 6" and 7" e-readers, the Boox Note Air,
// tablet, desktop), plus color, dark mode and text 1.3 at phone and desktop
// sizes (and text 1.5 on phones): the Progress page's stats card and Starred entry, the stats page
// (14 and 30 days, accuracy), the Starred list (and its empty state), the
// word page and popover stars, the feedback panel's Star sheet, and AI
// conversation (the Chat tab, a reply with its correction and translation,
// the offline notice). HTTP is a MockClient.
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/bookmarks.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/bookmarks/bookmarks_ui.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/ai/ai_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bw_helpers.dart';
import 'bw_mode_test.dart' show bwSizes;
import 'fakes/demo_exercises.dart';
import 'helpers.dart';
import 'v04_extras_test.dart' show FakeTutorAi, seededStore, settleAi, tutorOverrides;

typedef Check = Future<void> Function(String what);

/// A word, a sentence and an exercise starred in the demo Italian course.
Future<InMemoryBookmarkRepo> starredRepo() async {
  final repo = InMemoryBookmarkRepo();
  final store = BookmarkStore(repo, clock: () => testNow);
  final course = buildDemoItalian();
  await store.add('it', wordBookmark(course, 'it:mangiare', 'en'));
  await store.add('it', sentenceBookmark(course.sentence('s:demo1')!, 'en'));
  await store.add('it', exerciseBookmark(demoExercises('it', 'en').first));
  return repo;
}

Future<void> walk(WidgetTester tester, Size size, Map<String, String> settings, Check check) async {
  final repo = await starredRepo();
  final marks = bookmarkRepoProvider.overrideWithValue(repo);

  // Progress: the stats card and the Starred entry.
  await pumpApp(tester, size: size, store: await seededStore(settings), initialLocation: Routes.progress, overrides: [marks]);
  for (final key in ['stats-summary', 'open-starred']) {
    await scrollToFind(tester, find.byKey(ValueKey(key)));
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await check('progress: $key');
  }
  await tester.pumpWidget(const SizedBox());

  // The stats page, 14 and 30 days, and the accuracy sections.
  await pumpApp(tester, size: size, store: await seededStore(settings), initialLocation: Routes.stats);
  await check('stats: 14 days');
  await tester.tap(find.text('30 days'));
  await tester.pumpAndSettle();
  await check('stats: 30 days');
  for (final key in ['stats-learned', 'stats-by-type', 'stats-by-kind', 'stats-by-grammar']) {
    await scrollToFind(tester, find.byKey(ValueKey(key)));
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await check('stats: $key');
  }
  await tester.pumpWidget(const SizedBox());

  // Starred: the list (each filter) and the empty state.
  await pumpApp(tester, size: size, store: TestProgressStore(settings: settings), initialLocation: Routes.starred, overrides: [marks]);
  await check('starred list');
  await tapKey(tester, 'starred-filter-exercise');
  await check('starred list: exercises');
  await tester.pumpWidget(const SizedBox());
  await pumpApp(tester, size: size, store: TestProgressStore(settings: settings), initialLocation: Routes.starred);
  await check('starred: empty');
  await tester.pumpWidget(const SizedBox());

  // The word page's stars (one starred), and the popover's.
  await pumpApp(
    tester,
    size: size,
    store: TestProgressStore(settings: settings),
    initialLocation: Routes.word('it:mangiare'),
    overrides: [marks],
  );
  await check('word page with stars');
  await tapIt(tester, find.byKey(const ValueKey('word-s:demo1-0')));
  expect(find.byKey(const ValueKey('word-popover-star')), findsOneWidget);
  await check('word popover with a star');
  await tester.pumpWidget(const SizedBox());

  // The feedback panel's Star and its sheet.
  final skills = buildDemoItalian().skills.map((s) => s.id).toList();
  await pumpApp(
    tester,
    size: size,
    store: TestProgressStore(settings: settings),
    initialLocation: Routes.labPlay(skills: skills, types: [ExerciseType.cloze], length: 1),
    overrides: [marks],
  );
  await answerCurrentNoContinue(tester, wrong: true);
  await scrollToFind(tester, find.byKey(const ValueKey('star-button')));
  await check('feedback panel with Star');
  await tapKey(tester, 'star-button');
  await tapKey(tester, 'star-toggle-word');
  await check('star sheet');
  await tester.pumpWidget(const SizedBox());

  // AI conversation.
  final ai = FakeTutorAi();
  final aiSettings = {...settings, AiSettingKeys.provider: 'anthropic'};
  await pumpApp(tester, size: size, store: TestProgressStore(settings: aiSettings), initialLocation: Routes.chats, overrides: tutorOverrides(ai));
  await check('chat tab');
  await tester.tap(find.byKey(const ValueKey('chat-start')));
  await settleAi(tester);
  await tapKey(tester, 'chat-translate-0');
  await scrollToFind(tester, find.byKey(const ValueKey('chat-correction-0')));
  await check('chat: reply with correction and translation');
  await tester.enterText(find.byKey(const ValueKey('chat-input')), 'Sì, mi piace');
  ai.offline = true;
  await tester.tap(find.byKey(const ValueKey('chat-send')));
  await settleAi(tester);
  expect(find.byKey(const ValueKey('chat-error-network')), findsOneWidget);
  await check('chat: learner message and the offline notice');
  await tester.pumpWidget(const SizedBox());
}

void main() {
  for (final entry in bwSizes.entries) {
    testWidgets('black & white ${entry.key}', (tester) async {
      await walk(tester, entry.value, {SettingKeys.display: 'bw'}, (what) async {
        await expectGrayscale(tester, what);
        expect(tester.takeException(), isNull, reason: what);
      });
    });
  }
  for (final size in const [Size(320, 568), Size(360, 640), Size(1280, 800)]) {
    testWidgets('color, dark, text 1.3 at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await walk(tester, size, {SettingKeys.themeMode: 'dark'}, (what) async {
        expect(tester.takeException(), isNull, reason: what);
      });
    });
    if (size.width < 400) {
      testWidgets('color, text 1.5 at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await walk(tester, size, const {}, (what) async {
          expect(tester.takeException(), isNull, reason: what);
        });
      });
    }
    testWidgets('color, light at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await walk(tester, size, const {}, (what) async {
        expect(tester.takeException(), isNull, reason: what);
      });
    });
  }
}
