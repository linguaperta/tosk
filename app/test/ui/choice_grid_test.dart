// Option grids (`ChoiceGrid`): every tile of a grid the same width and
// height, the full width of the player's column, no word broken over lines
// (labels shrink to 85 %, then the grid drops to one column), 48 px targets,
// number badges, and the right/wrong looks in color and black & white.
// Phones (320, 360, 412 px), the e-readers and the Boox 10.3", text 1.0, 1.3
// and 1.5, with long and multi-word options. Rendered in Roboto (the Android
// UI font, from the Flutter SDK's cache) instead of the test font, whose
// glyphs are a full em wide: word widths then say what a phone shows.
import 'dart:io';
import 'dart:math' as math;

import 'package:tosk/core/core.dart';
import 'package:tosk/speech/speaker.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/lesson/exercises/choice_grid.dart';
import 'package:tosk/ui/lesson/exercises/cloze_view.dart';
import 'package:tosk/ui/lesson/exercises/common.dart';
import 'package:tosk/ui/lesson/exercises/conj_pick_view.dart';
import 'package:tosk/ui/lesson/exercises/listen_pick_view.dart';
import 'package:tosk/ui/lesson/exercises/match_pairs_view.dart';
import 'package:tosk/ui/lesson/exercises/multiple_choice_view.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/theme/bw_skin.dart';
import 'package:tosk/ui/theme/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bw_helpers.dart';
import 'helpers.dart';

/// Phones and the e-readers (`bwSizes` in bw_mode_test), in logical pixels.
const gridSizes = {
  'small phone 320x568': Size(320, 568),
  'phone 360x640': Size(360, 640),
  'phone 412x915': Size(412, 915),
  'e-reader 6in 572x772': Size(572, 772),
  'e-reader 7in 674x896': Size(674, 896),
  'Boox 10.3in 1003x1337': Size(1003, 1337),
};

const textScales = [1.0, 1.3, 1.5];

/// Option sets: the reported one, long single words, multi-word phrases.
const optionSets = {
  'reported': ['Buonasera', 'Ciao', 'Prego', 'Scusa'],
  'long words': ['Arrivederci', 'sfortunatamente', 'Buongiorno', 'Grazie'],
  'phrases': ['per favore', 'a domani', 'molto bene grazie', 'buona notte a tutti'],
};

ClozeExercise cloze(List<String> options, {int correct = 0}) => ClozeExercise(
  id: 'cl',
  facetId: 'it:x#form',
  instruction: 'Fill in the gap',
  before: '',
  after: ', Tom.',
  expected: options[correct],
  accepted: [options[correct]],
  options: options,
  correctIndex: correct,
  hint: 'good evening',
  translation: 'Good evening, Tom.',
);

/// Hosts [child] the way the player does: a scroll view with 16 px sides,
/// centered and at most 640 px wide.
Future<void> hostLike(
  WidgetTester tester,
  Widget child, {
  required Size size,
  double textScale = 1,
  bool bw = false,
  Brightness brightness = Brightness.light,
}) async {
  setSurface(tester, size);
  await tester.pumpWidget(
    ProviderScope(
      child: RepaintBoundary(
        key: appRootKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: bw ? bwTheme() : const ToskSkin().theme(brightness),
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: c!,
          ),
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, c) {
                final side = math.max(16.0, (c.maxWidth - 640) / 2);
                return SingleChildScrollView(padding: EdgeInsets.fromLTRB(side, 12, side, 16), child: child);
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The player column's content width at [width].
double contentWidth(double width) => width - 2 * math.max(16.0, (width - 640) / 2);

/// The label paragraph of the option with [key].
RenderParagraph labelOf(WidgetTester tester, String key, String label) {
  final f = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == label),
  );
  expect(f, findsOneWidget, reason: 'label "$label" of $key');
  return tester.renderObject<RenderParagraph>(f);
}

/// The number of lines [label] takes in [p].
int linesOf(RenderParagraph p, String label) =>
    {for (final b in p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: label.length))) b.top.round()}
        .length;

