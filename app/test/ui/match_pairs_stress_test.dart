// Match pairs under fast and random tapping: the board state machine and the
// widget, against an independent model of the rules.
import 'dart:math' as math;

import 'package:tosk/core/core.dart';
import 'package:tosk/engine/templates/match_pairs.dart';
import 'package:tosk/ui/lesson/exercises/common.dart';
import 'package:tosk/ui/lesson/exercises/match_pairs_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 5-pair board with a scrambled solution.
MatchPairsExercise _exercise({int seed = 0, int n = 5}) {
  final rnd = math.Random(seed);
  final perm = List.generate(n, (i) => i)..shuffle(rnd);
  return MatchPairsExercise(
    id: 'mp$seed',
    facetId: 'it:w0#rec',
    instruction: 'Match the pairs',
    left: [for (var i = 0; i < n; i++) 'parola$i'],
    right: [for (var i = 0; i < n; i++) 'word${perm.indexOf(i)}'],
    solution: {for (var i = 0; i < n; i++) i: perm[i]},
    pairFacetIds: {for (var i = 0; i < n; i++) i: 'it:w$i#rec'},
  );
}

/// The rules written out independently of [MatchBoard].
class _Model {
  _Model(this.solution);
  final Map<int, int> solution;
  int? left, right;
  final matches = <int, int>{};
  final missed = <int>{};
  final wrong = <(int, int)>[];

  MatchTap tap(MatchSide side, int i) {
    if (matches.length == solution.length) return MatchTap.ignored;
    if (side == MatchSide.left ? matches.containsKey(i) : matches.containsValue(i)) return MatchTap.ignored;
    if (side == MatchSide.left) {
      if (left == i) {
        left = null;
        return MatchTap.deselected;
      }
      left = i;
    } else {
      if (right == i) {
        right = null;
        return MatchTap.deselected;
      }
      right = i;
    }
    if (left == null || right == null) return MatchTap.selected;
    final l = left!, r = right!;
    left = right = null;
    if (solution[l] == r) {
      matches[l] = r;
      return MatchTap.matched;
    }
    missed.add(l);
    wrong.add((l, r));
    return MatchTap.wrong;
  }
}

/// A random tap sequence: mostly sensible pairs, plus wrong pairs, repeated
/// taps, taps on matched cards and lone taps.
List<(MatchSide, int)> _randomTaps(math.Random rnd, int n, int count) => [
  for (var k = 0; k < count; k++) (rnd.nextBool() ? MatchSide.left : MatchSide.right, rnd.nextInt(n)),
];

/// Only correct pairs, in random order, either column first, with random
/// select-and-deselect noise in between (never a wrong pair).
List<(MatchSide, int)> _correctTaps(math.Random rnd, Map<int, int> solution) {
  final out = <(MatchSide, int)>[];
  final order = solution.keys.toList()..shuffle(rnd);
  for (final l in order) {
    final r = solution[l]!;
    if (rnd.nextDouble() < 0.3) {
      // Select something of one column and take it back.
      final side = rnd.nextBool() ? MatchSide.left : MatchSide.right;
      out
        ..add((side, side == MatchSide.left ? l : r))
        ..add((side, side == MatchSide.left ? l : r));
    }
    if (rnd.nextBool()) {
      out
        ..add((MatchSide.left, l))
        ..add((MatchSide.right, r));
    } else {
      out
        ..add((MatchSide.right, r))
        ..add((MatchSide.left, l));
    }
  }
  return out;
}

Future<void> _host(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
      ),
    ),
  );
  await tester.pump();
}

OptionState _cardState(WidgetTester tester, MatchSide side, int i) =>
    tester.widget<OptionButton>(find.byKey(ValueKey('match-${side.name}-$i'))).state;

