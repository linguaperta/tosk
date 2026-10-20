// Review renders of the v0.7.1 medal work with real fonts (no `_test`
// suffix, so not in the default run):
//   QA_OUT=<dir> [QA_RATIO=2] flutter test test/qa/v071_preview.dart
// Saves the three tiers (colour, dark, black & white; large and at map
// size), the decay states, the lesson summary with a promotion (mid moment
// and settled) and the promotion's frames.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:tosk/progression/progression.dart';
import 'package:tosk/ui/map/node_painter.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/progression/session_summary_card.dart';
import 'package:tosk/ui/progression/tier_medal.dart';
import 'package:tosk/ui/theme/bw_skin.dart';
import 'package:tosk/ui/theme/skin.dart';
import 'package:tosk/ui/theme/tosk_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'brand_preview.dart' show loadQaFonts;

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa-v071');
final _ratio = double.tryParse(Platform.environment['QA_RATIO'] ?? '') ?? 2;
const _root = ValueKey('v071-root');

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_root));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _ratio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    _out.createSync(recursive: true);
    File('${_out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Widget _frame(Widget child) => RepaintBoundary(
  key: _root,
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

Widget _node(MapTier tier, MapInk ink, bool mono, double size, {double decay = 0, int seed = 7}) => CustomPaint(
  size: Size.square(size),
  painter: NodePainter(tier: tier, ink: ink, strength: 0.6, decay: decay, seed: seed, monochrome: mono),
);

const _metals = [MapTier.bronze, MapTier.silver, MapTier.gold];

SessionProgressSummary _summary() {
  const level = LevelInfo(level: 3, xpIntoLevel: 40, xpForNext: 200, totalXp: 340);
  return SessionProgressSummary(
    sessionId: 's1',
    mode: 'lesson',
    startedAt: DateTime.utc(2026, 10, 20, 9),
    endedAt: DateTime.utc(2026, 10, 20, 9, 6),
    reviews: 14,
    correct: 13,
    xpEarned: 96,
    levelBefore: level,
    levelAfter: level,
    facetChanges: const [],
    tierChanges: const [
      TierChange(skillId: 'Food', from: SkillTier.bronze, to: SkillTier.silver),
      TierChange(skillId: 'Greetings', from: SkillTier.gold, to: SkillTier.silver),
    ],
  );
}

void main() {
  setUpAll(loadQaFonts);

  testWidgets('tiers', (tester) async {
    tester.view.physicalSize = const Size(560, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget row(MapInk ink, bool mono, Color bg) => Container(
      color: bg,
      padding: const EdgeInsets.all(6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final t in _metals) _node(t, ink, mono, 120, seed: 200 + t.index),
          for (final t in _metals) _node(t, ink, mono, 48, seed: 200 + t.index),
        ],
      ),
    );
    await tester.pumpWidget(_frame(Column(children: [
      row(const ToskSkin().mapStyle(toskLightScheme()).ink, false, Tosk.paperLow),
      row(const ToskSkin().mapStyle(toskDarkScheme()).ink, false, Tosk.nightLow),
      row(kBwInk, true, kBwWhite),
    ])));
    await _shot(tester, 'tiers');
  });

  testWidgets('decay', (tester) async {
    tester.view.physicalSize = const Size(560, 440);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget row(MapTier tier, MapInk ink, bool mono, Color bg) => Container(
      color: bg,
      padding: const EdgeInsets.all(6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [for (final d in [0.0, 0.25, 0.5, 0.75, 1.0]) _node(tier, ink, mono, 96, decay: d, seed: 31)],
      ),
    );
    await tester.pumpWidget(_frame(Column(children: [
      row(MapTier.gold, MapInk.storybook, false, Tosk.paperLow),
      row(MapTier.silver, MapInk.storybook, false, Tosk.paperLow),
      row(MapTier.started, MapInk.storybook, false, Tosk.paperLow),
      row(MapTier.silver, kBwInk, true, kBwWhite),
    ])));
    await _shot(tester, 'decay');
  });

  for (final (name, theme) in [
    ('summary', const ToskSkin().theme(Brightness.light)),
    ('summary-bw', const BwSkin().theme(Brightness.light)),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(400, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget app(bool reduce) => RepaintBoundary(
        key: _root,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SessionSummaryCard(summary: _summary(), reduceMotion: reduce),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(name.endsWith('bw')));
      await tester.pump(const Duration(milliseconds: 850));
      await _shot(tester, '$name-mid');
      await tester.pumpAndSettle();
      await _shot(tester, name);
    });
  }

  testWidgets('promotion frames', (tester) async {
    tester.view.physicalSize = const Size(900, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_frame(Container(
      color: Tosk.paperLow,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final t in [0.08, 0.2, 0.4, 0.6, 1.0])
            CustomPaint(
              size: const Size(170, 190),
              painter: CelebrationPainter(
                progress: AlwaysStoppedAnimation(t),
                tier: MapTier.gold,
                ink: MapInk.storybook,
                medal: 100,
                seed: 12,
              ),
            ),
        ],
      ),
    )));
    await _shot(tester, 'promotion-frames');
  });
}
