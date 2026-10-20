// Partly right sentence answers in the player: the word diff in the feedback
// panel (your answer / correct answer / legend), the placed tiles marked one
// by one, typed answers not struck through as a whole; in color and in black
// & white (pixel scan), and their layout at phone and e-reader sizes with
// large text. Plus the retry count and the retry note in a real-engine lesson.
import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/lesson/answer_diff_view.dart';
import 'package:tosk/ui/lesson/exercises/common.dart';
import 'package:tosk/ui/lesson/exercises/tile_builder_views.dart';
import 'package:tosk/ui/lesson/feedback_banner.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/theme/bw_skin.dart';
import 'package:tosk/ui/theme/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bw_helpers.dart';
import 'bw_mode_test.dart' show bwSettings, bwSizes;
import 'helpers.dart';

const _sentence = [
  TokenRef('Il', itemId: 'it:il'),
  TokenRef('ragazzo', pre: ' ', itemId: 'it:ragazzo'),
  TokenRef('mangia', pre: ' ', itemId: 'it:mangiare', form: 'presente.lui/lei'),
  TokenRef('una', pre: ' ', itemId: 'it:un'),
  TokenRef('mela', pre: ' ', itemId: 'it:mela'),
  TokenRef('.', isWord: false),
];

const _builder = SentenceBuilderExercise(
  id: 'sb',
  facetId: 'it:mela#prod',
  instruction: 'Translate this sentence',
  prompt: 'The boy eats an apple.',
  tiles: ['il', 'ragazzo', 'mangia', 'una', 'mela', 'mangio', 'pane'],
  answers: [
    ['il', 'ragazzo', 'mangia', 'una', 'mela'],
  ],
  answerTokens: _sentence,
);

/// A long one, for layout.
const _long = SentenceBuilderExercise(
  id: 'long',
  facetId: 'it:treno#prod',
  instruction: 'Translate this sentence',
  prompt: 'Tomorrow morning my grandparents take the early train to the sea with their old friends.',
  tiles: [
    'domani', 'mattina', 'i', 'miei', 'nonni', 'prendono', 'il', 'primo', 'treno', 'per', 'il', 'mare', //
    'con', 'i', 'loro', 'vecchi', 'amici', 'prende', 'ultimo',
  ],
  answers: [
    ['domani', 'mattina', 'i', 'miei', 'nonni', 'prendono', 'il', 'primo', 'treno', 'per', 'il', 'mare', 'con', 'i', 'loro', 'vecchi', 'amici'],
  ],
);

final _template = const SentenceBuilderTemplate();

Result _grade(SentenceBuilderExercise e, Answer a) => _template.grade(e, a, elapsed: const Duration(seconds: 3));

/// The exercise (tiles tapped in [order]) above the feedback panel of its
/// graded answer, like the player lays them out.
Future<Result> _show(
  WidgetTester tester, {
  required SentenceBuilderExercise exercise,
  required List<int> order,
  bool bw = false,
  Brightness brightness = Brightness.light,
  Size size = const Size(400, 900),
  double textScale = 1,
  bool typed = false,
}) async {
  setSurface(tester, size);
  final result = ValueNotifier<Result?>(null);
  Answer? draft;
  await tester.pumpWidget(
    ProviderScope(
      child: RepaintBoundary(
        key: appRootKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: bw ? bwTheme() : const ToskSkin().theme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: ValueListenableBuilder<Result?>(
            valueListenable: result,
            builder: (context, r, _) => Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SentenceBuilderView(
                        exercise: exercise,
                        result: r,
                        typed: typed,
                        onChanged: (a) => draft = a,
                      ),
                    ),
                  ),
                  if (r != null) FeedbackBanner(result: r, reduceMotion: true, onContinue: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (typed) {
    final words = [for (final i in order) exercise.tiles[i]];
    await tester.enterText(find.byType(TextField), words.join(' '));
    await tester.pump();
  } else {
    for (final i in order) {
      final tile = find.byKey(ValueKey('tile-$i'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();
    }
  }
  final graded = _grade(exercise, draft!);
  result.value = graded;
  await tester.pumpAndSettle();
  return graded;
}

/// The text spans of a diff line, by word.
Map<String, TextStyle?> _spans(WidgetTester tester, String key) {
  final out = <String, TextStyle?>{};
  final rich = tester.widget<RichText>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(RichText)).first);
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.text != null && span.text!.trim().isNotEmpty) out[span.text!] = span.style;
    return true;
  });
  return out;
}

