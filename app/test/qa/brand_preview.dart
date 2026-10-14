// Review screenshots of the tosk brand integration with real fonts (no
// `_test` suffix, so not in the default run):
//   QA_OUT=<dir> [QA_RATIO=1] flutter test test/qa/brand_preview.dart
// Saves the map (colour, dark, black & white; phone and desktop; a 30-skill
// course), a node-state gallery, the lesson summary, the empty states, the
// course picker and Settings' About.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:tosk/core/core.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/demo/demo_seed.dart';
import 'package:tosk/ui/lesson/intro/exercise_intros.dart';
import 'package:tosk/ui/map/node_painter.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/ui/theme/bw_skin.dart';
import 'package:tosk/ui/theme/skin.dart';
import 'package:tosk/ui/theme/tosk_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/big_map_course.dart';
import '../ui/helpers.dart';

/// Real fonts (Roboto and the icons from the Flutter cache; Gelasio comes
/// from the app's font manifest).
Future<void> loadQaFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'C:/Users/timo/dev/flutter';
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String name) async => ByteData.sublistView(File('$dir/$name').readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final n in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-italic.ttf', 'roboto-light.ttf']) {
    roboto.addFont(f(n));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(f('materialicons-regular.otf'))).load();
  // The app's own font (declared in pubspec, but flutter_test only maps it when loaded here).
  final gelasio = FontLoader('Gelasio');
  for (final n in ['Gelasio[wght].ttf', 'Gelasio-Bold.ttf']) {
    gelasio.addFont((() async => ByteData.sublistView(File('assets/brand/fonts/$n').readAsBytesSync()))());
  }
  await gelasio.load();
}

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa-brand');

/// 2 for crisp review images, 1 for the committed docs/screenshots.
final _ratio = double.tryParse(Platform.environment['QA_RATIO'] ?? '') ?? 2;

