// Review screenshots of topic trees with real fonts (no `_test` suffix, so not
// in the default run):
//   QA_OUT=<dir> [QA_RATIO=1] flutter test test/qa/topics_preview.dart
// Saves the main tree with its topic branches (colour, dark, black & white;
// 320 dp, phone and desktop), a close-up of a carving, a topic's tree, and
// the tree selector open. The committed renders are in docs/screenshots/topics/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/map/skill_map_view.dart' show MapPlan, SkillMapView;
import 'package:tosk/ui/map/topic_branch.dart' show BranchPlan;
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

import '../fixtures/topic_course.dart';
import '../ui/helpers.dart';
import 'brand_preview.dart' show loadQaFonts;

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa-topics');
final _ratio = double.tryParse(Platform.environment['QA_RATIO'] ?? '') ?? 2;

Future<void> _shot(WidgetTester tester, String name, {Rect? crop}) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(appRootKey));
  await tester.runAsync(() async {
    var image = await boundary.toImage(pixelRatio: _ratio);
    if (crop != null) {
      final rec = ui.PictureRecorder();
      final r = Rect.fromLTRB(crop.left * _ratio, crop.top * _ratio, crop.right * _ratio, crop.bottom * _ratio);
      Canvas(rec).drawImageRect(image, r, Offset.zero & r.size, Paint());
      image = await rec.endRecording().toImage(r.width.round(), r.height.round());
    }
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    _out.createSync(recursive: true);
    File('${_out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// The learner is in unit 2: Food basics started (its topic is open), the
/// end of the tree still locked (Travel's branch looks locked).
Map<String, SkillStats> topicStats() => {
  'greetings': SkillStats(tier: MapTier.gold, strength: 0.95, lastPracticed: testNow.subtract(const Duration(days: 1))),
  'people': SkillStats(tier: MapTier.silver, strength: 0.8, lastPracticed: testNow.subtract(const Duration(days: 2))),
  'numbers': SkillStats(tier: MapTier.bronze, strength: 0.6, lastPracticed: testNow.subtract(const Duration(days: 3))),
  'food-basics': SkillStats(tier: MapTier.started, strength: 0.4, lastPracticed: testNow, practicedFacets: 3, totalFacets: 8),
  'home': const SkillStats(tier: MapTier.available),
  'time': const SkillStats(tier: MapTier.available),
  'city': const SkillStats(tier: MapTier.locked),
  'work': const SkillStats(tier: MapTier.locked),
  'city-life': const SkillStats(tier: MapTier.locked),
  'cooking': SkillStats(tier: MapTier.started, strength: 0.3, lastPracticed: testNow, practicedFacets: 2, totalFacets: 10),
  'market': const SkillStats(tier: MapTier.available),
  'restaurant': const SkillStats(tier: MapTier.locked),
  'recipes': const SkillStats(tier: MapTier.locked),
  'station': const SkillStats(tier: MapTier.locked),
  'hotel': const SkillStats(tier: MapTier.locked),
  'sights': const SkillStats(tier: MapTier.locked),
};

Future<void> _pump(WidgetTester tester, Size size, Map<String, String> settings) => pumpApp(
  tester,
  size: size,
  store: TestProgressStore(settings: {SettingKeys.coursesAdded: 'it', ...settings}),
  overrides: [
    courseCatalogProvider.overrideWithValue(TopicCourseCatalog()),
    skillStatsProvider.overrideWith((ref) async => topicStats()),
  ],
);

/// Topic [id]'s branch plan on the main map.
BranchPlan topicBranchPlan(WidgetTester tester, String id) =>
    ((tester.state(find.byType(SkillMapView)) as dynamic).plan as MapPlan).branches.firstWhere((b) => b.branch.id == id);

/// Where topic [id]'s branch is tapped (the middle of its carving), on screen.
Offset topicTapPoint(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(const ValueKey('map-content'))) + topicBranchPlan(tester, id).tapPoint;

/// Scrolls the main map so topic [id]'s carving sits [above] px from the top.
Future<void> scrollToTopicBranch(WidgetTester tester, String id, {required double above}) async {
  await tester.ensureVisible(find.byKey(ValueKey('topic-branch-$id')));
  await tester.pumpAndSettle();
  await tester.drag(find.byKey(const ValueKey('map-scroll')), Offset(0, -(topicTapPoint(tester, id).dy - above)));
  await tester.pumpAndSettle();
}

/// Opens topic [id] with a tap on its branch.
Future<void> openTopicByBranch(WidgetTester tester, String id) async {
  await tester.ensureVisible(find.byKey(ValueKey('topic-branch-$id')));
  await tester.pumpAndSettle();
  await tester.tapAt(topicTapPoint(tester, id));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadQaFonts);

  for (final (name, settings, size) in [
    ('main-phone', <String, String>{}, const Size(390, 844)),
    ('main-dark', {SettingKeys.themeMode: 'dark'}, const Size(390, 844)),
    ('main-bw', {SettingKeys.display: 'bw'}, const Size(390, 844)),
    ('main-320', <String, String>{}, const Size(320, 640)),
    ('main-desktop', <String, String>{}, const Size(1280, 860)),
  ]) {
    testWidgets(name, (tester) async {
      await _pump(tester, size, settings);
      await scrollToTopicBranch(tester, 'cucina', above: size.height < 700 ? 240 : 340);
      await _shot(tester, '$name-food');
      if (topicBranchPlan(tester, 'cucina').carving case final c?) {
        final r = c.bounds.shift(tester.getTopLeft(find.byKey(const ValueKey('map-content')))).inflate(40);
        await _shot(tester, '$name-carving', crop: r.intersect(Offset.zero & size));
      }
      await scrollToTopicBranch(tester, 'viaggi', above: size.height < 700 ? 240 : 340);
      await _shot(tester, '$name-travel');
    });
  }

  testWidgets('topic tree', (tester) async {
    await _pump(tester, const Size(390, 844), {});
    await openTopicByBranch(tester, 'cucina');
    await _shot(tester, 'topic-food');
  });

  testWidgets('topic tree bw', (tester) async {
    await _pump(tester, const Size(390, 844), {SettingKeys.display: 'bw'});
    await openTopicByBranch(tester, 'cucina');
    await _shot(tester, 'topic-food-bw');
  });

  testWidgets('tree selector', (tester) async {
    await _pump(tester, const Size(390, 844), {});
    await tester.tap(find.byKey(const ValueKey('tree-selector')));
    await tester.pumpAndSettle();
    await _shot(tester, 'selector');
  });

  testWidgets('tree selector dark', (tester) async {
    await _pump(tester, const Size(390, 844), {SettingKeys.themeMode: 'dark'});
    await tester.tap(find.byKey(const ValueKey('tree-selector')));
    await tester.pumpAndSettle();
    await _shot(tester, 'selector-dark');
  });
}