void main() {
  group('MatchBoard (state machine)', () {
    test('random taps: never accepts a wrong pair, never rejects a right one, agrees with the model', () {
      for (var seed = 0; seed < 300; seed++) {
        final rnd = math.Random(seed);
        final e = _exercise(seed: seed, n: 2 + rnd.nextInt(5));
        final board = MatchBoard.of(e);
        final model = _Model(e.solution);
        for (final (side, i) in _randomTaps(rnd, e.left.length, 200)) {
          final matchedBefore = Map.of(board.matches);
          final pending = side == MatchSide.left ? board.selectedRight : board.selectedLeft;
          final what = board.tap(side, i);
          expect(what, model.tap(side, i), reason: 'seed $seed');
          if (what == MatchTap.matched || what == MatchTap.wrong) {
            final (l, r) = side == MatchSide.left ? (i, pending!) : (pending!, i);
            expect(e.solution[l] == r, what == MatchTap.matched, reason: 'seed $seed: ($l, $r)');
          }
          // Matches only grow and are always correct.
          for (final m in matchedBefore.entries) {
            expect(board.matches[m.key], m.value);
          }
          for (final m in board.matches.entries) {
            expect(e.solution[m.key], m.value);
          }
          // A matched card is never selected or flashing.
          for (var k = 0; k < e.left.length; k++) {
            if (board.isMatched(MatchSide.left, k)) {
              expect(board.isSelected(MatchSide.left, k) || board.isFlashing(MatchSide.left, k), isFalse);
            }
            if (board.isMatched(MatchSide.right, k)) {
              expect(board.isSelected(MatchSide.right, k) || board.isFlashing(MatchSide.right, k), isFalse);
            }
          }
          // Random timer expiries in between never touch a selection.
          if (rnd.nextDouble() < 0.2) {
            final selL = board.selectedLeft, selR = board.selectedRight;
            board.endFlash(rnd.nextInt(board.lastFlashId + 1));
            expect((board.selectedLeft, board.selectedRight), (selL, selR));
          }
        }
        expect(board.matches, model.matches);
        expect(board.missedLeft, model.missed);
        expect(board.wrongPairs, model.wrong);
        expect(board.missedRight, {for (final p in model.wrong) p.$2});
        if (board.done) {
          final a = board.answer();
          expect(a.matches, e.solution);
          expect(a.missed, model.missed);
          expect(a.wrongPairs, model.wrong);
        }
      }
    });

    test('correct taps in any order (with select/deselect noise) give the solution and no misses', () {
      for (var seed = 0; seed < 300; seed++) {
        final rnd = math.Random(1000 + seed);
        final e = _exercise(seed: seed);
        final board = MatchBoard.of(e);
        for (final (side, i) in _correctTaps(rnd, e.solution)) {
          expect(board.tap(side, i), isNot(MatchTap.wrong));
        }
        expect(board.done, isTrue);
        expect(board.answer().matches, e.solution);
        expect(board.answer().missed, isEmpty);
        expect(board.answer().wrongPairs, isEmpty);
      }
    });

    test('a flash ends only its own cards; tapping a flashing card selects it', () {
      final e = _exercise(seed: 3);
      final board = MatchBoard.of(e);
      final wrongR = (e.solution[0]! + 1) % 5;
      expect(board.tap(MatchSide.left, 0), MatchTap.selected);
      expect(board.tap(MatchSide.right, wrongR), MatchTap.wrong);
      final first = board.lastFlashId;
      expect(board.isFlashing(MatchSide.left, 0), isTrue);
      expect(board.isFlashing(MatchSide.right, wrongR), isTrue);
      // Re-tap the flashing word right away: selected, no longer marked.
      expect(board.tap(MatchSide.left, 0), MatchTap.selected);
      expect(board.isFlashing(MatchSide.left, 0), isFalse);
      expect(board.isSelected(MatchSide.left, 0), isTrue);
      // A second wrong pair with another word.
      final l1 = 1, wrong1 = (e.solution[1]! + 1) % 5;
      board.tap(MatchSide.left, 0); // deselect
      board.tap(MatchSide.left, l1);
      expect(board.tap(MatchSide.right, wrong1), MatchTap.wrong);
      // The first flash's timer: only its remaining card is cleared.
      board.endFlash(first);
      expect(board.isFlashing(MatchSide.right, wrongR), wrongR == wrong1);
      expect(board.isFlashing(MatchSide.left, l1), isTrue);
      // The flashing card can be matched right away and is then simply matched.
      expect(board.tap(MatchSide.right, e.solution[l1]!), MatchTap.selected);
      expect(board.tap(MatchSide.left, l1), MatchTap.matched);
      expect(board.isFlashing(MatchSide.left, l1), isFalse);
      expect(board.missedLeft, {0, l1});
      expect(board.missedRight, {wrongR, wrong1});
    });

    test('the engine grades the board answer: missed facets wrong, wrong pairs as the given text', () {
      final e = _exercise(seed: 4);
      final board = MatchBoard.of(e);
      final wrongR = (e.solution[2]! + 1) % 5;
      board
        ..tap(MatchSide.left, 2)
        ..tap(MatchSide.right, wrongR);
      for (var l = 0; l < 5; l++) {
        board
          ..tap(MatchSide.left, l)
          ..tap(MatchSide.right, e.solution[l]!);
      }
      expect(board.done, isTrue);
      final r = const MatchPairsTemplate().grade(e, board.answer(), elapsed: const Duration(seconds: 9));
      expect(r.correct, isFalse);
      expect([for (final o in r.outcomes) o.correct], [for (var i = 0; i < 5; i++) i != 2]);
      expect(r.given, '${e.left[2]} = ${e.right[wrongR]}');
      // Without mistakes everything is right.
      final clean = MatchBoard.of(e);
      for (var l = 0; l < 5; l++) {
        clean
          ..tap(MatchSide.right, e.solution[l]!)
          ..tap(MatchSide.left, l);
      }
      expect(const MatchPairsTemplate().grade(e, clean.answer(), elapsed: Duration.zero).correct, isTrue);
    });
  });

  group('MatchPairsView under fast taps', () {
    for (final reduce in [false, true]) {
      for (final pumpEach in [true, false]) {
        testWidgets('random taps (reduceMotion: $reduce, pump between taps: $pumpEach)', (tester) async {
          for (var seed = 0; seed < 12; seed++) {
            final rnd = math.Random(seed * 7 + (reduce ? 1 : 0) + (pumpEach ? 2 : 0));
            final e = _exercise(seed: seed);
            final model = _Model(e.solution);
            Answer? submitted;
            var submits = 0, selects = 0;
            await _host(
              tester,
              MatchPairsView(
                key: ValueKey('view-$seed-$reduce-$pumpEach'),
                exercise: e,
                onChanged: (_) {},
                onSubmit: (a) {
                  submitted = a;
                  submits++;
                },
                onSelect: () => selects++,
                reduceMotion: reduce,
              ),
            );
            var expectedSelects = 0;
            Future<void> doTap(MatchSide side, int i) async {
              final what = model.tap(side, i);
              if (what != MatchTap.ignored) expectedSelects++;
              await tester.tap(find.byKey(ValueKey('match-${side.name}-$i')), warnIfMissed: false);
              if (pumpEach) {
                // Sometimes mid-flash, sometimes after it.
                await tester.pump(Duration(milliseconds: rnd.nextInt(3) * 400));
                for (var k = 0; k < 5; k++) {
                  // A matched card always shows correct; a selected one selected.
                  if (model.matches.containsKey(k)) expect(_cardState(tester, MatchSide.left, k), OptionState.correct);
                  if (model.matches.containsValue(k)) {
                    expect(_cardState(tester, MatchSide.right, k), OptionState.correct);
                  }
                }
                if (model.left case final l?) expect(_cardState(tester, MatchSide.left, l), OptionState.selected);
                if (model.right case final r?) expect(_cardState(tester, MatchSide.right, r), OptionState.selected);
              }
            }

            // Random taps (wrong pairs, repeats, matched cards)...
            for (final (side, i) in _randomTaps(rnd, 5, 120)) {
              await doTap(side, i);
            }
            // ...then take back a pending selection and finish with right pairs.
            if (model.left case final l?) await doTap(MatchSide.left, l);
            if (model.right case final r?) await doTap(MatchSide.right, r);
            for (final (side, i) in _correctTaps(rnd, e.solution)) {
              await doTap(side, i);
            }
            await tester.pump(MatchPairsView.flashDuration * 2);
            expect(tester.takeException(), isNull);
            expect(model.matches.length, 5);
            expect(submits, 1);
            final a = submitted! as MatchAnswer;
            expect(a.matches, e.solution);
            expect(a.missed, model.missed);
            expect(a.wrongPairs, model.wrong);
            expect(selects, expectedSelects);
            // Tapping after the board is done does nothing.
            await tester.tap(find.byKey(const ValueKey('match-left-0')));
            await tester.pump();
            expect(submits, 1);
          }
        });
      }
    }

    testWidgets('a wrong pair marks both cards; re-tapping one selects it at once; the timer clears only that pair', (
      tester,
    ) async {
      final e = _exercise(seed: 5);
      Answer? submitted;
      await _host(tester, MatchPairsView(exercise: e, onChanged: (_) {}, onSubmit: (a) => submitted = a));
      final wrongR = (e.solution[0]! + 1) % 5;
      await tester.tap(find.byKey(const ValueKey('match-left-0')));
      await tester.tap(find.byKey(ValueKey('match-right-$wrongR')));
      await tester.pump();
      expect(_cardState(tester, MatchSide.left, 0), OptionState.wrong);
      expect(_cardState(tester, MatchSide.right, wrongR), OptionState.wrong);
      // During the flash: tap the word again, it shows as selected (not red).
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('match-left-0')));
      await tester.pump();
      expect(_cardState(tester, MatchSide.left, 0), OptionState.selected);
      expect(_cardState(tester, MatchSide.right, wrongR), OptionState.wrong);
      // The flash timer ends: the selection survives.
      await tester.pump(MatchPairsView.flashDuration);
      expect(_cardState(tester, MatchSide.left, 0), OptionState.selected);
      expect(_cardState(tester, MatchSide.right, wrongR), OptionState.idle);
      // And completes with its right meaning.
      await tester.tap(find.byKey(ValueKey('match-right-${e.solution[0]}')));
      await tester.pump();
      expect(_cardState(tester, MatchSide.left, 0), OptionState.correct);
      for (var l = 1; l < 5; l++) {
        await tester.tap(find.byKey(ValueKey('match-right-${e.solution[l]}')));
        await tester.tap(find.byKey(ValueKey('match-left-$l')));
      }
      await tester.pump();
      final a = submitted! as MatchAnswer;
      expect(a.missed, {0});
      expect(a.wrongPairs, [(0, wrongR)]);
    });

    testWidgets('reduce motion: the wrong pair stays marked until the next tap (no timer)', (tester) async {
      final e = _exercise(seed: 6);
      await _host(tester, MatchPairsView(exercise: e, onChanged: (_) {}, reduceMotion: true));
      final wrongR = (e.solution[1]! + 2) % 5;
      await tester.tap(find.byKey(ValueKey('match-right-$wrongR')));
      await tester.tap(find.byKey(const ValueKey('match-left-1')));
      await tester.pump(const Duration(seconds: 5));
      expect(_cardState(tester, MatchSide.left, 1), OptionState.wrong);
      expect(_cardState(tester, MatchSide.right, wrongR), OptionState.wrong);
      final other = (wrongR + 1) % 5;
      await tester.tap(find.byKey(ValueKey('match-right-$other')));
      await tester.pump();
      expect(_cardState(tester, MatchSide.left, 1), OptionState.idle);
      expect(_cardState(tester, MatchSide.right, wrongR), OptionState.idle);
      expect(_cardState(tester, MatchSide.right, other), OptionState.selected);
    });

    testWidgets('after checking: both cards of each wrong pair are marked, and the mix-ups are listed', (tester) async {
      final e = _exercise(seed: 7);
      final board = MatchBoard.of(e);
      final wrongR = (e.solution[3]! + 1) % 5;
      board
        ..tap(MatchSide.left, 3)
        ..tap(MatchSide.right, wrongR);
      final r = const MatchPairsTemplate().grade(e, board.answer(), elapsed: Duration.zero);
      // The view keeps its own board: play the same taps, then show the result.
      Answer? submitted;
      Widget view(Result? result) => MatchPairsView(
        key: const ValueKey('v'),
        exercise: e,
        onChanged: (_) {},
        onSubmit: (a) => submitted = a,
        result: result,
      );
      await _host(tester, view(null));
      await tester.tap(find.byKey(const ValueKey('match-left-3')));
      await tester.tap(find.byKey(ValueKey('match-right-$wrongR')));
      for (var l = 0; l < 5; l++) {
        await tester.tap(find.byKey(ValueKey('match-left-$l')));
        await tester.tap(find.byKey(ValueKey('match-right-${e.solution[l]}')));
      }
      await tester.pump();
      expect(submitted, isNotNull);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: view(r))),
          ),
        ),
      );
      await tester.pump();
      for (var k = 0; k < 5; k++) {
        expect(_cardState(tester, MatchSide.left, k), k == 3 ? OptionState.wrong : OptionState.correct);
        expect(_cardState(tester, MatchSide.right, k), k == wrongR ? OptionState.wrong : OptionState.correct);
      }
      expect(find.byKey(const ValueKey('match-mixups')), findsOneWidget);
      expect(find.text('${e.left[3]}  ≠  ${e.right[wrongR]}'), findsOneWidget);
    });
  });
}