Future<void> _shot(WidgetTester tester, String name, {Key root = appRootKey}) async {
  // Let image assets decode (they load on real futures), then settle.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(root));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _ratio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    _out.createSync(recursive: true);
    File('${_out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Every tier on the demo course, so the map shows the whole hierarchy.
Map<String, SkillStats> _tierStats() {
  final skills = buildDemoItalian().skills;
  final tiers = [MapTier.gold, MapTier.silver, MapTier.bronze, MapTier.started, MapTier.available, MapTier.locked];
  return {
    for (var i = 0; i < skills.length; i++)
      skills[i].id: SkillStats(
        tier: tiers[(i ~/ 2).clamp(0, tiers.length - 1)],
        strength: 0.3 + 0.1 * (i % 6),
        lastPracticed: tiers[(i ~/ 2).clamp(0, tiers.length - 1)].index >= MapTier.started.index
            ? testNow.subtract(Duration(days: i))
            : null,
        fading: i == 1 ? 0.7 : 0.1,
      ),
  };
}

Future<void> _reset(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  setUpAll(loadQaFonts);

  for (final (name, settings, size) in [
    ('map-phone', <String, String>{}, const Size(400, 800)),
    ('map-dark', {SettingKeys.themeMode: 'dark'}, const Size(400, 800)),
    ('map-bw', {SettingKeys.display: 'bw'}, const Size(400, 800)),
    ('map-desktop', <String, String>{}, const Size(1280, 800)),
    ('map-small', <String, String>{}, const Size(320, 568)),
  ]) {
    testWidgets(name, (tester) async {
      final store = TestProgressStore(settings: settings);
      await seedDemoProgress(store, buildDemoItalian(), testNow);
      await pumpApp(tester, store: store, size: size, overrides: [
        skillStatsProvider.overrideWith((ref) async => _tierStats()),
      ]);
      await _shot(tester, name);
      if (size.height <= 800) {
        await tester.drag(find.byKey(const ValueKey('map-scroll')), const Offset(0, -500));
        await _shot(tester, '$name-scrolled');
      }
    });
  }

  testWidgets('map-zoomed', (tester) async {
    final store = TestProgressStore();
    await seedDemoProgress(store, buildDemoItalian(), testNow);
    await pumpApp(tester, store: store, overrides: [skillStatsProvider.overrideWith((ref) async => _tierStats())]);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    await _shot(tester, 'map-zoomed');
  });

  testWidgets('map-big-course', (tester) async {
    await pumpApp(tester, size: const Size(400, 800), overrides: [courseCatalogProvider.overrideWithValue(BigCourseCatalog())]);
    await _shot(tester, 'map-big');
    await tester.drag(find.byKey(const ValueKey('map-scroll')), const Offset(0, -700));
    await _shot(tester, 'map-big-scrolled');
  });

  testWidgets('node gallery', (tester) async {
    setSurface(tester, const Size(640, 420));
    Widget row(MapStyle style, bool mono, Color bg) => Container(
      color: bg,
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final t in MapTier.values)
            CustomPaint(
              size: const Size.square(96),
              painter: NodePainter(tier: t, ink: style.ink, strength: 0.6, seed: 200 + t.index, monochrome: mono),
            ),
        ],
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: appRootKey,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              row(const ToskSkin().mapStyle(toskLightScheme()), false, Tosk.paperLow),
              row(const ToskSkin().mapStyle(toskDarkScheme()), false, Tosk.nightLow),
              row(const BwSkin().mapStyle(kBwScheme), true, kBwWhite),
              Container(
                color: Tosk.paperLow,
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final s in [0.0, 0.25, 0.5, 0.75, 1.0])
                      CustomPaint(
                        size: const Size.square(64),
                        painter: NodePainter(tier: MapTier.started, ink: MapInk.storybook, strength: s, seed: 5),
                      ),
                    CustomPaint(
                      size: const Size.square(64),
                      painter: const NodePainter(tier: MapTier.silver, ink: MapInk.storybook, strength: 0.6, decay: 0.8, seed: 9),
                    ),
                    CustomPaint(
                      size: const Size.square(64),
                      painter: const NodePainter(tier: MapTier.started, ink: kBwInk, strength: 0.6, monochrome: true, dashedRing: true, seed: 9),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await _shot(tester, 'nodes');
  });

  testWidgets('summary, empty states, picker, about, intro', (tester) async {
    final allSkills = buildDemoItalian().skills.map((s) => s.id).toList();
    for (final (variant, settings) in [('color', <String, String>{}), ('bw', {SettingKeys.display: 'bw'}), ('dark', {SettingKeys.themeMode: 'dark'})]) {
      await _reset(tester);
      await pumpApp(
        tester,
        store: TestProgressStore(settings: settings),
        initialLocation: Routes.labPlay(skills: allSkills, types: [ExerciseType.multipleChoice], length: 1),
      );
      await playToSummary(tester);
      await _shot(tester, 'summary-$variant');

      await _reset(tester);
      await pumpApp(tester, store: TestProgressStore(settings: settings), initialLocation: Routes.mistakes);
      await _shot(tester, 'mistakes-empty-$variant');

      await _reset(tester);
      await pumpApp(tester, store: TestProgressStore(settings: settings), initialLocation: Routes.settings);
      await scrollToFind(tester, find.byKey(const ValueKey('about-brand')));
      await _shot(tester, 'about-$variant');

      await _reset(tester);
      await pumpApp(tester, store: TestProgressStore(settings: settings), initialLocation: Routes.stories);
      await _shot(tester, 'stories-$variant');

      await _reset(tester);
      await pumpApp(tester, store: TestProgressStore(settings: settings), initialLocation: Routes.review);
      await _shot(tester, 'nothing-due-$variant');

      await _reset(tester);
      await pumpApp(
        tester,
        store: TestProgressStore(settings: settings),
        initialLocation: Routes.labPlay(skills: allSkills, types: [ExerciseType.cloze], length: 1),
        overrides: [exerciseIntrosEnabledProvider.overrideWithValue(true)],
      );
      await _shot(tester, 'intro-$variant');

      await _reset(tester);
      await pumpApp(tester, store: TestProgressStore(settings: settings));
      await _shot(tester, 'picker-$variant');
    }
  });
}
