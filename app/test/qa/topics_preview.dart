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

Future<void> _scrollTo(WidgetTester tester, String key, {double above = 140}) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  final y = tester.getTopLeft(f).dy;
  await tester.drag(find.byKey(const ValueKey('map-scroll')), Offset(0, -(y - above - 80)));
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
      await _scrollTo(tester, 'topic-go-cucina', above: size.height < 700 ? 200 : 300);
      await _shot(tester, '$name-food');
      if (find.byKey(const ValueKey('topic-carving-cucina')).evaluate().isNotEmpty) {
        final r = tester.getRect(find.byKey(const ValueKey('topic-carving-cucina'))).inflate(40);
        await _shot(tester, '$name-carving', crop: r.intersect(Offset.zero & size));
      }
      await _scrollTo(tester, 'topic-go-viaggi', above: size.height < 700 ? 200 : 300);
      await _shot(tester, '$name-travel');
    });
  }

  testWidgets('topic tree', (tester) async {
    await _pump(tester, const Size(390, 844), {});
    await tapKey(tester, 'topic-go-cucina');
    await _shot(tester, 'topic-food');
  });

  testWidgets('topic tree bw', (tester) async {
    await _pump(tester, const Size(390, 844), {SettingKeys.display: 'bw'});
    await tapKey(tester, 'topic-go-cucina');
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
