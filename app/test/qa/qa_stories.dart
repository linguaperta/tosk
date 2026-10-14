// Real-font screenshots of the graded stories on the real packs (not in the
// default run): QA_OUT=<dir> flutter test test/qa/qa_stories.dart
import 'package:tosk/ui/lesson/exercises/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/helpers.dart' show goTab, tapIt, tapKey;
import 'qa_walkthrough.dart' show loadQaFonts, pumpReal, settleReal, shot;

void main() {
  setUpAll(loadQaFonts);

  for (final (course, bw) in const [('it', false), ('nl', false), ('it', true)]) {
    testWidgets('stories $course${bw ? ' bw' : ''}', (tester) async {
      final tag = '$course${bw ? '-bw' : ''}';
      await pumpReal(
        tester,
        settings: {'course.active': course, if (bw) 'ui.display': 'bw'},
      );
      await goTab(tester, 'Practice');
      await tapKey(tester, 'practice-tab-stories');
      await settleReal(tester, until: find.byKey(const ValueKey('stories-list')));
      await shot(tester, 'stories-$tag-1-list');
      final first = '$course-u1'.startsWith('it') ? 'u1-piacere' : 'u1-familie';
      await tapKey(tester, 'story-tile-$first');
      await settleReal(tester, until: find.byKey(const ValueKey('story-sentence-0')));
      for (var i = 0; i < 4; i++) {
        await tapKey(tester, 'story-next');
      }
      await tapKey(tester, 'story-translate-2');
      await shot(tester, 'stories-$tag-2-reader');
      await tapKey(tester, 'word-s1-1');
      await shot(tester, 'stories-$tag-3-popover');
      await tester.tapAt(const Offset(2, 400));
      await tester.pumpAndSettle();
      while (find.byKey(const ValueKey('story-next')).evaluate().isNotEmpty) {
        await tapKey(tester, 'story-next');
      }
      await tapKey(tester, 'story-to-questions');
      await shot(tester, 'stories-$tag-4-question');
      await tapIt(tester, find.byType(OptionButton).first);
      await shot(tester, 'stories-$tag-5-answered');
      while (find.byKey(const ValueKey('story-result')).evaluate().isEmpty) {
        if (find.byType(OptionButton).evaluate().isNotEmpty &&
            find.byKey(const ValueKey('story-verdict-right')).evaluate().isEmpty &&
            find.byKey(const ValueKey('story-verdict-wrong')).evaluate().isEmpty) {
          await tapIt(tester, find.byType(OptionButton).first);
        }
        await tapKey(tester, 'story-question-next');
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
      await shot(tester, 'stories-$tag-6-result');
    });
  }
}
