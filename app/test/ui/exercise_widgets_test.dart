import 'package:tosk/core/core.dart';

import 'fakes/demo_exercises.dart';

import 'package:tosk/ui/lesson/answer_input.dart';
import 'package:tosk/ui/lesson/feedback_banner.dart';
import 'package:tosk/ui/lesson/exercises/cloze_view.dart';
import 'package:tosk/ui/lesson/exercises/common.dart';
import 'package:tosk/ui/lesson/exercises/conj_grid_view.dart';
import 'package:tosk/ui/lesson/exercises/conj_pick_view.dart';
import 'package:tosk/ui/lesson/exercises/flashcard_view.dart';
import 'package:tosk/ui/lesson/exercises/match_pairs_view.dart';
import 'package:tosk/ui/lesson/exercises/multiple_choice_view.dart';
import 'package:tosk/ui/lesson/exercises/spot_error_view.dart';
import 'package:tosk/ui/lesson/exercises/tile_builder_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _pool = demoExercises('it', 'en');
T _first<T extends Exercise>([bool Function(T)? where]) => _pool.whereType<T>().firstWhere(where ?? (_) => true);

/// Records what an exercise widget reports.
class Probe {
  Answer? draft;
  Answer? submitted;
  int checks = 0;
  void onChanged(Answer? a) => draft = a;
  void onSubmit(Answer a) => submitted = a;
  void onCheck() => checks++;
}

Future<void> host(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 900);
  addTearDown(tester.view.reset);
  // The default providers: the demo course (word popovers look words up there).
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> tap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump();
}