/// Every word of [label] sits on one line of its paragraph.
void expectWordsUnbroken(RenderParagraph p, String label, {String what = ''}) {
  for (final m in RegExp(r'\S+').allMatches(label)) {
    final boxes = p.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end));
    final tops = {for (final b in boxes) b.top.round()};
    expect(tops, hasLength(1), reason: '$what: "${m[0]}" of "$label" breaks over ${tops.length} lines');
  }
}

/// Checks a grid of options keyed [keys] with [labels]: equal tiles (equal
/// heights unless [uniform] is false), at least 48 px, inside the screen,
/// spanning the content width, no word broken, no layout error. Returns the
/// number of columns.
int expectGrid(
  WidgetTester tester, {
  required List<String> keys,
  required List<String> labels,
  required double width,
  bool uniform = true,
  bool numbered = true,
  String what = '',
}) {
  expect(tester.takeException(), isNull, reason: what);
  final rects = [for (final k in keys) tester.getRect(find.byKey(ValueKey(k)))];
  final first = rects.first;
  for (var i = 0; i < rects.length; i++) {
    final r = rects[i];
    expect(r.width, moreOrLessEquals(first.width, epsilon: 0.01), reason: '$what: width of ${keys[i]}');
    if (uniform) expect(r.height, moreOrLessEquals(first.height, epsilon: 0.01), reason: '$what: height of ${keys[i]}');
    expect(r.height, greaterThanOrEqualTo(48), reason: '$what: ${keys[i]} is a 48 px target');
    expect(r.left, greaterThanOrEqualTo(0), reason: what);
    expect(r.right, lessThanOrEqualTo(width + 0.01), reason: what);
    expectWordsUnbroken(labelOf(tester, keys[i], labels[i]), labels[i], what: what);
    if (numbered) {
      expect(
        find.descendant(of: find.byKey(ValueKey(keys[i])), matching: find.text('${i + 1}')),
        findsOneWidget,
        reason: '$what: badge ${i + 1}',
      );
    }
  }
  // Same-row tiles share a top; the grid spans the column.
  final columns = {for (final r in rects) r.left.round()}.length;
  final grid = tester.getRect(find.byKey(const ValueKey('choice-grid')).first);
  expect(grid.width, moreOrLessEquals(contentWidth(width), epsilon: 0.5), reason: '$what: grid uses the width');
  if (columns == 1) {
    expect(first.width, moreOrLessEquals(contentWidth(width), epsilon: 0.5), reason: '$what: full-width tiles');
  } else {
    final minLeft = rects.map((r) => r.left).reduce(math.min);
    final maxRight = rects.map((r) => r.right).reduce(math.max);
    expect(minLeft, moreOrLessEquals(grid.left, epsilon: 0.5), reason: '$what: first column at the left edge');
    expect(maxRight, moreOrLessEquals(grid.right, epsilon: 0.5), reason: '$what: last column at the right edge');
  }
  return columns;
}

/// The tiles' rects relative to their grid (the prompt above may grow when
/// the gap shows the picked option).
List<Rect> tileRects(WidgetTester tester, List<String> keys) {
  final origin = tester.getTopLeft(find.byKey(const ValueKey('choice-grid')).first);
  return [for (final k in keys) tester.getRect(find.byKey(ValueKey(k))).shift(-origin)];
}

Future<void> tapOption(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

double scaleOf(WidgetTester tester, String key) => tester.widget<OptionButton>(find.byKey(ValueKey(key))).textScale;

/// Loads Roboto (regular, medium, bold) and the Material icons from the SDK.
Future<void> loadRoboto() async {
  // Copies in test/fonts (CI has no SDK font cache); the SDK's as a fallback.
  final dir = Directory('test/fonts').existsSync()
      ? 'test/fonts'
      : '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String name) async => ByteData.sublistView(File('$dir/$name').readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final n in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
    roboto.addFont(f(n));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(f('materialicons-regular.otf'))).load();
}

