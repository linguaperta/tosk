// First-time exercise intros: shown once per type before the exercise,
// persisted account-wide, re-openable with (?); examples from the course's own
// data; black & white pixel scan and layout at every harness size.
import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/lesson/intro/exercise_intros.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bw_helpers.dart';
import 'bw_mode_test.dart' show bwSizes;
import 'helpers.dart';

final _intros = [exerciseIntrosEnabledProvider.overrideWithValue(true)];
final _allSkills = buildDemoItalian().skills.map((s) => s.id).toList();

Future<TestProgressStore> _lab(
  WidgetTester tester,
  ExerciseType type, {
  TestProgressStore? store,
  Size size = const Size(400, 800),
  int length = 2,
}) => pumpApp(
  tester,
  size: size,
  store: store,
  initialLocation: Routes.labPlay(skills: _allSkills, types: [type], length: length),
  overrides: _intros,
);

void main() {
  group('first-time intro', () {
    for (final type in ExerciseType.values) {
      testWidgets('${type.id}: shown before the first one, then never again', (tester) async {
        final store = await _lab(tester, type);
        expect(find.byKey(ValueKey('exercise-intro-${type.id}')), findsOneWidget);
        expect(find.text(introFor(type).title), findsOneWidget);
        expect(find.byKey(const ValueKey('intro-example')), findsOneWidget);
        // The exercise is not on screen yet, and no (?) while the intro shows.
        expect(find.byKey(const ValueKey('exercise-scroll')), findsNothing);
        expect(find.byKey(const ValueKey('exercise-help')), findsNothing);
        await tapKey(tester, 'intro-got-it');
        expect(find.byKey(ValueKey('exercise-intro-${type.id}')), findsNothing);
        expect(find.byKey(const ValueKey('exercise-scroll')), findsOneWidget);
        expect(currentExercise(tester).type, type);
        // Persisted, account-wide.
        expect(parseIntroSeen(store.settings[SettingKeys.introSeen]), {type});
        // The second exercise of the same type: no intro.
        await answerCurrent(tester);
        if (find.byKey(const ValueKey('session-summary')).evaluate().isEmpty) {
          expect(find.byKey(ValueKey('exercise-intro-${type.id}')), findsNothing);
          expect(find.byKey(const ValueKey('exercise-scroll')), findsOneWidget);
        }
        // A new session with the same store: no intro either.
        await tester.pumpWidget(const SizedBox());
        await _lab(tester, type, store: store);
        expect(find.byKey(ValueKey('exercise-intro-${type.id}')), findsNothing);
        expect(currentExercise(tester).type, type);
      });
    }

    testWidgets('Enter dismisses the intro (desktop)', (tester) async {
      await _lab(tester, ExerciseType.multipleChoice, size: const Size(1280, 800));
      expect(find.byKey(const ValueKey('exercise-intro-multiple_choice')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exercise-intro-multiple_choice')), findsNothing);
      expect(currentExercise(tester).type, ExerciseType.multipleChoice);
    });

    testWidgets('(?) reopens the explanation over the exercise', (tester) async {
      final store = TestProgressStore(settings: {SettingKeys.introSeen: 'transform'});
      await _lab(tester, ExerciseType.transform, store: store);
      expect(find.byKey(const ValueKey('exercise-intro-transform')), findsNothing);
      await tapKey(tester, 'exercise-help');
      expect(find.byKey(const ValueKey('exercise-intro-sheet-transform')), findsOneWidget);
      expect(find.text('Change the tense or person'), findsOneWidget);
      await tapKey(tester, 'intro-sheet-close');
      expect(find.byKey(const ValueKey('exercise-intro-sheet-transform')), findsNothing);
      expect(currentExercise(tester).type, ExerciseType.transform);
    });

    testWidgets('intros off (the test default): straight to the exercise', (tester) async {
      await pumpApp(
        tester,
        initialLocation: Routes.labPlay(skills: _allSkills, types: [ExerciseType.cloze], length: 1),
      );
      expect(find.byKey(const ValueKey('exercise-intro-cloze')), findsNothing);
      expect(currentExercise(tester).type, ExerciseType.cloze);
    });
  });

  group('examples from the course', () {
    for (final course in [buildDemoItalian(), buildDemoDutch()]) {
      test('demo ${course.meta.id}: every type has an example (sentence types when it has sentences)', () {
        final hasSentences = course.allItems.any((i) => course.sentencesFor(i.id).isNotEmpty);
        for (final t in ExerciseType.values) {
          final lines = introExample(t, course, 'en');
          if (!hasSentences && (t == ExerciseType.sentenceBuilder || t == ExerciseType.cloze)) {
            expect(lines, isEmpty);
            continue;
          }
          expect(lines, isNotEmpty, reason: t.id);
          for (final l in lines) {
            expect(l.from.trim(), isNotEmpty, reason: '$t $l');
            expect(l.to.trim(), isNotEmpty, reason: '$t $l');
          }
        }
      });
    }

    for (final id in ['it', 'nl']) {
      test('real pack $id: every type has an example, in both source languages', () {
        final course = loadCourseFile('assets/courses/$id.sqlite');
        for (final lang in ['en', 'nl']) {
          for (final t in ExerciseType.values) {
            expect(introExample(t, course, lang), isNotEmpty, reason: '$id $lang ${t.id}');
          }
        }
        // "mangio → ho mangiato": a tense change of the same person.
        final tr = introExample(ExerciseType.transform, course, 'en').first;
        expect(tr.from, startsWith('${course.meta.tenseLabel(course.meta.tenses.first, 'en')}: '));
      });
    }

    test('the transform example changes the tense of a real verb form', () {
      final it = buildDemoItalian();
      final lines = introExample(ExerciseType.transform, it, 'en');
      expect(lines.first.from, startsWith('${it.meta.tenseLabel(it.meta.tenses.first, 'en')}: '));
      expect(lines.first.to, isNot(lines.first.from));
    });

    test('never the current exercise\'s own words', () {
      final it = buildDemoItalian();
      final first = introExample(ExerciseType.flashcard, it, 'en').single;
      final item = it.allItems.firstWhere((i) => first.from.endsWith(i.lemma) && !i.isVerb);
      final ex = FlashcardExercise(
        id: 'x',
        facetId: '${item.id}#rec',
        front: item.lemma,
        back: 'x',
        direction: Direction.values.first,
      );
      final other = introExample(ExerciseType.flashcard, it, 'en', current: ex).single;
      expect(other.from, isNot(first.from));
    });

    test('seen types round-trip through the setting', () {
      expect(parseIntroSeen(null), isEmpty);
      expect(parseIntroSeen('cloze, transform,nope'), {ExerciseType.cloze, ExerciseType.transform});
      expect(formatIntroSeen({ExerciseType.transform, ExerciseType.flashcard}), 'flashcard,transform');
    });
  });

  group('layout and black & white', () {
    const shown = [ExerciseType.matchPairs, ExerciseType.transform, ExerciseType.sentenceBuilder];
    for (final entry in bwSizes.entries) {
      testWidgets('black & white ${entry.key}: intro screen and (?) sheet', (tester) async {
        for (final type in shown) {
          await _lab(tester, type, size: entry.value, store: TestProgressStore(settings: {SettingKeys.display: 'bw'}));
          await expectGrayscale(tester, '${type.id} intro');
          expect(tester.takeException(), isNull);
          await tapKey(tester, 'intro-got-it');
          await tapKey(tester, 'exercise-help');
          await expectGrayscale(tester, '${type.id} (?) sheet');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
    for (final size in const [Size(320, 568), Size(360, 640), Size(1280, 800)]) {
      testWidgets('color, dark, text 1.3 at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (final type in ExerciseType.values) {
          await _lab(tester, type, size: size, store: TestProgressStore(settings: {SettingKeys.themeMode: 'dark'}));
          expect(find.byKey(ValueKey('exercise-intro-${type.id}')), findsOneWidget);
          expect(tester.takeException(), isNull, reason: type.id);
          await tapKey(tester, 'intro-got-it');
          await tapKey(tester, 'exercise-help');
          expect(tester.takeException(), isNull, reason: '${type.id} sheet');
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  });
}