void main() {
  group('FlashcardView', () {
    testWidgets('reveal then self-grade submits a SelfGradeAnswer', (tester) async {
      final e = _first<FlashcardExercise>();
      final p = Probe();
      await host(tester, FlashcardView(exercise: e, onChanged: p.onChanged, onSubmit: p.onSubmit));
      expect(find.text(e.front), findsOneWidget);
      expect(find.byKey(const ValueKey('flashcard-back')), findsNothing);
      expect(find.byKey(const ValueKey('grade-good')), findsNothing);
      await tap(tester, 'flashcard-reveal');
      await tester.pumpAndSettle();
      expect(find.text(e.back), findsOneWidget);
      await tap(tester, 'grade-hard');
      expect((p.submitted! as SelfGradeAnswer).rating, Rating.hard);
    });

    testWidgets('keys: Enter reveals, digit grades', (tester) async {
      final keys = ExerciseKeys();
      final p = Probe();
      await host(tester, FlashcardView(exercise: _first(), onChanged: p.onChanged, onSubmit: p.onSubmit, keys: keys));
      keys.digit(3); // ignored before reveal
      await tester.pump();
      expect(p.submitted, isNull);
      keys.primary();
      await tester.pumpAndSettle();
      keys.digit(4);
      await tester.pump();
      expect((p.submitted! as SelfGradeAnswer).rating, Rating.easy);
    });
  });

  group('MultipleChoiceView', () {
    testWidgets('tap selects and reports ChoiceAnswer; result marks right and wrong', (tester) async {
      final e = _first<MultipleChoiceExercise>();
      final p = Probe();
      await host(tester, MultipleChoiceView(exercise: e, onChanged: p.onChanged));
      expect(find.text(e.prompt), findsOneWidget);
      for (final o in e.options) {
        expect(find.text(o), findsOneWidget);
      }
      await tap(tester, 'option-0');
      expect((p.draft! as ChoiceAnswer).index, 0);

      final result = Result(
        correct: false,
        expected: e.options[e.correctIndex],
        given: e.options[0],
        outcomes: const [],
      );
      await host(tester, MultipleChoiceView(exercise: e, onChanged: p.onChanged, result: result));
      final correct = tester.widget<OptionButton>(find.byKey(ValueKey('option-${e.correctIndex}')));
      expect(correct.state, OptionState.correct);
    });

    testWidgets('digit keys select options', (tester) async {
      final e = _first<MultipleChoiceExercise>();
      final keys = ExerciseKeys();
      final p = Probe();
      await host(tester, MultipleChoiceView(exercise: e, onChanged: p.onChanged, keys: keys));
      keys.digit(2);
      await tester.pump();
      expect((p.draft! as ChoiceAnswer).index, 1);
      keys.digit(9); // out of range
      await tester.pump();
      expect((p.draft! as ChoiceAnswer).index, 1);
    });
  });

  group('MatchPairsView', () {
    testWidgets('matching all pairs submits; a wrong pair flashes and is missed', (tester) async {
      final e = _first<MatchPairsExercise>();
      final p = Probe();
      await host(tester, MatchPairsView(exercise: e, onChanged: p.onChanged, onSubmit: p.onSubmit));
      final wrongRight = (e.solution[0]! + 1) % e.right.length;
      await tap(tester, 'match-left-0');
      await tap(tester, 'match-right-$wrongRight');
      expect(tester.widget<OptionButton>(find.byKey(const ValueKey('match-left-0'))).state, OptionState.wrong);
      await tester.pump(MatchPairsView.flashDuration + const Duration(milliseconds: 50));
      expect(tester.widget<OptionButton>(find.byKey(const ValueKey('match-left-0'))).state, OptionState.idle);
      for (var i = 0; i < e.left.length; i++) {
        expect(p.submitted, isNull);
        // right first for one pair: order shouldn't matter
        if (i == 1) {
          await tap(tester, 'match-right-${e.solution[i]}');
          await tap(tester, 'match-left-$i');
        } else {
          await tap(tester, 'match-left-$i');
          await tap(tester, 'match-right-${e.solution[i]}');
        }
      }
      final a = p.submitted! as MatchAnswer;
      expect(a.matches, e.solution);
      expect(a.missed, {0});
    });
  });

  group('ConjPickView', () {
    testWidgets('shows stem, person and tense; picking an ending fills the gap', (tester) async {
      final e = _first<ConjPickExercise>();
      final p = Probe();
      await host(tester, ConjPickView(exercise: e, onChanged: p.onChanged));
      expect(find.text(e.personLabel), findsOneWidget);
      expect(find.text(e.tenseLabel), findsOneWidget);
      String word() => tester.widget<Text>(find.byKey(const ValueKey('conj-pick-word'))).textSpan!.toPlainText();
      expect(word(), '${e.stem}___');
      await tap(tester, 'ending-${e.correctIndex}');
      expect((p.draft! as ChoiceAnswer).index, e.correctIndex);
      expect(word(), e.fullForm);
    });

    testWidgets('empty ending is labelled', (tester) async {
      expect(endingLabel(''), '–');
      expect(endingLabel('–'), '–');
      expect(endingLabel('iamo'), '-iamo');
    });
  });

  group('ConjGridView', () {
    testWidgets('tap cell then tile; prefilled shown; complete grid gives GridAnswer', (tester) async {
      final e = _first<ConjGridExercise>((g) => g.cells.any((c) => c.prefilled));
      final p = Probe();
      await host(tester, ConjGridView(exercise: e, onChanged: p.onChanged));
      final pre = e.cells.indexWhere((c) => c.prefilled);
      expect(find.text(e.cells[pre].expected), findsWidgets);

      final asked = [
        for (var i = 0; i < e.cells.length; i++)
          if (!e.cells[i].prefilled) i,
      ];
      // First empty cell is preselected: tapping a tile fills it.
      final firstTile = e.tiles.indexOf(e.cells[asked.first].expected);
      await tap(tester, 'grid-tile-$firstTile');
      expect(p.draft, isNull);
      // Tapping a filled cell clears it again.
      await tap(tester, 'grid-cell-${asked.first}');
      expect(find.byKey(ValueKey('grid-tile-$firstTile')), findsOneWidget);

      final used = <int>{};
      for (final i in asked) {
        final t = [for (var k = 0; k < e.tiles.length; k++) k]
            .firstWhere((k) => !used.contains(k) && e.tiles[k] == e.cells[i].expected);
        used.add(t);
        await tap(tester, 'grid-cell-$i');
        await tap(tester, 'grid-tile-$t');
      }
      final a = p.draft! as GridAnswer;
      expect(a.cells.length, e.cells.length);
      expect(a.cells[pre], '');
      for (final i in asked) {
        expect(a.cells[i], e.cells[i].expected);
      }
    });

    testWidgets('result shows per-cell marks and the expected form', (tester) async {
      final e = _first<ConjGridExercise>();
      final marks = [for (var i = 0; i < e.cells.length; i++) i != 2];
      final result = Result(correct: false, expected: '', given: '', outcomes: const [], cellCorrect: marks);
      await host(tester, ConjGridView(exercise: e, onChanged: (_) {}, result: result));
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text(e.cells[2].expected), findsWidgets);
    });
  });

  group('SentenceBuilderView / TransformView', () {
    testWidgets('tiles move to the answer line and back', (tester) async {
      final e = _first<SentenceBuilderExercise>();
      final p = Probe();
      await host(tester, SentenceBuilderView(exercise: e, onChanged: p.onChanged));
      expect(find.text(e.prompt), findsOneWidget);
      final words = e.answers.first;
      final idx = [for (final w in words) e.tiles.indexOf(w)];
      for (final t in idx) {
        await tap(tester, 'tile-$t');
      }
      expect((p.draft! as TilesAnswer).words, words);
      await tap(tester, 'placed-${idx.first}');
      expect((p.draft! as TilesAnswer).words, words.sublist(1));
      for (final t in idx.skip(1)) {
        await tap(tester, 'placed-$t');
      }
      expect(p.draft, isNull);
    });

    testWidgets('transform shows source and target, builds TilesAnswer', (tester) async {
      final e = _first<TransformExercise>();
      final p = Probe();
      await host(tester, TransformView(exercise: e, onChanged: p.onChanged));
      // The source sentence, its words tappable (the asked verb only after checking).
      expect(find.byKey(const ValueKey('source-sentence')), findsOneWidget);
      expect(find.byKey(const ValueKey('word-3')), findsOneWidget); // mela
      expect(find.byKey(const ValueKey('word-1')), findsNothing); // mangio
      expect(find.text(e.targetDescription), findsOneWidget);
      for (final w in e.answers.first) {
        await tap(tester, 'tile-${e.tiles.indexOf(w)}');
      }
      expect((p.draft! as TilesAnswer).words, e.answers.first);
    });
  });

  group('ClozeView', () {
    testWidgets('choice mode', (tester) async {
      final e = _first<ClozeExercise>((c) => c.options != null);
      final p = Probe();
      await host(tester, ClozeView(exercise: e, onChanged: p.onChanged));
      expect(find.byKey(const ValueKey('answer-input')), findsNothing);
      await tap(tester, 'cloze-option-${e.correctIndex}');
      expect((p.draft! as ChoiceAnswer).index, e.correctIndex);
      expect(find.text(e.options![e.correctIndex!]), findsWidgets); // shown in the gap too
    });

    testWidgets('text mode uses the keyboard AnswerInputWidget; Enter asks to check', (tester) async {
      final e = _first<ClozeExercise>((c) => c.options == null);
      final p = Probe();
      await host(tester, ClozeView(exercise: e, onChanged: p.onChanged, onCheck: p.onCheck));
      expect(find.byType(KeyboardAnswerField), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('answer-input')), 'Mangiamo');
      await tester.pump();
      final a = p.draft! as TextAnswer;
      expect(a.text, 'Mangiamo');
      expect(a.inputMode, InputMode.keyboard);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(p.checks, 1);
      await tester.enterText(find.byKey(const ValueKey('answer-input')), '  ');
      await tester.pump();
      expect(p.draft, isNull);
    });

    testWidgets('a custom input builder plugs in', (tester) async {
      final e = _first<ClozeExercise>((c) => c.options == null);
      AnswerInputWidget builder({
        Key? key,
        required ValueChanged<TextAnswer?> onChanged,
        VoidCallback? onSubmitted,
        bool enabled = true,
        String? hintText,
      }) => _FakeInk(onChanged: onChanged);
      final p = Probe();
      await host(tester, ClozeView(exercise: e, onChanged: p.onChanged, inputBuilder: builder));
      await tester.tap(find.byKey(const ValueKey('fake-ink')));
      await tester.pump();
      final a = p.draft! as TextAnswer;
      expect(a.inputMode, InputMode.ink);
      expect(a.candidates, ['mangiamo', 'mangiano']);
    });
  });

  group('SpotErrorView', () {
    testWidgets('tapping a word reports TokenAnswer; punctuation is not tappable', (tester) async {
      final e = _first<SpotErrorExercise>();
      final p = Probe();
      await host(tester, SpotErrorView(exercise: e, onChanged: p.onChanged));
      final punct = e.tokenIsWord.indexOf(false);
      expect(find.byKey(ValueKey('token-$punct')), findsNothing);
      await tap(tester, 'token-1');
      expect((p.draft! as TokenAnswer).index, 1);
      await tap(tester, 'token-${e.errorIndex}');
      expect((p.draft! as TokenAnswer).index, e.errorIndex);
    });

    testWidgets('result shows the correction', (tester) async {
      final e = _first<SpotErrorExercise>();
      final result = Result(correct: true, expected: e.correction, given: '', outcomes: const []);
      await host(tester, SpotErrorView(exercise: e, onChanged: (_) {}, result: result));
      expect(find.textContaining(e.correction), findsWidgets);
    });

    test('groupTokens attaches punctuation', () {
      expect(groupTokens(['¿', 'Dove', 'sei', '?'], [false, true, true, false]), [
        [0, 1],
        [2, 3],
      ]);
      expect(groupTokens(['Ciao', ',', 'Anna', '.'], [true, false, true, false]), [
        [0, 1],
        [2, 3],
      ]);
    });
  });

  testWidgets('locked widgets ignore input', (tester) async {
    final e = _first<MultipleChoiceExercise>();
    final p = Probe();
    final result = Result(correct: true, expected: '', given: '', outcomes: const []);
    await host(tester, MultipleChoiceView(exercise: e, onChanged: p.onChanged, result: result));
    await tap(tester, 'option-0');
    expect(p.draft, isNull);
  });

  group('engine fields', () {
    testWidgets('multiple choice shows the hint (article questions)', (tester) async {
      const e = MultipleChoiceExercise(
        id: 'mc',
        facetId: 'it:ragazzo#article',
        prompt: '___ ragazzo',
        options: ['il', 'lo', 'la'],
        correctIndex: 0,
        direction: Direction.produce,
        hint: 'boy',
      );
      await host(tester, MultipleChoiceView(exercise: e, onChanged: (_) {}));
      expect(find.text('___ ragazzo'), findsOneWidget);
      expect(find.text('boy'), findsOneWidget);
    });

    testWidgets('conj pick: the engine\'s no-ending option shows as – and fills nothing', (tester) async {
      const e = ConjPickExercise(
        id: 'cp',
        facetId: 'nl:werken#form:tegenwoordige_tijd',
        lemma: 'werken',
        gloss: 'to work',
        tense: 'tegenwoordige_tijd',
        tenseLabel: 'present',
        person: 'ik',
        personLabel: 'ik',
        stem: 'werk',
        endings: ['–', 't', 'en'],
        correctIndex: 0,
        fullForm: 'werk',
      );
      final p = Probe();
      await host(tester, ConjPickView(exercise: e, onChanged: p.onChanged));
      expect(find.text('–'), findsOneWidget);
      expect(find.text('-t'), findsOneWidget);
      await tap(tester, 'ending-0');
      expect((p.draft! as ChoiceAnswer).index, 0);
      final word = tester.widget<Text>(find.byKey(const ValueKey('conj-pick-word'))).textSpan!.toPlainText();
      expect(word, 'werk');
    });

    testWidgets('spot the error groups tokens by tokenPre (elision, punctuation)', (tester) async {
      const tokens = ["L'", 'acqua', 'sono', 'fredda', '.'];
      const pre = ['', '', ' ', ' ', ''];
      expect(groupTokens(tokens, const [true, true, true, true, false], pre: pre), [
        [0, 1],
        [2],
        [3, 4],
      ]);
      const e = SpotErrorExercise(
        id: 'se',
        facetId: 'it:essere#form:presente',
        tokens: tokens,
        tokenPre: pre,
        tokenIsWord: [true, true, true, true, false],
        errorIndex: 2,
        correction: 'è',
        translation: 'The water is cold.',
      );
      final p = Probe();
      await host(tester, SpotErrorView(exercise: e, onChanged: p.onChanged));
      await tap(tester, 'token-2');
      expect((p.draft! as TokenAnswer).index, 2);
      expect(find.text('The water is cold.'), findsOneWidget);
    });

    testWidgets('transform shows the translation', (tester) async {
      const e = TransformExercise(
        id: 'tr',
        facetId: 'it:mangiare#form:passato_prossimo',
        source: 'Mangio una mela.',
        targetDescription: '→ passato prossimo',
        tiles: ['Ho', 'mangiato', 'una', 'mela.'],
        answers: [
          ['Ho', 'mangiato', 'una', 'mela.'],
        ],
        translation: 'I eat an apple.',
      );
      await host(tester, TransformView(exercise: e, onChanged: (_) {}));
      expect(find.byKey(const ValueKey('transform-translation')), findsOneWidget);
      expect(find.text('I eat an apple.'), findsOneWidget);
    });

    testWidgets('an accent slip is accepted with a "watch the accent" note', (tester) async {
      const r = Result(correct: true, expected: 'città', given: 'citta', outcomes: [], accentSlip: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackBanner(result: r, onContinue: () {}, reduceMotion: true),
          ),
        ),
      );
      expect(find.text('Correct!'), findsOneWidget);
      expect(find.text('Watch the accent: città'), findsOneWidget);
    });
  });
}

class _FakeInk extends AnswerInputWidget {
  const _FakeInk({required super.onChanged});
  @override
  InputMode get inputMode => InputMode.ink;
  @override
  State<_FakeInk> createState() => _FakeInkState();
}

class _FakeInkState extends State<_FakeInk> {
  @override
  Widget build(BuildContext context) => TextButton(
    key: const ValueKey('fake-ink'),
    onPressed: () =>
        widget.onChanged(const TextAnswer('mangiamo', inputMode: InputMode.ink, candidates: ['mangiamo', 'mangiano'])),
    child: const Text('draw'),
  );
}