void main() {
  setUpAll(loadRoboto);

  group('planChoiceGrid', () {
    const style = TextStyle(fontFamily: 'FlutterTest', fontSize: 10);
    double measure(String s) {
      final p = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = p.maxIntrinsicWidth;
      p.dispose();
      return w;
    }

    const chrome = 20.0;
    // Width at which a [word]-wide label just fits a 2-column tile at [scale].
    double widthFor(double word, double scale) => 2 * (word * scale + chrome) + kChoiceSpacing;

    test('fits: two columns at full size', () {
      final w = measure('abcdefghij');
      final plan = planChoiceGrid(
        width: widthFor(w, 1) + 1,
        labels: ['abcdefghij', 'ab', 'cd', 'ef'],
        style: style,
        chrome: chrome,
      );
      expect(plan, const ChoiceGridPlan(2, 1));
    });

    test('the longest word shrinks the whole grid a little', () {
      final w = measure('abcdefghij');
      final plan = planChoiceGrid(
        width: widthFor(w, 0.92),
        labels: ['abcdefghij', 'ab', 'cd', 'ef'],
        style: style,
        chrome: chrome,
      );
      expect(plan, const ChoiceGridPlan(2, 0.9));
    });

    test('below 85 % the grid drops to one column', () {
      final w = measure('abcdefghij');
      final plan = planChoiceGrid(
        width: widthFor(w, 0.8),
        labels: ['abcdefghij', 'ab', 'cd', 'ef'],
        style: style,
        chrome: chrome,
      );
      expect(plan, const ChoiceGridPlan(1, 1));
    });

    test('a board that keeps its columns shrinks further first', () {
      final w = measure('abcdefghij');
      final plan = planChoiceGrid(
        width: widthFor(w, 0.77),
        labels: ['abcdefghij', 'ab', 'cd', 'ef'],
        style: style,
        chrome: chrome,
        keepColumns: true,
      );
      expect(plan, const ChoiceGridPlan(2, 0.75));
      // Below 75 % it stacks: one column, full size.
      final stacked = planChoiceGrid(
        width: widthFor(w, 0.7),
        labels: ['abcdefghij', 'ab', 'cd', 'ef'],
        style: style,
        chrome: chrome,
        keepColumns: true,
      );
      expect(stacked, const ChoiceGridPlan(1, 1));
    });

    test('words break only between words: a long phrase wraps, its words fit', () {
      final w = measure('abcde');
      final plan = planChoiceGrid(
        width: widthFor(w, 1) + 1,
        labels: ['abcde abcde', 'ab', 'cd', 'ef'],
        style: style,
        chrome: chrome,
      );
      expect(plan, const ChoiceGridPlan(2, 1));
    });

    test('a label over three lines drops the grid to one column', () {
      final w = measure('abcde');
      final plan = planChoiceGrid(
        width: widthFor(w, 1) + 1,
        labels: ['abcde abcde abcde abcde', 'ab', 'cd', 'ef'],
        style: style,
        chrome: chrome,
      );
      expect(plan.columns, 1);
    });

    test('one column shrinks as far as needed, not below 50 %', () {
      final w = measure('abcdefghij');
      // One column of width w * 0.62 + chrome.
      final one = planChoiceGrid(width: w * 0.62 + chrome, labels: ['abcdefghij', 'ab'], style: style, chrome: chrome);
      expect(one, const ChoiceGridPlan(1, 0.6));
      final none = planChoiceGrid(width: w * 0.3 + chrome, labels: ['abcdefghij', 'ab'], style: style, chrome: chrome);
      expect(none, const ChoiceGridPlan(1, 0.5));
    });

    test('one option, one column', () {
      expect(planChoiceGrid(width: 400, labels: ['a'], style: style, chrome: chrome).columns, 1);
    });
  });

  group('cloze grid', () {
    for (final size in gridSizes.entries) {
      for (final scale in textScales) {
        for (final set in optionSets.entries) {
          final options = set.value;
          final keys = [for (var i = 0; i < options.length; i++) 'cloze-option-$i'];
          final what = '${size.key}, text $scale, ${set.key}';
          testWidgets(what, (tester) async {
            final e = cloze(options);
            Widget view(Result? r) => ClozeView(exercise: e, onChanged: (_) {}, result: r);

            // Color, light.
            await hostLike(tester, view(null), size: size.value, textScale: scale);
            final cols = expectGrid(tester, keys: keys, labels: options, width: size.value.width, what: '$what color');
            final s = scaleOf(tester, keys.first);
            expect(s, greaterThanOrEqualTo(cols == 1 ? 0.6 : 0.85), reason: what);
            for (final k in keys) {
              expect(scaleOf(tester, k), s, reason: '$what: one scale per grid');
            }
            // A selection doesn't move or resize anything.
            final before = tileRects(tester, keys);
            await tapOption(tester, keys[1]);
            expect(tileRects(tester, keys), before, reason: '$what selected');
            expect(tester.widget<OptionButton>(find.byKey(ValueKey(keys[1]))).state, OptionState.selected);

            // Black & white, before and after checking (✓ / ✗ marks, bold
            // right answer): same grid, nothing re-wraps, all gray.
            await hostLike(tester, view(null), size: size.value, textScale: scale, bw: true);
            final bwCols = expectGrid(tester, keys: keys, labels: options, width: size.value.width, what: '$what bw');
            await tapOption(tester, keys[1]);
            await expectGrayscale(tester, '$what bw selected');
            final bwBefore = tileRects(tester, keys);
            await hostLike(
              tester,
              view(Result(correct: false, expected: options[0], given: options[1], outcomes: const [])),
              size: size.value,
              textScale: scale,
              bw: true,
            );
            expect(tester.widget<OptionButton>(find.byKey(ValueKey(keys[0]))).state, OptionState.correct);
            expect(tester.widget<OptionButton>(find.byKey(ValueKey(keys[1]))).state, OptionState.wrong);
            expect(
              expectGrid(tester, keys: keys, labels: options, width: size.value.width, what: '$what bw checked'),
              bwCols,
            );
            expect(tileRects(tester, keys), bwBefore, reason: '$what checked');
            expect(find.byIcon(Icons.check), findsWidgets);
            expect(find.byIcon(Icons.close), findsWidgets);
            await expectGrayscale(tester, '$what bw checked');
          });
        }
      }
    }

    testWidgets('the reported screen: 412 px phone, dark, the grid spans the column', (tester) async {
      final e = cloze(optionSets['reported']!);
      await hostLike(
        tester,
        ClozeView(exercise: e, onChanged: (_) {}),
        size: const Size(412, 915),
        brightness: Brightness.dark,
      );
      final keys = [for (var i = 0; i < 4; i++) 'cloze-option-$i'];
      // 2 x 2 at full size, each tile half the 380 px column (the old chips
      // were 140 px, centered, and broke "Buonaser|a").
      expect(expectGrid(tester, keys: keys, labels: optionSets['reported']!, width: 412, what: 'reported'), 2);
      expect(scaleOf(tester, keys.first), 1);
      expect(
        tester.getRect(find.byKey(const ValueKey('cloze-option-0'))),
        const Rect.fromLTWH(
          16,
          0,
          185,
          48,
        ).shift(Offset(0, tester.getTopLeft(find.byKey(const ValueKey('cloze-option-0'))).dy)),
      );
      expect(linesOf(labelOf(tester, keys.first, 'Buonasera'), 'Buonasera'), 1);
    });

    testWidgets('text 1.5 on a 412 px phone: still two columns, one line each', (tester) async {
      final e = cloze(optionSets['reported']!);
      await hostLike(
        tester,
        ClozeView(exercise: e, onChanged: (_) {}),
        size: const Size(412, 915),
        textScale: 1.5,
      );
      final keys = [for (var i = 0; i < 4; i++) 'cloze-option-$i'];
      expect(expectGrid(tester, keys: keys, labels: optionSets['reported']!, width: 412, what: 'reported 1.5'), 2);
      expect(linesOf(labelOf(tester, keys.first, 'Buonasera'), 'Buonasera'), 1);
    });

    testWidgets('three options: the lone last tile is centered, same size', (tester) async {
      final e = cloze(['Ciao', 'Prego', 'Scusa']);
      await hostLike(
        tester,
        ClozeView(exercise: e, onChanged: (_) {}),
        size: const Size(1003, 1337),
      );
      final keys = [for (var i = 0; i < 3; i++) 'cloze-option-$i'];
      expectGrid(tester, keys: keys, labels: const ['Ciao', 'Prego', 'Scusa'], width: 1003, what: 'three');
      final grid = tester.getRect(find.byKey(const ValueKey('choice-grid')));
      expect(tester.getRect(find.byKey(const ValueKey('cloze-option-2'))).center.dx, moreOrLessEquals(grid.center.dx));
    });

    testWidgets('number keys still pick options', (tester) async {
      final keys = ExerciseKeys();
      Answer? draft;
      await hostLike(
        tester,
        ClozeView(exercise: cloze(optionSets['reported']!), onChanged: (a) => draft = a, keys: keys),
        size: const Size(360, 640),
      );
      keys.digit(3);
      await tester.pump();
      expect((draft! as ChoiceAnswer).index, 2);
    });
  });

  group('conjugation endings', () {
    for (final size in [const Size(320, 568), const Size(412, 915), const Size(1003, 1337)]) {
      for (final scale in textScales) {
        testWidgets('${size.width.round()} px, text $scale', (tester) async {
          const endings = ['iamo', 'ate', 'ano', kNoEndingLabelTest];
          final e = ConjPickExercise(
            id: 'cp',
            facetId: 'it:mangiare#form:presente',
            instruction: 'Pick the right ending',
            lemma: 'mangiare',
            gloss: 'to eat',
            tense: 'presente',
            tenseLabel: 'present',
            person: 'noi',
            personLabel: 'noi',
            stem: 'mang',
            endings: endings,
            correctIndex: 0,
            fullForm: 'mangiamo',
          );
          final labels = [for (final x in endings) endingLabel(x)];
          final keys = [for (var i = 0; i < 4; i++) 'ending-$i'];
          for (final bw in [false, true]) {
            await hostLike(
              tester,
              ConjPickView(exercise: e, onChanged: (_) {}),
              size: size,
              textScale: scale,
              bw: bw,
            );
            expectGrid(tester, keys: keys, labels: labels, width: size.width, what: 'conj bw=$bw');
            if (bw) await expectGrayscale(tester, 'conj pick');
          }
        });
      }
    }
  });

  group('match pairs', () {
    const left = ['sfortunatamente', 'Arrivederci', 'Buonasera', 'ciao'];
    const right = ['hi', 'unfortunately', 'goodbye for now', 'good evening'];
    final e = MatchPairsExercise(
      id: 'mp',
      facetId: 'it:a',
      instruction: 'Match the pairs',
      left: left,
      right: right,
      solution: const {0: 1, 1: 2, 2: 3, 3: 0},
      pairFacetIds: const {0: 'a', 1: 'b', 2: 'c', 3: 'd'},
    );
    for (final size in gridSizes.entries) {
      for (final scale in textScales) {
        testWidgets('${size.key}, text $scale', (tester) async {
          for (final bw in [false, true]) {
            await hostLike(
              tester,
              MatchPairsView(exercise: e, onChanged: (_) {}),
              size: size.value,
              textScale: scale,
              bw: bw,
            );
            expect(tester.takeException(), isNull);
            final lk = [for (var i = 0; i < 4; i++) 'match-left-$i'];
            final rk = [for (var i = 0; i < 4; i++) 'match-right-$i'];
            final all = [...lk, ...rk];
            final labels = [...left, ...right];
            final rects = tileRects(tester, all);
            for (var i = 0; i < all.length; i++) {
              expect(rects[i].size, rects.first.size, reason: '${all[i]} same card size');
              expect(rects[i].height, greaterThanOrEqualTo(48));
              expectWordsUnbroken(labelOf(tester, all[i], labels[i]), labels[i], what: '${size.key} $scale bw=$bw');
            }
            final stacked = rects[4].left == rects[0].left;
            if (stacked) {
              // Too long for half the width even at 75 %: left words, then
              // right words, full width. Not on a phone at text 1.0.
              expect(scale > 1 || size.value.width < 360, isTrue, reason: '${size.key} $scale stacked');
              for (var i = 1; i < 8; i++) {
                expect(rects[i].top, greaterThan(rects[i - 1].bottom));
              }
              expect(rects[0].width, moreOrLessEquals(contentWidth(size.value.width), epsilon: 0.5));
              // A wider gap between the left and the right words.
              expect(rects[4].top - rects[3].bottom, greaterThan(rects[1].top - rects[0].bottom));
            } else {
              for (var i = 0; i < 4; i++) {
                // Left words on the left, rows aligned with the right column.
                expect(rects[i].left, rects[0].left);
                expect(rects[4 + i].left, rects[4].left);
                expect(rects[4 + i].left, greaterThan(rects[i].right));
                expect(rects[4 + i].top, rects[i].top);
              }
              expect(rects[4].right - rects[0].left, moreOrLessEquals(contentWidth(size.value.width), epsilon: 0.5));
            }
            if (bw) {
              await tester.tap(find.byKey(const ValueKey('match-left-0')));
              await tester.tap(find.byKey(const ValueKey('match-right-1')));
              await tester.pumpAndSettle();
              expect(
                tester.widget<OptionButton>(find.byKey(const ValueKey('match-left-0'))).state,
                OptionState.correct,
              );
              expect(tileRects(tester, all), rects, reason: 'a match moves nothing');
              await expectGrayscale(tester, 'match pairs');
            }
          }
        });
      }
    }
  });

  group('lists (multiple choice, listen and pick)', () {
    const options = ['sfortunatamente', 'Arrivederci, ci vediamo domani', 'Buonasera a tutti', 'Ciao'];
    final mc = MultipleChoiceExercise(
      id: 'mc',
      facetId: 'it:a#rec',
      instruction: 'Pick the translation',
      prompt: 'unfortunately',
      options: options,
      correctIndex: 0,
      direction: Direction.produce,
    );
    final lp = ListenPickExercise(
      id: 'lp',
      facetId: 'it:a#listen',
      instruction: 'What do you hear?',
      text: options[0],
      languageCode: 'it',
      options: options,
      correctIndex: 0,
    );
    final keys = [for (var i = 0; i < 4; i++) 'option-$i'];
    for (final size in [const Size(320, 568), const Size(412, 915), const Size(572, 772), const Size(1003, 1337)]) {
      for (final scale in textScales) {
        testWidgets('${size.width.round()} px, text $scale', (tester) async {
          for (final bw in [false, true]) {
            await hostLike(
              tester,
              MultipleChoiceView(exercise: mc, onChanged: (_) {}),
              size: size,
              textScale: scale,
              bw: bw,
            );
            expect(
              expectGrid(tester, keys: keys, labels: options, width: size.width, uniform: false, what: 'mc bw=$bw'),
              1,
            );
            await hostLike(
              tester,
              ListenPickView(exercise: lp, onChanged: (_) {}, speaker: const NullSpeaker(), autoplay: false),
              size: size,
              textScale: scale,
              bw: bw,
            );
            expect(
              expectGrid(tester, keys: keys, labels: options, width: size.width, uniform: false, what: 'listen bw=$bw'),
              1,
            );
            if (bw) await expectGrayscale(tester, 'listen pick');
          }
        });
      }
    }
  });

  testWidgets('in the player: the cloze grid spans the column at 412 px', (tester) async {
    final allSkills = buildDemoItalian().skills.map((s) => s.id).toList();
    await pumpApp(
      tester,
      size: const Size(412, 915),
      initialLocation: Routes.labPlay(skills: allSkills, types: [ExerciseType.cloze], length: 1),
    );
    final e = currentExercise(tester) as ClozeExercise;
    final keys = [for (var i = 0; i < e.options!.length; i++) 'cloze-option-$i'];
    expectGrid(tester, keys: keys, labels: e.options!, width: 412, what: 'player');
  });
}

/// The empty ending, as the engine sends it.
const kNoEndingLabelTest = '–';
