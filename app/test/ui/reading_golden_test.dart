// Golden images of reading mode, my words and read aloud in black & white
// (and the reader in colour). Test font (Ahem), like bw_golden_test.dart.
// Update with:
//   flutter test --update-goldens test/ui/reading_golden_test.dart
// Rendered on Windows; CI (Linux) skips them with --exclude-tags golden.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/speech/speech_providers.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

import '../fixtures/story_course.dart';
import 'helpers.dart';
import 'reading_helpers.dart';
import 'reading_test.dart' show openText, pumpReader, someWords;
import 'stories_test.dart' show practiceUnit;

Future<void> _golden(WidgetTester tester, String name) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
  await expectLater(find.byKey(appRootKey), matchesGoldenFile('goldens/$name.png'));
}

const _phone = Size(390, 844);
const _bw = {SettingKeys.display: 'bw'};

void main() {
  testWidgets('reader in black & white: unknown words, the popover, reading aloud', (tester) async {
    await pumpReader(tester, size: _phone, settings: _bw, speaker: HoldingSpeaker(), words: await someWords());
    await openText(tester);
    await _golden(tester, 'bw_reader');
    await tapReadingWord(tester, 0, 'arrivò');
    await _golden(tester, 'bw_reader_popover');
    await tester.tapAt(const Offset(4, 700));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reading-read-aloud')));
    await tester.pump();
    await _golden(tester, 'bw_reader_aloud');
  });

  testWidgets('reader in colour with known words highlighted', (tester) async {
    await pumpReader(tester, size: _phone, speaker: HoldingSpeaker(), words: await someWords());
    await openText(tester);
    await tapKey(tester, 'reading-highlight-known');
    await _golden(tester, 'reader_known_colour');
  });

  testWidgets('read tab in black & white', (tester) async {
    await pumpReader(tester, size: _phone, settings: _bw, words: await someWords());
    await _golden(tester, 'bw_read_tab');
  });

  testWidgets('my words in black & white', (tester) async {
    await pumpReader(tester, size: _phone, settings: _bw, words: await someWords(), location: Routes.myWords);
    await _golden(tester, 'bw_my_words');
    await tapKey(tester, 'my-words-add');
    await _golden(tester, 'bw_my_word_sheet');
  });

  testWidgets('a story reading aloud in black & white', (tester) async {
    final course = storyCourse();
    final store = TestProgressStore(settings: _bw);
    await practiceUnit(store, course, 'u1');
    await pumpApp(
      tester,
      size: _phone,
      store: store,
      initialLocation: Routes.story(course.stories.first.id),
      overrides: [
        courseDataProvider.overrideWith((ref) async => course),
        speakerProvider.overrideWithValue(HoldingSpeaker()),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('story-read-aloud')));
    await tester.pump();
    await _golden(tester, 'bw_story_aloud');
  });
}
