// The map's raster caches (`map_raster.dart`, "Map performance" in
// docs/ui.md): the cached map looks like the vector map, scrolling repaints
// no static art and rebuilds no widget, only tiles near the viewport exist,
// and a tile or stone is drawn once.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/ui/map/map_layout.dart';
import 'package:tosk/ui/map/map_raster.dart';
import 'package:tosk/ui/map/node_painter.dart';
import 'package:tosk/ui/map/skill_map_view.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/theme/bw_skin.dart';
import 'package:tosk/ui/theme/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/real_packs.dart';
import '../fixtures/big_map_course.dart';
import 'helpers.dart';

Map<String, SkillStats> _stats(CourseData c) => {
  for (var i = 0; i < c.skills.length; i++)
    c.skills[i].id: i > c.skills.length * 0.6
        ? const SkillStats(tier: MapTier.locked)
        : SkillStats(
            tier: MapTier.values[1 + i % 5],
            strength: 0.2 + 0.1 * (i % 8),
            lastPracticed: testNow.subtract(Duration(days: i % 9)),
            fading: (i % 5) * 0.2,
            practicedFacets: 4,
            totalFacets: 8,
          ),
};

class _Counted extends StatelessWidget {
  const _Counted({required this.child});
  final Widget child;
  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return child;
  }
}

void main() {
  final course = bundledPackIds().contains('it') ? loadCourseFile('assets/courses/it.sqlite') : bigMapCourse();
  final layout = layoutSkillMap(course.units, course.skills);
  final scrollKey = GlobalKey();

  Widget app({bool bw = false, ScrollController? controller}) {
    final skin = bw ? const BwSkin() : const ToskSkin() as Skin;
    final theme = skin.theme(Brightness.light);
    return MaterialApp(
      theme: theme,
      home: _Counted(
        child: Scaffold(
          appBar: AppBar(title: const Text('Map')),
          body: SingleChildScrollView(
            key: scrollKey,
            controller: controller,
            child: SkillMapView(
              course: course,
              layout: layout,
              stats: _stats(course),
              style: skin.mapStyle(theme.colorScheme),
              lang: 'en',
              now: testNow,
              // Tosk's image loads asynchronously; the art is what's compared.
              showMarker: false,
            ),
          ),
        ),
      ),
    );
  }

  Future<Uint8List> capture(WidgetTester tester) async {
    late Uint8List out;
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(appRootKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
      out = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      image.dispose();
    });
    return out;
  }

  RenderRasterArt boughs(WidgetTester tester) => tester.renderObject<RenderRasterArt>(find.byKey(const ValueKey('map-boughs')));

  for (final bw in [false, true]) {
    testWidgets('the cached map looks like the vector map (3x${bw ? ', black & white' : ''})', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(412 * 3, 800 * 3);
      addTearDown(tester.view.reset);
      addTearDown(() => debugDisableMapRasterCache = false);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      for (final offset in [0.0, 700.0, 1500.0]) {
        final shots = <Uint8List>[];
        for (final vector in [false, true]) {
          debugDisableMapRasterCache = vector;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(RepaintBoundary(key: appRootKey, child: app(bw: bw, controller: controller)));
          await tester.pump();
          controller.jumpTo(offset.clamp(0, controller.position.maxScrollExtent));
          await tester.pump();
          await tester.pump();
          shots.add(await capture(tester));
        }
        final a = shots[0], b = shots[1];
        expect(a.length, b.length);
        var off = 0, total = 0;
        for (var i = 0; i < a.length; i += 4) {
          var d = 0;
          for (var k = 0; k < 3; k++) {
            final x = (a[i + k] - b[i + k]).abs();
            if (x > d) d = x;
          }
          total += d;
          if (d > 64) off++;
        }
        final pixels = a.length ~/ 4;
        debugPrint('[raster vs vector] at $offset: ${(100 * off / pixels).toStringAsFixed(3)} % of pixels differ, mean ${(total / pixels).toStringAsFixed(3)}');
        // Same picture: only antialiased edges move by a fraction of a pixel.
        expect(off / pixels, lessThan(0.006), reason: 'at $offset: $off of $pixels pixels differ');
        expect(total / pixels, lessThan(1.0), reason: 'at $offset: mean difference');
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('scrolling the whole map repaints no static art and rebuilds no widget', (tester) async {
    setSurface(tester, const Size(412, 800));
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller: controller));
    await tester.pump();
    await tester.pump();
    final stones = NodePainter.debugPaintCount;
    final cached = RenderCachedPaint.debugRenders;
    final full = MapEdgesPainter.debugPaintCount;
    final tiles = RenderRasterArt.debugTileRenders;
    final builds = _Counted.builds;
    var rebuilt = 0;
    final names = <String>[];
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    final total = boughs(tester).debugTilesTotal;
    var maxLive = 0;
    final max = controller.position.maxScrollExtent;
    expect(max, greaterThan(2000), reason: 'a long map');
    for (var y = 0.0; y <= max; y += 37) {
      controller.jumpTo(y);
      await tester.pump(const Duration(milliseconds: 16));
      // Count from the second frame on: the first scroll flips the app
      // bar to "scrolled under" (one rebuild of the bar, as on any screen).
      if (y > 0 && debugOnRebuildDirtyWidget == null) {
        debugOnRebuildDirtyWidget = (e, _) {
          rebuilt++;
          names.add(e.widget.toStringShort());
        };
      }
      final live = boughs(tester).debugTileCount;
      if (live > maxLive) maxLive = live;
    }
    debugOnRebuildDirtyWidget = null;
    expect(tester.takeException(), isNull);
    expect(NodePainter.debugPaintCount, stones, reason: 'no stone is painted again');
    expect(RenderCachedPaint.debugRenders, cached, reason: 'no stone image is drawn again');
    expect(MapEdgesPainter.debugPaintCount, full, reason: 'the boughs are never painted whole');
    final drawn = RenderRasterArt.debugTileRenders - tiles;
    expect(drawn, lessThanOrEqualTo(total), reason: 'each tile is drawn at most once on the way down');
    expect(drawn, greaterThan(0));
    expect(maxLive, lessThanOrEqualTo(8), reason: 'only tiles near the viewport exist ($total in all)');
    expect(_Counted.builds, builds, reason: 'the screen above the map does not rebuild');
    expect(rebuilt, 0, reason: 'no widget rebuilds per scroll frame: ${names.toSet()}');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a stone is drawn once and again only when its skill changes', (tester) async {
    setSurface(tester, const Size(412, 800));
    await tester.pumpWidget(app());
    await tester.pump();
    final before = RenderCachedPaint.debugRenders;
    await tester.pumpWidget(app());
    await tester.pump();
    expect(RenderCachedPaint.debugRenders, before, reason: 'the same stats: nothing to redraw');
    await tester.pumpWidget(app(bw: true));
    await tester.pump();
    expect(RenderCachedPaint.debugRenders, greaterThan(before), reason: 'black & white redraws the stones');
    await tester.pumpWidget(const SizedBox());
  });
}
