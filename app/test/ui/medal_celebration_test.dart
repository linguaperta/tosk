// The promotion moment on the session summary (v0.7.1): a new medal pops
// in with a shine and twinkling stars, then settles; static with reduce
// motion and in black & white (pixel-scanned); a dropped tier shows its
// medal cracked; no celebration without a new medal.
import 'package:tosk/progression/progression.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/ui/progression/progression_widgets.dart';
import 'package:tosk/ui/theme/bw_skin.dart';
import 'package:tosk/ui/theme/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bw_helpers.dart';
import 'helpers.dart';

const _root = ValueKey('summary-root');

SessionProgressSummary _summary(List<TierChange> changes) {
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
    tierChanges: changes,
  );
}

const _promoted = [
  TierChange(skillId: 'food', from: SkillTier.bronze, to: SkillTier.silver),
  TierChange(skillId: 'greetings', from: SkillTier.gold, to: SkillTier.silver),
  TierChange(skillId: 'travel', from: SkillTier.started, to: SkillTier.bronze),
];

Widget _card(List<TierChange> changes, {bool bw = false, bool dark = false, bool reduceMotion = false}) => RepaintBoundary(
  key: _root,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: bw ? const BwSkin().theme(Brightness.light) : const ToskSkin().theme(dark ? Brightness.dark : Brightness.light),
    home: Scaffold(
      body: SingleChildScrollView(
        child: SessionSummaryCard(
          summary: _summary(changes),
          reduceMotion: reduceMotion,
          skillLabel: (id) => id[0].toUpperCase() + id.substring(1),
        ),
      ),
    ),
  ),
);

CelebrationPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(of: find.byKey(const ValueKey('medal-celebration')), matching: find.byType(CustomPaint)))
    .map((p) => p.painter)
    .whereType<CelebrationPainter>()
    .single;

void main() {
  testWidgets('a promotion celebrates the best new medal, then settles and stops ticking', (tester) async {
    setSurface(tester, const Size(400, 900));
    await tester.pumpWidget(_card(_promoted));
    expect(find.byKey(const ValueKey('medal-celebration')), findsOneWidget);
    expect(find.text('Silver medal'), findsOneWidget, reason: 'silver beats the new bronze');
    expect(find.text('Food, up from Bronze'), findsOneWidget);
    expect(find.bySemanticsLabel('New medal: Silver, Food'), findsOneWidget);
    final p = _painter(tester);
    expect(p.progress.value, lessThan(0.1));
    await tester.pump(const Duration(milliseconds: 900));
    expect(p.progress.value, inExclusiveRange(0.3, 0.7), reason: 'mid moment: shine and stars');
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(p.progress.value, 1);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
    // The rows show the storybook medals; the dropped one is cracked.
    expect(find.bySemanticsLabel('Silver medal, cracked'), findsOneWidget);
    expect(find.bySemanticsLabel('Gold medal'), findsOneWidget);
  });

  testWidgets('with reduce motion it is the settled picture from the start', (tester) async {
    setSurface(tester, const Size(400, 900));
    await tester.pumpWidget(_card(_promoted, reduceMotion: true));
    expect(_painter(tester).progress, kAlwaysCompleteAnimation);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('black & white: static, and only black, white and gray', (tester) async {
    setSurface(tester, const Size(400, 900));
    await tester.pumpWidget(_card(_promoted, bw: true));
    expect(_painter(tester).progress, kAlwaysCompleteAnimation, reason: 'no motion on e-ink');
    await expectGrayscale(tester, 'summary with a promotion', root: find.byKey(_root));
    // The medal letters on the small medals.
    expect(find.text('S'), findsWidgets);
  });

  testWidgets('no celebration without a new medal (only drops, unlocks, starts)', (tester) async {
    setSurface(tester, const Size(400, 900));
    await tester.pumpWidget(_card(const [
      TierChange(skillId: 'food', from: SkillTier.gold, to: SkillTier.silver),
      TierChange(skillId: 'travel', from: SkillTier.available, to: SkillTier.started),
      TierChange(skillId: 'time', from: SkillTier.locked, to: SkillTier.available),
    ]));
    expect(find.byKey(const ValueKey('medal-celebration')), findsNothing);
    expect(find.bySemanticsLabel('Silver medal, cracked'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  // The e-ink harness sizes (see bw_mode_test): pixel scan and no overflow.
  for (final size in const [Size(320, 568), Size(572, 772), Size(674, 896), Size(1003, 1337)]) {
    testWidgets('black & white at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      setSurface(tester, size);
      await tester.pumpWidget(_card(_promoted, bw: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectGrayscale(tester, 'summary at $size', root: find.byKey(_root));
    });
  }

  for (final bw in [false, true]) {
    testWidgets('the skill sheet shows the skill\'s stone, cracked when fading (${bw ? 'black & white' : 'colour'})', (tester) async {
      await pumpApp(
        tester,
        size: const Size(400, 900),
        store: TestProgressStore(settings: {if (bw) SettingKeys.display: 'bw'}),
        initialLocation: Routes.skill('present-are'),
        overrides: [
          skillStatsProvider.overrideWith((ref) async => {
            'present-are': SkillStats(tier: MapTier.silver, strength: 0.6, fading: 0.8, lastPracticed: testNow.subtract(const Duration(days: 20))),
          }),
        ],
      );
      expect(find.byKey(const ValueKey('skill-medal')), findsOneWidget);
      expect(find.bySemanticsLabel('Silver, fading'), findsOneWidget);
      if (bw) await expectGrayscale(tester, 'skill sheet with a cracked medal');
    });
  }

  for (final (name, size, dark) in [('phone', Size(320, 568), false), ('dark', Size(360, 640), true), ('desktop', Size(1280, 800), false)]) {
    testWidgets('no overflow: $name', (tester) async {
      setSurface(tester, size);
      await tester.pumpWidget(_card(_promoted, dark: dark));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final box = tester.renderObject<RenderBox>(find.byKey(const ValueKey('medal-celebration')));
      expect(box.size.width, lessThanOrEqualTo(size.width));
    });
  }
}
