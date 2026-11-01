// Review screenshots of placement with real fonts on the bundled Italian pack
// (no `_test` suffix, so not in the default run):
//   QA_OUT=../docs/screenshots/placement flutter test test/qa/placement_preview.dart
// A phone in colour and black & white: "New to Italian?", the test's items
// (a whole verb form, a word from its meaning; tapped and typed), the word
// check of a learner who knows the first six units (its start, a word, the
// word revealed, the offer after a good sample), the result, "Skip ahead
// without a test", and "Reset this skill".
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show ValueKey;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_loader.dart';
import 'package:tosk/engine/engine.dart' show FocusPresets, isBareCloze;
import 'package:tosk/providers.dart';
import 'package:tosk/ui/settings/learner_settings.dart' show LearnerSettingKeys;
import 'package:tosk/ui/settings/setting_keys.dart';

import '../fixtures/topic_course.dart' show TopicCourseCatalog;
import '../ui/helpers.dart';
import 'brand_preview.dart' show loadQaFonts;

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa-placement');
final _ratio = double.tryParse(Platform.environment['QA_RATIO'] ?? '') ?? 1;
const _phone = Size(390, 844);

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
CourseData _italian() => _it ??= () {
  final db = sqlite3.open('assets/courses/it.sqlite', mode: OpenMode.readOnly);
  try {
    return loadCourseFromSqlite(db);
  } finally {
    db.close();
  }
}();

Future<TestProgressStore> _pump(WidgetTester tester, Map<String, String> settings, {bool fresh = true}) => pumpApp(
  tester,
  size: _phone,
  engine: true,
  store: TestProgressStore(fresh: fresh, settings: {if (!fresh) SettingKeys.coursesAdded: 'it', ...settings}),
  overrides: [
    courseCatalogProvider.overrideWithValue(TopicCourseCatalog(_italian())),
    focusPresetsProvider.overrideWith((ref) async => FocusPresets.defaults),
  ],
);

bool _visible(String key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty;

void main() {
  setUpAll(loadQaFonts);

  for (final (mode, settings) in [('colour', <String, String>{}), ('bw', {SettingKeys.display: 'bw'})]) {
    testWidgets('the placement test and the word check, $mode', (tester) async {
      final course = _italian();
      final main = CourseTrees.of(course).mainUnits;
      final unitOf = {for (final s in course.skills) s.id: main.indexWhere((u) => u.id == s.unitId)};
      await _pump(tester, settings);
      await tapKey(tester, 'course-add-it');
      await _shot(tester, '01-new-to-italian-$mode');
      await tapKey(tester, 'placement-find');
      // A learner who knows units 1-6.
      var form = false, word = false;
      for (var i = 0; i < 45 && !inWordCheck() && !_visible('session-summary'); i++) {
        final e = currentExercise(tester);
        if (!form && e is ConjPickExercise) {
          await _shot(tester, '02-item-form-$mode');
          form = true;
        } else if (!word && e is ClozeExercise && isBareCloze(e)) {
          await _shot(tester, '03-item-word-$mode');
          word = true;
        }
        final unit = unitOf[e.skillId] ?? 99;
        await answerCurrent(tester, wrong: unit >= 6 || unit < 0);
      }
      await _shot(tester, '04-word-check-$mode');
      await tapKey(tester, 'word-check-start');
      await _shot(tester, '05-word-check-word-$mode');
      await tapKey(tester, 'word-check-reveal');
      await _shot(tester, '06-word-check-revealed-$mode');
      for (var i = 0; i < 40 && !_visible('word-check-offer'); i++) {
        if (!_visible('word-check-reveal') && !_visible('word-check-knew')) break;
        if (_visible('word-check-reveal')) await tapKey(tester, 'word-check-reveal');
        await tapKey(tester, 'word-check-knew');
      }
      await _shot(tester, '07-word-check-offer-$mode');
      await tapKey(tester, 'word-check-mark-rest');
      // The rest of unit 1's skills, then the later units left as new.
      for (var i = 0; i < 300 && inWordCheck(); i++) {
        if (_visible('word-check-offer')) {
          await tapKey(tester, 'word-check-mark-rest');
        } else if (i > 60) {
          await tapKey(tester, 'word-check-skip-unit');
        } else {
          await tapKey(tester, 'word-check-reveal');
          await tapKey(tester, 'word-check-knew');
        }
      }
      await _shot(tester, '08-result-$mode');
    });

    testWidgets('skip ahead and reset, $mode', (tester) async {
      await _pump(tester, settings);
      await tapKey(tester, 'course-add-it');
      await tapKey(tester, 'placement-skip');
      final third = CourseTrees.of(_italian()).mainUnits[2].id;
      await tapKey(tester, 'skip-unit-$third');
      await _shot(tester, '11-skip-ahead-$mode');
      await tapKey(tester, 'skip-ahead-confirm');
      await _shot(tester, '12-skip-ahead-result-$mode');
      await tapKey(tester, 'skip-ahead-done');
      final first = _italian().skills.first.id;
      await tapKey(tester, 'skill-node-$first');
      await scrollToFind(tester, find.byKey(const ValueKey('skill-reset')));
      await tapKey(tester, 'skill-reset');
      await _shot(tester, '13-reset-dialog-$mode');
      await tapKey(tester, 'skill-reset-confirm');
      await _shot(tester, '14-reset-undo-$mode');
    });
  }

  testWidgets('typed items and a typed word check, colour', (tester) async {
    await _pump(tester, {LearnerSettingKeys.answerInput: 'type'});
    await tapKey(tester, 'course-add-it');
    await tapKey(tester, 'placement-find');
    var form = false, word = false;
    for (var i = 0; i < 45 && !inWordCheck() && !_visible('session-summary'); i++) {
      final e = currentExercise(tester);
      if (!form && e is ConjPickExercise) {
        await _shot(tester, '09-item-form-typed-colour');
        form = true;
      } else if (!word && e is ClozeExercise && isBareCloze(e)) {
        await _shot(tester, '09-item-word-typed-colour');
        word = true;
      }
      await answerCurrent(tester);
    }
    await tapKey(tester, 'word-check-start');
    await tester.enterText(find.byKey(const ValueKey('word-check-input')), 'xyzzy');
    await tester.pumpAndSettle();
    await tapKey(tester, 'word-check-check');
    await _shot(tester, '10-word-check-typed-colour');
  });
}
