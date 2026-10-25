// Reading mode, "my words" and read aloud in the app, on the bundled Italian
// pack: Practice → Read (paste, a .txt file, recent texts with delete and
// undo), the reader (known share, unknown words underlined, the word popover
// with the grammar of the form, a word not in the course, "Add to my words"
// prefilled, highlight known), My words (add, validate, edit, delete and
// undo, practise), read aloud in the reader and in the story reader with a
// fake speaker (play, pause, the frame, from a sentence, slow, stop on
// leaving, hidden without a voice), and every new screen in black & white
// (pixel scan) and without overflow at the phone, e-reader, Boox and desktop
// sizes.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_loader.dart';
import 'package:tosk/data/progress/user_words.dart';
import 'package:tosk/data/sync/progress_backup.dart' show isLocalOnlySetting;
import 'package:tosk/engine/engine.dart' show FocusPresets;
import 'package:tosk/providers.dart';
import 'package:tosk/speech/speaker.dart';
import 'package:tosk/speech/speech_providers.dart';
import 'package:tosk/ui/lesson/exercises/exercise_view.dart';
import 'package:tosk/ui/reading/reading_home.dart';
import 'package:tosk/ui/reading/reading_providers.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

import '../fixtures/story_course.dart';
import '../fixtures/topic_course.dart' show TopicCourseCatalog;
import 'bw_helpers.dart';
import 'bw_mode_test.dart' show bwSizes;
import 'helpers.dart';
import 'reading_helpers.dart';
import 'stories_test.dart' show practiceUnit;

const kText =
    'Il commissario arrivò in questura alle otto. Sul tavolo c\'era una lettera.\n'
    '\n'
    'Poi chiamò il suo amico, che rispose subito.';

CourseData? _it;
CourseData get it => _it ??= () {
  final db = sqlite3.open('assets/courses/it.sqlite', mode: OpenMode.readOnly);
  try {
    return loadCourseFromSqlite(db);
  } finally {
    db.close();
  }
}();

/// A learner who knows `il`, `in`, `alle` and `otto` (one reviewed facet each).
Future<TestProgressStore> learnerStore([Map<String, String> settings = const {}]) async {
  final store = TestProgressStore(settings: {SettingKeys.coursesAdded: 'it', ...settings});
  var n = 0;
  for (final id in ['it:il', 'it:in', 'it:otto', 'it:commissario']) {
    if (it.item(id) == null) continue;
    await store.record(
      ReviewEvent(
        id: 'k${n++}',
        facetId: '$id#rec',
        at: testNow.subtract(const Duration(days: 1)),
        rating: Rating.good,
        exerciseType: 'flashcard',
        inputMode: InputMode.self,
        responseMs: 1000,
        correct: true,
      ),
    );
  }
  return store;
}

Future<(TestProgressStore, InMemoryUserWordRepo)> pumpReader(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  Map<String, String> settings = const {},
  String location = Routes.read,
  Speaker? speaker,
  InMemoryUserWordRepo? words,
  bool engine = false,
  List<Override> overrides = const [],
}) async {
  final store = await learnerStore(settings);
  final repo = words ?? InMemoryUserWordRepo();
  await pumpApp(
    tester,
    size: size,
    store: store,
    engine: engine,
    initialLocation: location,
    overrides: [
      courseCatalogProvider.overrideWithValue(TopicCourseCatalog(it)),
      userWordRepoProvider.overrideWithValue(repo),
      // rootBundle caches the asset's future in the first test's zone, where a
      // later test can't await it: the engine's defaults are the same presets.
      focusPresetsProvider.overrideWith((ref) async => FocusPresets.defaults),
      if (speaker != null) speakerProvider.overrideWithValue(speaker),
      ...overrides,
    ],
  );
  return (store, repo);
}

Future<void> openText(WidgetTester tester, [String text = kText]) async {
  await scrollToFind(tester, find.byKey(const ValueKey('reading-input')));
  await tester.enterText(find.byKey(const ValueKey('reading-input')), text);
  await tester.pumpAndSettle();
  await tapKey(tester, 'reading-read');
}

