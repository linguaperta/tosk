// One-handed use: the interactive part of every exercise sits in the lower
// part of the screen (prompt on top), and tap targets are at least 48 px.
import 'package:tosk/core/core.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/lesson/exercises/exercise_layout.dart';
import 'package:tosk/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// A control of each exercise type that should be in the thumb zone.
String controlKey(Exercise e) => switch (e) {
  FlashcardExercise() => 'flashcard-reveal',
  MultipleChoiceExercise e => 'option-${e.options.length - 1}',
  MatchPairsExercise e => 'match-left-${e.left.length - 1}',
  ConjPickExercise() => 'ending-0',
  ConjGridExercise() => 'grid-tile-0',
  SentenceBuilderExercise() || TransformExercise() => 'tile-0',
  ClozeExercise() => 'cloze-option-0',
  SpotErrorExercise() => 'token-0',
};

void main() {
  final allSkills = buildDemoItalian().skills.map((s) => s.id).toList();

  for (final size in const [Size(400, 800), Size(1280, 800)]) {
    for (final type in ExerciseType.values) {
      testWidgets('${type.id} at ${size.width.round()}x${size.height.round()}: controls near the bottom', (
        tester,
      ) async {
        await pumpApp(
          tester,
          size: size,
          initialLocation: Routes.labPlay(skills: allSkills, types: [type], length: 1),
        );
        final ex = currentExercise(tester);
        final control = find.byKey(ValueKey(controlKey(ex)));
        expect(control, findsOneWidget);
        // The control's bottom is in the lower 40 % of the screen...
        expect(tester.getBottomLeft(control).dy, greaterThan(size.height * 0.6), reason: type.id);
        // ...and still on screen, above the Check button when there is one.
        final check = find.byKey(const ValueKey('check-button'));
        final limit = check.evaluate().isEmpty ? size.height : tester.getTopLeft(check).dy;
        expect(tester.getBottomLeft(control).dy, lessThanOrEqualTo(limit), reason: type.id);
        // The instruction stays at the top.
        final layout = find.byType(ExerciseLayout);
        expect(tester.getTopLeft(layout).dy, lessThan(size.height * 0.2));
        // Centered column on wide screens.
        if (size.width > 700) {
          final r = tester.getRect(layout);
          expect(r.width, lessThanOrEqualTo(640));
          expect((r.center.dx - size.width / 2).abs(), lessThan(1));
        }
      });
    }
  }

  testWidgets('tap targets: options, tiles and grid cells are at least 48 px tall', (tester) async {
    for (final type in [ExerciseType.multipleChoice, ExerciseType.conjGrid, ExerciseType.sentenceBuilder]) {
      await pumpApp(
        tester,
        initialLocation: Routes.labPlay(skills: allSkills, types: [type], length: 1),
      );
      final keys = switch (currentExercise(tester)) {
        MultipleChoiceExercise() => ['option-0'],
        ConjGridExercise e => ['grid-tile-0', 'grid-cell-${e.cells.indexWhere((c) => !c.prefilled)}'],
        _ => ['tile-0'],
      };
      for (final k in keys) {
        final s = tester.getSize(find.byKey(ValueKey(k)));
        expect(s.height, greaterThanOrEqualTo(48), reason: k);
        expect(s.width, greaterThanOrEqualTo(48), reason: k);
      }
      // Reset the app between types.
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('ExerciseLayout: a plain column without a minimum height, split with one', (tester) async {
    Widget layout(BoxConstraints c) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: c,
          child: const ExerciseLayout(
            gap: 10,
            prompt: SizedBox(key: ValueKey('p'), height: 50),
            controls: SizedBox(key: ValueKey('c'), height: 100),
          ),
        ),
      ),
    );
    await tester.pumpWidget(layout(const BoxConstraints(maxWidth: 300)));
    expect(tester.getSize(find.byType(ExerciseLayout)), const Size(300, 160));
    expect(tester.getTopLeft(find.byKey(const ValueKey('c'))).dy, 60);
    await tester.pumpWidget(layout(const BoxConstraints(maxWidth: 300, minHeight: 500)));
    expect(tester.getSize(find.byType(ExerciseLayout)), const Size(300, 500));
    expect(tester.getTopLeft(find.byKey(const ValueKey('p'))).dy, 0);
    expect(tester.getBottomLeft(find.byKey(const ValueKey('c'))).dy, 500);
    expect(tester.getSize(find.byKey(const ValueKey('c'))).width, 300);
  });
}
