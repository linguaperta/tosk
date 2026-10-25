// Review screenshots of reading mode, my words and read aloud with real fonts
// on the bundled Italian pack (no `_test` suffix, so not in the default run):
//   QA_OUT=../docs/screenshots/reading QA_RATIO=1 flutter test test/qa/reading_preview.dart
// Phone size, colour and black & white: the Read tab, the reader (known
// share, unknown words underlined, known ones highlighted), a word popover
// (passato remoto) and a word not in the course, the add sheet prefilled
// from the reader, the My words list, a My words exercise, the reader and a
// story reading aloud. The committed renders are in docs/screenshots/reading/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_loader.dart';
import 'package:tosk/data/progress/user_words.dart';
import 'package:tosk/engine/engine.dart' show FocusPresets;
import 'package:tosk/providers.dart';
import 'package:tosk/speech/speech_providers.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

import '../fixtures/topic_course.dart' show TopicCourseCatalog;
import '../ui/helpers.dart';
import '../ui/reading_helpers.dart';
import 'brand_preview.dart' show loadQaFonts;

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa-reading');
final _ratio = double.tryParse(Platform.environment['QA_RATIO'] ?? '') ?? 2;
const _phone = Size(390, 844);

const kSampleText =
    'Il commissario arrivò in questura alle otto. Sul tavolo c\'era una lettera senza firma.\n'
    '\n'
    'La aprì con attenzione e lesse le prime righe. Poi chiamò il suo amico, che rispose subito: '
    '«Arrivo, ho appena mangiato.»\n'
    '\n'
    'Fuori pioveva. Il commissario guardò la città e pensò alla sua casa al mare.';

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

CourseData? _it;
CourseData get it => _it ??= () {
  final db = sqlite3.open('assets/courses/it.sqlite', mode: OpenMode.readOnly);
  try {
    return loadCourseFromSqlite(db);
  } finally {
    db.close();
  }
}();

/// A learner who has practised the words of the first [units] units.
Future<TestProgressStore> learner(Map<String, String> settings, {int units = 8}) async {
  final store = TestProgressStore(settings: {SettingKeys.coursesAdded: 'it', ...settings});
  final mainUnits = CourseTrees.of(it).mainUnits.take(units).map((u) => u.id).toSet();
  var n = 0;
  final seen = <String>{};
  for (final s in it.skills.where((s) => mainUnits.contains(s.unitId))) {
    for (final i in it.skillItems(s.id)) {
      if (!seen.add(i.id)) continue;
      await store.record(
        ReviewEvent(
          id: 'k${n++}',
          facetId: '${i.id}#rec',
          at: testNow.subtract(const Duration(days: 3)),
          rating: Rating.good,
          exerciseType: 'flashcard',
          inputMode: InputMode.self,
          responseMs: 1000,
          correct: true,
        ),
      );
    }
  }
  return store;
}

Future<InMemoryUserWordRepo> myWords() async {
  final repo = InMemoryUserWordRepo();
  final store = UserWordStore(repo, clock: () => testNow);
  await store.add(
    'it',
    word: 'questura',
    translation: 'police headquarters',
    example: 'Il commissario arrivò in questura alle otto.',
    pos: 'noun',
  );
  await store.add('it', word: 'firma', translation: 'signature', pos: 'noun');
  await store.add('it', word: 'commissario', translation: 'inspector, superintendent', note: 'Montalbano', pos: 'noun');
  await store.add('it', word: 'indagare', translation: 'to investigate', pos: 'verb');
  return repo;
}

Future<HoldingSpeaker> _pump(
  WidgetTester tester,
  Map<String, String> settings, {
  String location = Routes.read,
  InMemoryUserWordRepo? words,
}) async {
  final speaker = HoldingSpeaker();
  final store = await learner(settings);
  final repo = words ?? await myWords();
  await pumpApp(
    tester,
    size: _phone,
    store: store,
    engine: true,
    initialLocation: location,
    overrides: [
      courseCatalogProvider.overrideWithValue(TopicCourseCatalog(it)),
      // rootBundle caches the asset's future in the first test's zone, where a
      // later test can't await it: the engine's defaults are the same presets.
      focusPresetsProvider.overrideWith((ref) async => FocusPresets.defaults),
      speakerProvider.overrideWithValue(speaker),
      userWordRepoProvider.overrideWithValue(repo),
    ],
  );
  return speaker;
}

Future<void> _openText(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('reading-input')), kSampleText);
  await tester.pumpAndSettle();
  await tapKey(tester, 'reading-read');
}

void main() {
  setUpAll(loadQaFonts);

  for (final (mode, settings) in [
    ('colour', <String, String>{}),
    ('bw', {SettingKeys.display: 'bw'}),
  ]) {
    testWidgets('read tab, $mode', (tester) async {
      await _pump(tester, settings);
      await _openText(tester);
      await tapKey(tester, 'reading-back');
      await tester.enterText(
        find.byKey(const ValueKey('reading-input')),
        'Ieri sono andata al mercato con mia sorella.',
      );
      await tester.pumpAndSettle();
      await _shot(tester, 'read-tab-$mode');
    });

    testWidgets('reader, popover, add sheet, $mode', (tester) async {
      await _pump(tester, settings);
      await _openText(tester);
      await _shot(tester, 'reader-$mode');
      await tapReadingWord(tester, 0, 'arrivò');
      await _shot(tester, 'reader-popover-$mode');
      await tester.tapAt(const Offset(5, 400));
      await tester.pumpAndSettle();
      await tapReadingWord(tester, 0, 'firma');
      await _shot(tester, 'reader-my-word-$mode');
      await tester.tapAt(const Offset(5, 400));
      await tester.pumpAndSettle();
      await tapReadingWord(tester, 4, 'pioveva');
      await tapKey(tester, 'reading-add-word');
      await _shot(tester, 'reader-add-sheet-$mode');
    });

    testWidgets('reader, known words highlighted, reading aloud, $mode', (tester) async {
      final speaker = await _pump(tester, settings);
      await _openText(tester);
      await tapKey(tester, 'reading-highlight-known');
      await _shot(tester, 'reader-known-$mode');
      await tester.tap(find.byKey(const ValueKey('reading-read-aloud')));
      await tester.pump();
      speaker.finish();
      await tester.pump();
      speaker.finish();
      await tester.pumpAndSettle();
      await _shot(tester, 'reader-aloud-$mode');
    });

    testWidgets('my words, $mode', (tester) async {
      await _pump(tester, settings, location: Routes.myWords);
      await _shot(tester, 'my-words-$mode');
      await tapKey(tester, 'my-words-practice');
      await _shot(tester, 'my-words-practice-$mode');
    });

    testWidgets('story read aloud, $mode', (tester) async {
      final story = it.stories.first;
      final speaker = await _pump(tester, settings, location: Routes.story(story.id));
      await tester.tap(find.byKey(const ValueKey('story-read-aloud')));
      await tester.pump();
      speaker.finish();
      await tester.pump();
      speaker.finish();
      await tester.pumpAndSettle();
      await _shot(tester, 'story-aloud-$mode');
    });
  }
}
