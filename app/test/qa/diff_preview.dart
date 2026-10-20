// Real-font screenshots of partly right answers (the word diff) in color and
// black & white: `QA_OUT=<dir> flutter test test/qa/diff_preview.dart`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/ui/lesson/exercises/tile_builder_views.dart';
import 'package:tosk/ui/lesson/feedback_banner.dart';
import 'package:tosk/ui/theme/bw_skin.dart';
import 'package:tosk/ui/theme/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_walkthrough.dart' show loadQaFonts;

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa');
const _root = ValueKey('qa-root');

const _builder = SentenceBuilderExercise(
  id: 'sb',
  facetId: 'it:mela#prod',
  instruction: 'Translate this sentence',
  prompt: 'The boy eats an apple.',
  tiles: ['il', 'ragazzo', 'mangia', 'una', 'mela', 'mangio', 'pane'],
  answers: [
    ['il', 'ragazzo', 'mangia', 'una', 'mela'],
  ],
  answerTokens: [
    TokenRef('Il', itemId: 'it:il'),
    TokenRef('ragazzo', pre: ' ', itemId: 'it:ragazzo'),
    TokenRef('mangia', pre: ' ', itemId: 'it:mangiare', form: 'presente.lui/lei'),
    TokenRef('una', pre: ' ', itemId: 'it:un'),
    TokenRef('mela', pre: ' ', itemId: 'it:mela'),
    TokenRef('.', isWord: false),
  ],
);

Future<void> _shot(WidgetTester tester, List<int> order, {required bool bw, required String name}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 860);
  final result = ValueNotifier<Result?>(null);
  Answer? draft;
  await tester.pumpWidget(
    ProviderScope(
      child: RepaintBoundary(
        key: _root,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: bw ? bwTheme() : const ToskSkin().theme(Brightness.light),
          home: ValueListenableBuilder<Result?>(
            valueListenable: result,
            builder: (context, r, _) => Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SentenceBuilderView(key: ValueKey(name), exercise: _builder, result: r, onChanged: (a) => draft = a),
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
  for (final i in order) {
    await tester.tap(find.byKey(ValueKey('tile-$i')));
    await tester.pump();
  }
  result.value = const SentenceBuilderTemplate().grade(_builder, draft!, elapsed: const Duration(seconds: 3));
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_root));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    _out.createSync(recursive: true);
    File('${_out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('diff previews', (tester) async {
    await tester.runAsync(loadQaFonts);
    for (final bw in [false, true]) {
      final m = bw ? 'bw' : 'color';
      await _shot(tester, [0, 1, 5, 3, 4], bw: bw, name: 'diff_wrong_$m');
      await _shot(tester, [0, 1, 3, 4, 2], bw: bw, name: 'diff_moved_$m');
      await _shot(tester, [0, 1, 2, 4], bw: bw, name: 'diff_missing_$m');
    }
  });
}