OptionState _tileState(WidgetTester tester, int tile) => tester.widget<WordTile>(find.byKey(ValueKey('placed-$tile'))).state;

void main() {
  group('the word diff', () {
    for (final bw in [false, true]) {
      final mode = bw ? 'black & white' : 'color';
      testWidgets('$mode: one wrong word is struck through and corrected, the other tiles stay right', (tester) async {
        // il ragazzo mangio una mela
        final r = await _show(tester, exercise: _builder, order: [0, 1, 5, 3, 4], bw: bw);
        expect(r.correct, isFalse);
        expect(r.diff!.partial, isTrue);
        expect(find.byKey(const ValueKey('feedback-diff')), findsOneWidget);
        expect(find.text('Almost: 1 word to fix'), findsOneWidget);
        final given = _spans(tester, 'feedback-given');
        expect(given['mangio']?.decoration, TextDecoration.lineThrough);
        expect(given.containsKey('ragazzo'), isTrue);
        expect(given['ragazzo'], isNull, reason: 'right words are plain');
        final expected = _spans(tester, 'feedback-expected');
        expect(expected['mangia']?.decoration, TextDecoration.underline);
        expect(expected['mangia']?.fontWeight, FontWeight.w800);
        expect(find.textContaining('Struck through: wrong'), findsOneWidget);
        expect(_tileState(tester, 5), OptionState.wrong);
        for (final t in [0, 1, 3, 4]) {
          expect(_tileState(tester, t), OptionState.correct);
        }
        if (bw) await expectGrayscale(tester, 'diff: wrong word');
      });

      testWidgets('$mode: a moved word is boxed in both lines, its tile marked misplaced', (tester) async {
        // il ragazzo una mela mangia
        final r = await _show(tester, exercise: _builder, order: [0, 1, 3, 4, 2], bw: bw);
        expect(r.diff!.partial, isTrue);
        expect(find.descendant(of: find.byKey(const ValueKey('feedback-given')), matching: find.text('mangia')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('feedback-expected')), matching: find.text('mangia')), findsOneWidget);
        expect(find.textContaining('right word, wrong place'), findsOneWidget);
        expect(_tileState(tester, 2), OptionState.misplaced);
        if (bw) {
          expect(find.byIcon(Icons.swap_horiz), findsOneWidget, reason: 'the mark, not a color');
          await expectGrayscale(tester, 'diff: moved word');
        }
      });

      testWidgets('$mode: a missing word: a box where it belongs, the word underlined', (tester) async {
        // il ragazzo mangia mela
        final r = await _show(tester, exercise: _builder, order: [0, 1, 2, 4], bw: bw);
        expect(r.diff!.partial, isTrue);
        expect(find.descendant(of: find.byKey(const ValueKey('feedback-given')), matching: find.text('…')), findsOneWidget);
        expect(_spans(tester, 'feedback-expected')['una']?.decoration, TextDecoration.underline);
        expect(find.textContaining('… box: missing word'), findsOneWidget);
        if (bw) await expectGrayscale(tester, 'diff: missing word');
      });

      testWidgets('$mode: typed, the answer is not struck through as a whole', (tester) async {
        await _show(tester, exercise: _builder, order: [0, 1, 5, 3, 4], bw: bw, typed: true);
        expect(find.text('Almost: see the marked words'), findsOneWidget);
        final field = tester.widget<EditableText>(find.byType(EditableText));
        expect(field.style.decoration, isNot(TextDecoration.lineThrough));
        expect(_spans(tester, 'feedback-given')['mangio']?.decoration, TextDecoration.lineThrough);
        if (bw) await expectGrayscale(tester, 'diff: typed');
      });
    }

    testWidgets('a mostly wrong answer shows the plain correct answer', (tester) async {
      final r = await _show(tester, exercise: _builder, order: [6, 5]);
      expect(r.diff?.partial, isFalse);
      expect(find.byKey(const ValueKey('feedback-diff')), findsNothing);
      expect(find.text('Correct answer:'), findsOneWidget);
      expect(find.text('il ragazzo mangia una mela'), findsOneWidget);
      for (final t in [6, 5]) {
        expect(_tileState(tester, t), OptionState.wrong);
      }
    });

    testWidgets('AnswerDiffView alone: the count for several places', (tester) async {
      final d = diffAnswer(['il', 'ragazzo', 'mangio', 'mela'], textTokens('Il ragazzo mangia una mela.'), AccentStrictness.strict);
      expect(d.partial, isTrue);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AnswerDiffView(diff: d, foreground: Colors.black))),
      );
      expect(find.text('Almost: 2 words to fix'), findsOneWidget);
    });
  });

  group('layout', () {
    final sizes = {
      'phone 360x640': bwSizes['phone 360x640']!,
      'small phone 320x568': bwSizes['small phone 320x568']!,
      'e-reader 6in 572x772': bwSizes['e-reader 6in 572x772']!,
      'Boox 10.3in 1003x1337': bwSizes['Boox 10.3in 1003x1337']!,
    };
    for (final MapEntry(key: name, value: size) in sizes.entries) {
      for (final bw in [false, true]) {
        testWidgets('$name, ${bw ? 'black & white' : 'color'}, text 1.3: a long sentence diff fits', (tester) async {
          // Two wrong words and one left out in a 17-word sentence.
          final order = [0, 1, 2, 3, 4, 17, 6, 18, 8, 9, 10, 11, 12, 13, 14, 16];
          final r = await _show(tester, exercise: _long, order: order, bw: bw, size: size, textScale: 1.3);
          expect(r.diff!.partial, isTrue);
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('feedback-diff')), findsOneWidget);
          final continueButton = find.byKey(const ValueKey('continue-button'));
          expect(tester.getBottomLeft(continueButton).dy, lessThanOrEqualTo(size.height));
          if (bw) await expectGrayscale(tester, 'long diff $name');
        });
      }
    }

    testWidgets('dark mode, text 1.3 at 320x568', (tester) async {
      await _show(
        tester,
        exercise: _builder,
        order: [0, 1, 5, 3, 4],
        brightness: Brightness.dark,
        size: const Size(320, 568),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('feedback-diff')), findsOneWidget);
    });
  });

  group('retries in the player (real engine)', () {
    testWidgets('a wrong answer adds a retry to the count and comes back at the end with a note', (tester) async {
      await pumpApp(
        tester,
        engine: true,
        overrides: [focusPresetsProvider.overrideWith((ref) async => FocusPresets.defaults)],
        initialLocation: Routes.labPlay(skills: ['present-are'], types: [ExerciseType.conjPick], length: 2),
      );
      final first = currentExercise(tester);
      expect(find.byKey(const ValueKey('retry-count')), findsNothing);
      expect(find.byKey(const ValueKey('retry-note')), findsNothing);
      await answerCurrentNoContinue(tester, wrong: true);
      expect(find.byKey(const ValueKey('retry-count')), findsOneWidget);
      expect(find.byTooltip('1 mistake to retry'), findsOneWidget);
      await tapKey(tester, 'continue-button');
      // The second planned exercise, then the retry.
      expect(find.byKey(const ValueKey('retry-note')), findsNothing);
      await answerCurrent(tester);
      expect(find.byKey(const ValueKey('retry-note')), findsOneWidget);
      final retry = currentExercise(tester);
      expect(retry.facetId, first.facetId);
      expect(retry.type, first.type);
      expect(find.byKey(const ValueKey('retry-count')), findsNothing, reason: 'nothing else waiting');
      await answerCurrent(tester);
      expect(find.text('Session complete'), findsOneWidget);
    });

    testWidgets('black & white: the retry note and count are gray only', (tester) async {
      await pumpApp(
        tester,
        engine: true,
        size: const Size(360, 640),
        store: TestProgressStore(settings: bwSettings),
        overrides: [focusPresetsProvider.overrideWith((ref) async => FocusPresets.defaults)],
        initialLocation: Routes.labPlay(skills: ['present-are'], types: [ExerciseType.conjPick], length: 1),
      );
      await answerCurrentNoContinue(tester, wrong: true);
      await tapKey(tester, 'continue-button');
      expect(find.byKey(const ValueKey('retry-note')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectGrayscale(tester, 'retry note');
    });
  });
}