Future<InMemoryUserWordRepo> someWords() async {
  final repo = InMemoryUserWordRepo();
  final s = UserWordStore(repo, clock: () => testNow);
  await s.add('it', word: 'questura', translation: 'police headquarters', pos: 'noun', example: 'Arrivò in questura.');
  await s.add('it', word: 'firma', translation: 'signature', pos: 'noun');
  await s.add('it', word: 'qwertina', translation: 'a made-up thing');
  await s.add('it', word: 'indagare', translation: 'to investigate', pos: 'verb');
  return repo;
}

/// The Read tab's "My words" entry is below the text field (a drag on the
/// field would scroll the field, not the list).
Future<void> openMyWordsFromRead(WidgetTester tester) async {
  final list = find.descendant(of: find.byKey(const ValueKey('reading-home')), matching: find.byType(Scrollable)).first;
  final pos = tester.state<ScrollableState>(list).position;
  pos.jumpTo(pos.maxScrollExtent);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-my-words')));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) {
  final w = tester.widget(find.byKey(ValueKey(key)));
  return switch (w) {
    Text(:final data?) => data,
    Text(:final textSpan?) => textSpan.toPlainText(),
    _ => throw StateError('not a text: $w'),
  };
}

void main() {
  group('Read tab', () {
    testWidgets('a pasted text opens in the reader, is kept as a recent text, deletes with undo', (tester) async {
      final (store, _) = await pumpReader(tester);
      expect(find.byKey(const ValueKey('practice-tab-read')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('reading-read'))).onPressed, isNull);
      await openText(tester);
      expect(find.byKey(const ValueKey('reading-text')), findsOneWidget);
      expect(_text(tester, 'reading-known'), matches(RegExp(r'^\d+% of words known$')));
      // Back on the tab: the text is listed with its title, the field is empty.
      await tapKey(tester, 'reading-back');
      final saved = await SavedTextStore(store).list('it');
      expect(saved.single.title, 'Il commissario arrivò in questura alle otto. Sul tavolo…');
      expect(find.text(saved.single.title), findsOneWidget);
      expect(find.textContaining('20 words'), findsOneWidget);
      // Reading it again opens the same entry.
      await openText(tester);
      await tapKey(tester, 'reading-back');
      expect((await SavedTextStore(store).list('it')), hasLength(1));
      // Delete, then undo.
      await tapKey(tester, 'reading-delete-${saved.single.id}');
      expect(find.text(saved.single.title), findsNothing);
      expect(await store.getSetting(SavedTextStore.textKey('it', saved.single.id)), isNull);
      await tester.tap(find.byKey(const ValueKey('reading-undo')));
      await tester.pumpAndSettle();
      expect(find.text(saved.single.title), findsOneWidget);
      expect(await store.getSetting(SavedTextStore.textKey('it', saved.single.id)), kText);
    });

    testWidgets('paste from the clipboard and open a .txt file', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': 'Ciao, come stai?'};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpReader(
        tester,
        overrides: [readingFilePickerProvider.overrideWithValue(() async => 'Buongiorno!\nCome va?')],
      );
      await tapKey(tester, 'reading-paste');
      expect(find.text('Ciao, come stai?'), findsOneWidget);
      await tapKey(tester, 'reading-open-file');
      expect(find.text('Buongiorno!\nCome va?'), findsOneWidget);
      await tapKey(tester, 'reading-read');
      expect(find.byKey(const ValueKey('reading-p-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('reading-p-1')), findsOneWidget);
    });

    testWidgets('saved texts stay local: never synced, never in the backup', (tester) async {
      final (store, _) = await pumpReader(tester);
      await openText(tester);
      final keys = (await store.allSettings()).keys.where((k) => k.startsWith('reading.')).toList();
      expect(keys, isNotEmpty);
      for (final k in keys) {
        expect(isLocalOnlySetting(k), isTrue, reason: k);
      }
    });
  });

  group('reader', () {
    testWidgets('the known share, unknown words underlined, known ones plain or highlighted', (tester) async {
      final (store, _) = await pumpReader(tester);
      await openText(tester);
      final known = _text(tester, 'reading-known');
      final counts = _text(tester, 'reading-counts');
      final m = RegExp(r'(\d+) of (\d+) words').firstMatch(counts)!;
      final k = int.parse(m[1]!), n = int.parse(m[2]!);
      expect(n, 21, reason: "c'era is two words");
      expect(k, greaterThanOrEqualTo(3), reason: 'il ×2, in, otto');
      expect(known, '${k * 100 ~/ n}% of words known');
      // "arrivò" (not practised) is underlined, "Il" (known) is not.
      TextStyle? styleOf(String word) {
        final rich = tester.widget<RichText>(
          find.descendant(of: find.byKey(const ValueKey('reading-p-0')), matching: find.byType(RichText)).first,
        );
        TextStyle? found;
        rich.text.visitChildren((s) {
          if (s is TextSpan && s.text == word) {
            found = s.style;
            return false;
          }
          return true;
        });
        return found;
      }

      expect(styleOf('arrivò')?.decoration, TextDecoration.underline);
      expect(styleOf('arrivò')?.decorationStyle, TextDecorationStyle.dotted);
      expect(styleOf('Il')?.decoration, isNot(TextDecoration.underline));
      await tapKey(tester, 'reading-highlight-known');
      expect(styleOf('Il')?.backgroundColor, isNotNull);
      expect(await store.getSetting(kReadingHighlightKnownKey), 'true');
    });

    testWidgets('a word: the popover with the grammar of the form, star and "Add to my words" prefilled', (
      tester,
    ) async {
      final (_, repo) = await pumpReader(tester);
      await openText(tester);
      await tapReadingWord(tester, 0, 'arrivò');
      expect(find.byKey(const ValueKey('word-popover')), findsOneWidget);
      final headline = _text(tester, 'word-popover-headline');
      expect(headline, startsWith('arrivò → arrivare'));
      expect(headline, contains('passato remoto'));
      expect(_text(tester, 'word-popover-detail'), contains('verb'));
      expect(_text(tester, 'word-popover-detail'), contains('new to you'));
      expect(find.byKey(const ValueKey('word-popover-star')), findsOneWidget);
      expect(find.byKey(const ValueKey('word-popover-reference')), findsOneWidget);
      await tapKey(tester, 'reading-add-word');
      expect(find.byKey(const ValueKey('my-word-sheet')), findsOneWidget);
      String field(String key) => tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
      expect(field('my-word-word'), 'arrivare');
      expect(field('my-word-translation'), isNotEmpty);
      expect(field('my-word-note'), contains('passato remoto'));
      expect(field('my-word-example'), 'Il commissario arrivò in questura alle otto.');
      await tapKey(tester, 'my-word-save');
      expect(find.byKey(const ValueKey('reading-word-added')), findsOneWidget);
      final saved = (await repo.load('it')).live.single;
      expect(saved.word, 'arrivare');
      expect(saved.lemmaId, 'it:arrivare');
      expect(saved.pos, 'verb');
      expect(saved.lang, 'en');
      expect(saved.id, startsWith('user~'));
      // Now the popover says it is in my words.
      await tapReadingWord(tester, 0, 'arrivò');
      expect(
        find.byKey(const ValueKey('reading-edit-word')),
        findsNothing,
        reason: 'my word is the lemma, not this form',
      );
    });

    testWidgets('a word not in the course: its own popover; my words show my meaning', (tester) async {
      await pumpReader(tester, words: await someWords());
      await openText(tester, 'Sul tavolo una qwertina e una zzyzx.');
      await tapReadingWord(tester, 0, 'qwertina');
      expect(_text(tester, 'word-popover-headline'), 'qwertina');
      expect(_text(tester, 'word-popover-glosses'), 'a made-up thing');
      expect(find.byKey(const ValueKey('reading-edit-word')), findsOneWidget);
      await tester.tapAt(const Offset(4, 600));
      await tester.pumpAndSettle();
      await tapReadingWord(tester, 0, 'zzyzx');
      expect(_text(tester, 'word-popover-glosses'), 'Not in this course');
      await tapKey(tester, 'reading-add-word');
      String field(String key) => tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
      expect(field('my-word-word'), 'zzyzx');
      expect(field('my-word-translation'), '');
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('my-word-save'))).onPressed, isNull);
    });

    testWidgets('elisions are tappable on their own: dell\' and acqua', (tester) async {
      await pumpReader(tester);
      await openText(tester, "Comprò dell'acqua.");
      await tapReadingWord(tester, 0, 'acqua');
      expect(_text(tester, 'word-popover-headline'), contains('acqua'));
    });

    testWidgets('a long text is laid out lazily', (tester) async {
      await pumpReader(tester);
      final long = List.generate(300, (i) => 'Riga $i: il commissario arrivò in questura alle otto.').join('\n');
      await openText(tester, long);
      expect(find.byKey(const ValueKey('reading-p-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('reading-p-299')), findsNothing, reason: 'not built until scrolled to');
      expect(find.byType(RichText).evaluate().length, lessThan(120));
    });
  });

  group('read aloud', () {
    testWidgets('the reader: play, the frame, next sentence, pause, from a sentence, slow, stop on leaving', (
      tester,
    ) async {
      final speaker = HoldingSpeaker();
      await pumpReader(tester, speaker: speaker);
      await openText(tester);
      await tester.tap(find.byKey(const ValueKey('reading-read-aloud')));
      await tester.pump();
      expect(speaker.spoken.single.$1, 'Il commissario arrivò in questura alle otto.');
      expect(speaker.spoken.single.$2, 'it');
      expect(speaker.spoken.single.$3, isFalse);
      await tester.pump();
      expect(find.byKey(const ValueKey('reading-speaking')), findsOneWidget);
      speaker.finish();
      await tester.pump();
      await tester.pump();
      expect(speaker.spoken.last.$1, "Sul tavolo c'era una lettera.");
      // Pause and resume the same sentence.
      await tester.tap(find.byKey(const ValueKey('reading-read-aloud')));
      await tester.pump();
      expect(speaker.stops, 1);
      expect(find.byKey(const ValueKey('reading-speaking')), findsOneWidget, reason: 'paused on it');
      await tester.tap(find.byKey(const ValueKey('reading-read-aloud')));
      await tester.pump();
      expect(speaker.spoken.last.$1, "Sul tavolo c'era una lettera.");
      // Slow: the sentence starts again at the slow rate.
      await tester.tap(find.byKey(const ValueKey('reading-read-aloud-slow')));
      await tester.pump();
      await tester.pump();
      expect(speaker.spoken.last.$3, isTrue);
      // From a tapped word's sentence.
      await tester.tap(find.byKey(const ValueKey('reading-read-aloud')));
      await tester.pump();
      await tapReadingWord(tester, 2, 'amico');
      await tapKey(tester, 'reading-read-from-here');
      await tester.pump();
      expect(speaker.spoken.last.$1, 'Poi chiamò il suo amico, che rispose subito.');
      // The last sentence ends: reading stops, no frame.
      speaker.finish();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reading-speaking')), findsNothing);
      // Leaving while reading stops the voice.
      await tester.tap(find.byKey(const ValueKey('reading-read-aloud')));
      await tester.pump();
      final stops = speaker.stops;
      await tapKey(tester, 'reading-back');
      expect(speaker.stops, greaterThan(stops));
    });

    testWidgets('no voice for the language: no read-aloud buttons, no "Read from here"', (tester) async {
      // Not Android: no "install a voice" snack bar over the Read button.
      await pumpReader(
        tester,
        speaker: HoldingSpeaker(languages: const {'nl'}),
        overrides: [isAndroidProvider.overrideWithValue(false)],
      );
      await openText(tester);
      expect(find.byKey(const ValueKey('reading-read-aloud')), findsNothing);
      await tapReadingWord(tester, 0, 'arrivò');
      expect(find.byKey(const ValueKey('reading-read-from-here')), findsNothing);
    });

    testWidgets(
      'a story: reads sentence by sentence revealing them, a tap starts at a sentence, slow, stops on leaving',
      (tester) async {
        final speaker = HoldingSpeaker();
        final course = storyCourse();
        final store = TestProgressStore();
        await practiceUnit(store, course, 'u1');
        final story = course.stories.first;
        await pumpApp(
          tester,
          store: store,
          initialLocation: Routes.story(story.id),
          overrides: [
            courseDataProvider.overrideWith((ref) async => course),
            speakerProvider.overrideWithValue(speaker),
          ],
        );
        expect(find.byKey(const ValueKey('story-sentence-1')), findsNothing, reason: 'revealed one at a time');
        await tester.tap(find.byKey(const ValueKey('story-read-aloud')));
        await tester.pump();
        expect(speaker.spoken.single.$1, story.sentences[0].text);
        await tester.pump();
        expect(find.byKey(const ValueKey('story-speaking-0')), findsOneWidget);
        speaker.finish();
        await tester.pump();
        await tester.pump();
        expect(speaker.spoken.last.$1, story.sentences[1].text);
        expect(find.byKey(const ValueKey('story-sentence-1')), findsOneWidget, reason: 'reading reveals it');
        expect(find.byKey(const ValueKey('story-speaking-1')), findsOneWidget);
        // A tap on the first sentence starts there.
        // (Off the words, which open their popover.)
        await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('story-sentence-0'))) + const Offset(3, 20));
        await tester.pump();
        await tester.pump();
        expect(speaker.spoken.last.$1, story.sentences[0].text);
        await tester.tap(find.byKey(const ValueKey('story-read-aloud-slow')));
        await tester.pump();
        await tester.pump();
        expect(speaker.spoken.last.$3, isTrue);
        final stops = speaker.stops;
        GoRouter.of(tester.element(find.byKey(const ValueKey('story-close')))).go(Routes.map);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('story-close')), findsNothing);
        expect(speaker.stops, greaterThan(stops));
      },
    );

    testWidgets('a story without a voice (Sarnami-like): no buttons, and a tap on a sentence does nothing', (
      tester,
    ) async {
      final speaker = HoldingSpeaker(languages: const {});
      final course = storyCourse();
      final store = TestProgressStore();
      await practiceUnit(store, course, 'u1');
      await pumpApp(
        tester,
        store: store,
        initialLocation: Routes.story(course.stories.first.id),
        overrides: [courseDataProvider.overrideWith((ref) async => course), speakerProvider.overrideWithValue(speaker)],
      );
      expect(find.byKey(const ValueKey('story-read-aloud')), findsNothing);
      await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('story-sentence-0'))) + const Offset(3, 20));
      await tester.pumpAndSettle();
      expect(speaker.spoken, isEmpty);
    });
  });

  group('my words', () {
    testWidgets('empty state, add with validation, edit, delete and undo', (tester) async {
      final (_, repo) = await pumpReader(tester, location: Routes.myWords);
      expect(find.byKey(const ValueKey('my-words-empty')), findsOneWidget);
      await tapKey(tester, 'my-words-add-empty');
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('my-word-save'))).onPressed, isNull);
      expect(find.byKey(const ValueKey('my-word-needs')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('my-word-word')), 'questura');
      await tester.enterText(find.byKey(const ValueKey('my-word-translation')), 'police headquarters');
      await tester.enterText(find.byKey(const ValueKey('my-word-note')), 'feminine');
      await tester.pumpAndSettle();
      await tapKey(tester, 'my-word-save');
      final w = (await repo.load('it')).live.single;
      expect(w.note, 'feminine');
      expect(find.byKey(ValueKey('my-word-${w.id}')), findsOneWidget);
      expect(_text(tester, 'my-word-status-${w.id}'), 'New');
      expect(_text(tester, 'my-words-counts'), '1 word · 1 new');
      // Edit.
      await tapIt(tester, find.byKey(ValueKey('my-word-${w.id}')));
      await tester.enterText(find.byKey(const ValueKey('my-word-translation')), 'police station');
      await tester.pumpAndSettle();
      await tapKey(tester, 'my-word-save');
      expect(find.text('police station'), findsOneWidget);
      expect((await repo.load('it'))[w.id]!.created, w.created);
      // Delete and undo.
      await tapKey(tester, 'my-word-delete-${w.id}');
      expect(find.byKey(const ValueKey('my-words-empty')), findsOneWidget);
      expect((await repo.load('it'))[w.id]!.removed, isTrue);
      await tester.tap(find.byKey(const ValueKey('my-word-undo')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('my-word-${w.id}')), findsOneWidget);
      expect((await repo.load('it'))[w.id]!.translation, 'police station');
    });

    testWidgets('Settings and the Read tab lead to My words', (tester) async {
      await pumpReader(tester, words: await someWords());
      expect(find.text('My words (4)'), findsOneWidget);
      await tapKey(tester, 'open-my-words');
      expect(find.byKey(const ValueKey('my-words-list')), findsOneWidget);
    });

    testWidgets('practise my words: their own exercises through the engine, answers recorded', (tester) async {
      final (store, _) = await pumpReader(tester, location: Routes.myWords, words: await someWords(), engine: true);
      await tapKey(tester, 'my-words-practice');
      final seen = <String>{};
      for (var i = 0; i < 12 && find.byType(ExerciseView).evaluate().isNotEmpty; i++) {
        final e = currentExercise(tester);
        expect(isUserFacetId(e.facetId), isTrue);
        seen.add(e.facetId);
        await answerCurrent(tester);
      }
      expect(seen, hasLength(6));
      expect(find.byKey(const ValueKey('summary-done')), findsOneWidget);
      final log = await store.log();
      expect(log.where((e) => e.mode == 'myWords'), hasLength(6));
    });
  });

  group('black & white and layout', () {
    for (final entry in {...bwSizes, 'phone 412x915': const Size(412, 915)}.entries) {
      testWidgets('every new screen at ${entry.key}', (tester) async {
        final speaker = HoldingSpeaker();
        await pumpReader(
          tester,
          size: entry.value,
          settings: {SettingKeys.display: 'bw'},
          speaker: speaker,
          words: await someWords(),
        );
        await expectGrayscale(tester, 'read tab');
        expect(tester.takeException(), isNull);
        await openText(tester);
        await expectGrayscale(tester, 'reader');
        await tapKey(tester, 'reading-highlight-known');
        await expectGrayscale(tester, 'reader, known highlighted');
        await tapReadingWord(tester, 0, 'arrivò');
        await expectGrayscale(tester, 'popover');
        await tapKey(tester, 'reading-add-word');
        await expectGrayscale(tester, 'add sheet');
        await tapKey(tester, 'my-word-cancel');
        await tester.tap(find.byKey(const ValueKey('reading-read-aloud')));
        await tester.pump();
        await tester.pump();
        await expectGrayscale(tester, 'reading aloud');
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'reading-back');
        await openMyWordsFromRead(tester);
        await expectGrayscale(tester, 'my words');
        expect(tester.takeException(), isNull);
      });
    }

    for (final size in [const Size(320, 568), const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('colour, dark and text 1.3 at ${size.width.toInt()}x${size.height.toInt()}: no overflow', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final speaker = HoldingSpeaker();
        await pumpReader(
          tester,
          size: size,
          settings: {SettingKeys.themeMode: 'dark'},
          speaker: speaker,
          words: await someWords(),
        );
        await openText(tester);
        await tapReadingWord(tester, 0, 'arrivò');
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'reading-add-word');
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'my-word-cancel');
        await tester.tap(find.byKey(const ValueKey('reading-read-aloud')));
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'reading-back');
        await openMyWordsFromRead(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('my words exercises in black & white at the e-reader sizes', (tester) async {
      for (final size in [const Size(360, 640), const Size(572, 772), const Size(1003, 1337)]) {
        final (_, _) = await pumpReader(
          tester,
          size: size,
          settings: {SettingKeys.display: 'bw'},
          location: Routes.myWordsPlay,
          words: await someWords(),
          engine: true,
        );
        for (var i = 0; i < 6 && find.byType(ExerciseView).evaluate().isNotEmpty; i++) {
          await expectGrayscale(tester, 'my words exercise $i at $size');
          expect(tester.takeException(), isNull);
          await answerCurrent(tester, wrong: i == 1);
        }
      }
    });

    testWidgets('a story reading aloud in black & white', (tester) async {
      final course = storyCourse();
      final store = TestProgressStore(settings: {SettingKeys.display: 'bw'});
      await practiceUnit(store, course, 'u1');
      await pumpApp(
        tester,
        size: const Size(360, 640),
        store: store,
        initialLocation: Routes.story(course.stories.first.id),
        overrides: [
          courseDataProvider.overrideWith((ref) async => course),
          speakerProvider.overrideWithValue(HoldingSpeaker()),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('story-read-aloud')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('story-speaking-0')), findsOneWidget);
      await expectGrayscale(tester, 'story reading aloud');
    });
  });
}
