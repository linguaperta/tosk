// v0.7.1 medals and map motion: the three tiers differ in colour and in
// shape, decay cracks the stone, the promotion sweep, the twinkle motion,
// the leaf springs; and on the map: one shared ticker that runs only while
// something moves, nothing in black & white or with reduce motion, and no
// repaint of the static layers (stones, boughs) or of widgets outside the
// map while the twinkles and leaves move.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:tosk/ui/map/branch_style.dart';
import 'package:tosk/ui/map/map_layout.dart';
import 'package:tosk/ui/map/map_motion.dart';
import 'package:tosk/ui/map/medal_art.dart';
import 'package:tosk/ui/map/node_painter.dart';
import 'package:tosk/ui/map/skill_map_view.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/theme/bw_skin.dart';
import 'package:tosk/ui/theme/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/big_map_course.dart';
import 'helpers.dart';

Future<ByteData> _render(Size size, void Function(Canvas) paint, {Color background = Colors.white}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = background);
  paint(canvas);
  final image = await recorder.endRecording().toImage(size.width.ceil(), size.height.ceil());
  return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
}

List<String> _coloured(ByteData px, {int tolerance = 6}) {
  final out = <String>[];
  for (var i = 0; i + 3 < px.lengthInBytes; i += 4) {
    final r = px.getUint8(i), g = px.getUint8(i + 1), b = px.getUint8(i + 2);
    final lo = [r, g, b].reduce((x, y) => x < y ? x : y);
    final hi = [r, g, b].reduce((x, y) => x > y ? x : y);
    if (hi - lo > tolerance) out.add('${i ~/ 4}: rgb($r,$g,$b)');
    if (out.length > 5) break;
  }
  return out;
}

int _dark(ByteData px) {
  var n = 0;
  for (var i = 0; i + 3 < px.lengthInBytes; i += 4) {
    if (px.getUint8(i) < 110) n++;
  }
  return n;
}

int _differing(ByteData a, ByteData b) {
  var n = 0;
  for (var i = 0; i + 3 < a.lengthInBytes; i += 4) {
    if ((a.getUint8(i) - b.getUint8(i)).abs() > 60) n++;
  }
  return n;
}

/// Mean colour of the stone's face (a disc of half the stone radius).
(double, double, double) _faceColour(ByteData px, int size) {
  final c = size / 2, rr = NodePainter.stoneRadius(size.toDouble()) * 0.5;
  var r = 0.0, g = 0.0, b = 0.0, n = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if ((x - c) * (x - c) + (y - c) * (y - c) > rr * rr) continue;
      final i = (y * size + x) * 4;
      r += px.getUint8(i);
      g += px.getUint8(i + 1);
      b += px.getUint8(i + 2);
      n++;
    }
  }
  return (r / n, g / n, b / n);
}

void main() {
  group('tiers', () {
    testWidgets('bronze, silver and gold differ in colour: copper-brown, cool grey, warm yellow', (tester) async {
      await tester.runAsync(() async {
        Future<(double, double, double)> face(MapTier t) async => _faceColour(
              await _render(const Size.square(120), (c) => NodePainter(tier: t, ink: MapInk.storybook, strength: 1, seed: 5).paint(c, const Size.square(120))),
              120,
            );
        final (br, bg, bb) = await face(MapTier.bronze);
        final (sr, sg, sb) = await face(MapTier.silver);
        final (gr, gg, gb) = await face(MapTier.gold);
        double lum(double r, double g, double b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;
        // Bronze is dark and red-brown; gold is light and yellow; silver is bluish grey.
        expect(lum(br, bg, bb), lessThan(lum(gr, gg, gb) - 40));
        expect(br - bb, greaterThan(50), reason: 'bronze is warm');
        expect(gr - gb, greaterThan(80), reason: 'gold is warm yellow');
        expect(gg, greaterThan(bg + 50), reason: 'gold is yellow, bronze is brown');
        expect(sb, greaterThan(sr), reason: 'silver is cool');
        expect((sr - sb).abs(), lessThan(40), reason: 'silver is grey');
      });
    });

    testWidgets('in black & white the tiers differ by shape (texture, rings, rays, laurel)', (tester) async {
      await tester.runAsync(() async {
        final px = <MapTier, ByteData>{};
        for (final t in [MapTier.bronze, MapTier.silver, MapTier.gold]) {
          px[t] = await _render(const Size.square(100),
              (c) => NodePainter(tier: t, ink: kBwInk, strength: 1, monochrome: true, seed: 3).paint(c, const Size.square(100)));
          expect(_coloured(px[t]!), isEmpty, reason: t.name);
        }
        // Pairwise, a good part of the medal differs.
        expect(_differing(px[MapTier.bronze]!, px[MapTier.silver]!), greaterThan(400));
        expect(_differing(px[MapTier.silver]!, px[MapTier.gold]!), greaterThan(400));
        expect(_differing(px[MapTier.bronze]!, px[MapTier.gold]!), greaterThan(400));
      });
    });

    test('gold has rays over the top (long and short) and a laurel; the spec parses them', () {
      const rays = Rays();
      expect(rays.angles, hasLength(7));
      expect(rays.angles.every((a) => a > -180 && a < 0), isTrue, reason: 'over the top half');
      expect(rays.shortAngles, hasLength(6));
      const full = Rays(arcFrom: null, arcTo: null, count: 8, shortR1: null);
      expect(full.angles.first, 22.5);
      expect(full.shortAngles, isEmpty);
      expect(TierSparkle.gold.laurel, isNotNull);
      expect(TierSparkle.silver.laurel, isNull);
      final s = BranchStyle.parse(
        '{"nodes": {"gleam": {"tiers": ["gold", "silver"]}, "cracks": {"start": 0.3, "max": 2},'
        ' "sparkle": {"gold": {"rays": {"count": 5, "arc_deg": null, "short_r1": null}, "laurel": {"leaves": 6}}}}}',
      );
      expect(s.gleam.tiers, ['gold', 'silver']);
      expect(s.cracks.start, 0.3);
      expect(s.cracks.maxCracks, 2);
      expect(s.sparkleFor('gold').rays!.arcFrom, isNull);
      expect(s.sparkleFor('gold').rays!.shortAngles, isEmpty);
      expect(s.sparkleFor('gold').laurel!.leaves, 6);
      expect(s.sparkleFor('gold').laurel!.size, const Laurel().size);
      expect(BranchStyle.parse('{"nodes": {"sparkle": {"gold": {"laurel": null}}}}').sparkleFor('gold').laurel, isNull);
    });
  });

  group('decay cracks', () {
    test('the crack level starts at the threshold and saturates', () {
      const c = Cracks();
      expect(c.level(0), 0);
      expect(c.level(0.19), 0);
      expect(c.level(double.nan), 0);
      expect(c.level(0.6), closeTo(0.5, 1e-9));
      expect(c.level(1), 1);
      expect(c.level(7), 1);
      expect(NodePainter.crackLevel(MapTier.locked, 1), 0);
      expect(NodePainter.crackLevel(MapTier.available, 1), 0);
      expect(NodePainter.crackLevel(MapTier.gold, 1), 1);
    });

    test('more decay, more cracks: longer, chipped, a fragment breaking off; seeded', () {
      expect(CrackPattern.build(0, 3).isEmpty, isTrue);
      expect(CrackPattern.build(double.nan, 3).isEmpty, isTrue);
      var lastLines = 0;
      for (final lv in [0.05, 0.3, 0.6, 0.9]) {
        final p = CrackPattern.build(lv, 7);
        expect(p.lines.length, greaterThanOrEqualTo(lastLines), reason: 'level $lv');
        lastLines = p.lines.length;
        for (final line in p.lines) {
          expect(line.length, greaterThanOrEqualTo(2));
          for (final q in line) {
            expect(q.distance, lessThanOrEqualTo(1.0), reason: 'cracks stay on the stone');
          }
        }
      }
      expect(CrackPattern.build(0.05, 7).chips, isEmpty);
      expect(CrackPattern.build(0.3, 7).chips, hasLength(1));
      expect(CrackPattern.build(0.9, 7).chips, hasLength(3));
      expect(CrackPattern.build(0.45, 7).shards, isEmpty);
      expect(CrackPattern.build(0.6, 7).shards, hasLength(1));
      // Deterministic per seed, different across seeds.
      expect(CrackPattern.build(0.6, 7).lines.first, CrackPattern.build(0.6, 7).lines.first);
      expect(CrackPattern.build(0.6, 7).lines.first, isNot(CrackPattern.build(0.6, 8).lines.first));
    });

    testWidgets('a cracked node has more ink than a whole one; black & white stays black and white', (tester) async {
      await tester.runAsync(() async {
        for (final tier in [MapTier.started, MapTier.bronze, MapTier.silver, MapTier.gold]) {
          final counts = <int>[];
          for (final decay in [0.0, 0.5, 1.0]) {
            final px = await _render(const Size.square(100),
                (c) => NodePainter(tier: tier, ink: kBwInk, strength: 0.5, decay: decay, monochrome: true, seed: 11).paint(c, const Size.square(100)));
            expect(_coloured(px), isEmpty, reason: '${tier.name} $decay');
            counts.add(_dark(px));
          }
          expect(counts[1], greaterThan(counts[0]), reason: '${tier.name}: cracks add ink');
          expect(counts[2], greaterThan(counts[0]), reason: '${tier.name}: crumbling');
        }
      });
    });

    test('painting cracked nodes never throws (sizes, colour and dark ink)', () {
      for (final ink in [MapInk.storybook, MapInk.night, kBwInk]) {
        for (final tier in MapTier.values) {
          for (final size in [0.0, 6.0, 30.0, 48.0, 200.0]) {
            for (final decay in [0.0, 0.2, 0.35, 0.6, 0.85, 1.0, double.nan, -1.0]) {
              final recorder = ui.PictureRecorder();
              NodePainter(tier: tier, ink: ink, strength: 0.5, decay: decay, monochrome: ink == kBwInk, seed: 9)
                  .paint(Canvas(recorder), Size.square(size));
              recorder.endRecording();
            }
          }
        }
      }
    });
  });

  group('promotion and motion pieces', () {
    testWidgets('the shine sweep brightens the stone while it passes', (tester) async {
      await tester.runAsync(() async {
        int bright(ByteData px) {
          var n = 0;
          for (var i = 0; i + 3 < px.lengthInBytes; i += 4) {
            n += px.getUint8(i) + px.getUint8(i + 1) + px.getUint8(i + 2);
          }
          return n;
        }

        Future<ByteData> at(double? t) => _render(
              const Size.square(120),
              (c) => NodePainter(tier: MapTier.silver, ink: MapInk.storybook, strength: 1, sweep: t, seed: 2).paint(c, const Size.square(120)),
              background: Colors.black,
            );
        final none = bright(await at(null));
        expect(bright(await at(0.5)), greaterThan(none));
        // At the ends of the sweep there is nothing extra.
        expect(bright(await at(0)), none);
        expect(bright(await at(1)), none);
      });
    });

    test('twinkle motion: bronze rests and flares now and then, silver and gold breathe', () {
      var bronzeFlares = 0, bronzeRest = 0;
      final silver = <double>{}, gold = <double>{};
      for (var t = 0.0; t < 12; t += 0.05) {
        final b = twinkleMotion(MapTier.bronze, 0, t, 0.3);
        b.scale > 1.01 ? bronzeFlares++ : bronzeRest++;
        silver.add(double.parse(twinkleMotion(MapTier.silver, 1, t, 0.3).scale.toStringAsFixed(2)));
        gold.add(twinkleMotion(MapTier.gold, 0, t, 0.3).opacity);
      }
      expect(bronzeFlares, greaterThan(0));
      expect(bronzeRest, greaterThan(bronzeFlares * 4), reason: 'an occasional glint');
      expect(gold.length, greaterThan(20));
      expect(silver.length, greaterThan(10));
      final m = twinkleMotion(MapTier.gold, 0, double.nan, 0);
      expect(m.scale, 1);
      expect(twinkleMotion(MapTier.started, 0, 3, 0).scale, 1);
      for (var t = 0.0; t < 10; t += 0.1) {
        for (final tier in [MapTier.bronze, MapTier.silver, MapTier.gold]) {
          final x = twinkleMotion(tier, 2, t, 0.9);
          expect(x.scale, inInclusiveRange(0.7, 1.6));
          expect(x.opacity, inInclusiveRange(0.5, 1.0));
        }
      }
    });

    test('laurel, shine, stipple and sweep paint at degenerate sizes', () {
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      for (final r in [0.0, 0.5, 3.0, 40.0]) {
        paintLaurel(c, const Offset(50, 50), r, const Laurel(), MapInk.storybook);
        paintLaurel(c, const Offset(50, 50), r, const Laurel(leaves: 0), kBwInk);
        paintShine(c, const Offset(50, 50), r, Colors.white, edge: Colors.black);
        paintStipple(c, const Offset(50, 50), r, Colors.black);
        for (final t in [-1.0, 0.0, 0.5, 1.0, double.nan]) {
          paintShineSweep(c, const Offset(50, 50), r, t, Colors.white);
        }
      }
      recorder.endRecording();
    });

    test('leaf springs lean with the scroll, then settle; inactive leaves hang still', () {
      final leaves = [
        for (var i = 0; i < 3; i++) LeafSpot(tip: Offset(10.0 * i, 0), angle: i * 0.4, scale: 0.6, seed: 3 + i * 17),
      ];
      final sway = LeafSway(leaves);
      expect(sway.settled, isTrue);
      // Scrolling at 1500 px/s for half a second.
      for (var i = 0; i < 30; i++) {
        sway.step(1 / 60, 1500, {0, 1});
      }
      expect(sway.angleOf(0).abs(), greaterThan(0.1));
      expect(sway.angleOf(0).abs(), lessThanOrEqualTo(LeafSway.maxLean * 1.6));
      expect(sway.angleOf(2), 0, reason: 'not active');
      expect(sway.angleOf(0), isNot(closeTo(sway.angleOf(1), 1e-6)), reason: 'leaves differ');
      expect(sway.settled, isFalse);
      // The scrolling stops: a few swings, then still.
      var swings = 0;
      var last = sway.angleOf(0).sign;
      var t = 0.0;
      while (!sway.settled && t < 10) {
        sway.step(1 / 60, 0, {0, 1});
        t += 1 / 60;
        if (sway.angleOf(0) != 0 && sway.angleOf(0).sign != last) {
          swings++;
          last = sway.angleOf(0).sign;
        }
      }
      expect(sway.settled, isTrue);
      expect(t, lessThan(5), reason: 'settles within a few seconds');
      expect(swings, greaterThanOrEqualTo(1), reason: 'it wiggles back');
      expect(sway.angleOf(0), 0);
      sway.step(0, 100, {0});
      sway.step(double.nan, 100, {0});
      expect(LeafSway(const []).settled, isTrue);
    });
  });

  group('the map', () {
    final course = bigMapCourse();
    final layout = layoutSkillMap(course.units, course.skills);
    final tiers = [MapTier.gold, MapTier.silver, MapTier.bronze, MapTier.started];
    final stats = {
      for (var i = 0; i < course.skills.length; i++)
        course.skills[i].id: SkillStats(
          tier: tiers[i % tiers.length],
          strength: 0.8,
          lastPracticed: testNow.subtract(const Duration(days: 3)),
          fading: i % 3 == 0 ? 0.7 : 0.1,
          practicedFacets: 3,
          totalFacets: 3,
        ),
    };
    final scrollKey = GlobalKey();

    Widget map({
      bool twinkle = true,
      bool? sway,
      bool reduceMotion = false,
      bool bw = false,
      bool tickers = true,
    }) => MaterialApp(
      home: TickerMode(
        enabled: tickers,
        child: Scaffold(
          appBar: AppBar(title: const _Sentinel(key: ValueKey('outside'))),
          body: SingleChildScrollView(
            key: scrollKey,
            child: Column(
              children: [
                SkillMapView(
                  course: course,
                  layout: layout,
                  stats: stats,
                  style: bw ? const BwSkin().mapStyle(kBwScheme) : const ToskSkin().mapStyle(ThemeData().colorScheme),
                  lang: 'en',
                  now: testNow,
                  twinkle: twinkle,
                  swayLeaves: sway,
                  reduceMotion: reduceMotion,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    bool ticking(WidgetTester tester) =>
        (tester.state(find.byType(SkillMapView)) as dynamic).ticking as bool;

    testWidgets('no motion layers and no ticker in black & white or with reduce motion', (tester) async {
      setSurface(tester, const Size(400, 800));
      for (final (bw, reduce) in [(true, false), (false, true)]) {
        await tester.pumpWidget(map(bw: bw, reduceMotion: reduce));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('map-sparkles')), findsNothing);
        expect(find.byKey(const ValueKey('map-leaves')), findsNothing);
        expect(ticking(tester), isFalse);
        expect(tester.hasRunningAnimations, isFalse);
        // Scrolling doesn't start anything either.
        await tester.drag(find.byKey(scrollKey), const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 50));
        expect(ticking(tester), isFalse);
        await tester.pumpAndSettle();
        expect(ticking(tester), isFalse);
        expect(tester.hasRunningAnimations, isFalse);
      }
    });

    testWidgets('twinkles: one ticker, repainting only the sparkle layer', (tester) async {
      setSurface(tester, const Size(400, 800));
      await tester.pumpWidget(map(sway: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('map-sparkles')), findsOneWidget);
      expect(find.byKey(const ValueKey('map-leaves')), findsNothing);
      expect(ticking(tester), isTrue);
      final nodes = NodePainter.debugPaintCount;
      final edges = MapEdgesPainter.debugPaintCount;
      final outside = _Sentinel.paints;
      final sparkles = MapSparklePainter.debugPaintCount;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      expect(NodePainter.debugPaintCount, nodes, reason: 'the stones never repaint for the twinkles');
      expect(MapEdgesPainter.debugPaintCount, edges, reason: 'nor do the boughs');
      expect(_Sentinel.paints, outside, reason: 'nor anything outside the map');
      final painted = MapSparklePainter.debugPaintCount - sparkles;
      expect(painted, greaterThan(10));
      expect(painted, lessThanOrEqualTo(35), reason: 'throttled to about 30 fps');
      // Turning motion off stops the ticker.
      await tester.pumpWidget(map(twinkle: false));
      await tester.pump();
      expect(ticking(tester), isFalse);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('leaves sway while scrolling and the ticker stops once they settle', (tester) async {
      setSurface(tester, const Size(400, 800));
      await tester.pumpWidget(map(twinkle: false, sway: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-leaves')), findsOneWidget);
      expect(find.byKey(const ValueKey('map-sparkles')), findsNothing);
      expect(ticking(tester), isFalse, reason: 'nothing moves before a scroll');
      final nodes = NodePainter.debugPaintCount;
      final edges = MapEdgesPainter.debugPaintCount;
      final leaves = MapLeavesPainter.debugPaintCount;
      // A slow drag, frame by frame.
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(scrollKey)));
      for (var i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(0, -12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      expect(ticking(tester), isTrue);
      expect(MapLeavesPainter.debugPaintCount - leaves, greaterThan(10), reason: 'the leaves move');
      expect(NodePainter.debugPaintCount, nodes, reason: 'scrolling moves the static layers, it does not repaint them');
      expect(MapEdgesPainter.debugPaintCount, edges);
      // Let it settle: the ticker stops by itself.
      for (var i = 0; i < 400 && ticking(tester); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ticking(tester), isFalse);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      final settled = MapLeavesPainter.debugPaintCount;
      await tester.pump(const Duration(seconds: 1));
      expect(MapLeavesPainter.debugPaintCount, settled, reason: 'no repaint once still');
    });

    testWidgets('paused off screen (TickerMode) and while the app is in the background', (tester) async {
      setSurface(tester, const Size(400, 800));
      await tester.pumpWidget(map(tickers: false));
      await tester.pump();
      final sparkles = MapSparklePainter.debugPaintCount;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(MapSparklePainter.debugPaintCount, sparkles, reason: 'muted while off screen');
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(map());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(ticking(tester), isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(ticking(tester), isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(ticking(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the twinkles stop when no metal node is in view, and come back with a scroll', (tester) async {
      setSurface(tester, const Size(400, 800));
      final plain = {for (final s in course.skills) s.id: const SkillStats(tier: MapTier.available)};
      final first = course.skills.first.id;
      plain[first] = const SkillStats(tier: MapTier.gold, strength: 1, practicedFacets: 1, totalFacets: 1);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: SkillMapView(
              course: course,
              layout: layout,
              stats: plain,
              style: const ToskSkin().mapStyle(ThemeData().colorScheme),
              lang: 'en',
              now: testNow,
              twinkle: true,
              swayLeaves: false,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(ticking(tester), isTrue);
      controller.jumpTo(controller.position.maxScrollExtent);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ticking(tester), isFalse, reason: 'the only gold node is out of view');
      controller.jumpTo(0);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(ticking(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    test('bough shapes: the painter keeps the old look with leaves, and hands them out without', () {
      final g = MapGeometry(layout: layout, availableWidth: 400, zoom: 1);
      final painter = MapEdgesPainter(layout: layout, geometry: g, style: const ToskSkin().mapStyle(ThemeData().colorScheme));
      final boughs = painter.boughShapes();
      expect(boughs, isNotEmpty);
      final leaves = [for (final b in boughs) ?b.shape.leaf];
      expect(leaves, isNotEmpty);
      expect(boughs.where((b) => b.locked).every((b) => b.shape.leaf == null), isTrue);
      for (final leafless in [true, false]) {
        final recorder = ui.PictureRecorder();
        MapEdgesPainter(
          layout: layout,
          geometry: g,
          style: const ToskSkin().mapStyle(ThemeData().colorScheme),
          boughs: boughs,
          paintLeaves: leafless,
        ).paint(Canvas(recorder), Size(g.width, g.height));
        recorder.endRecording();
      }
      // The motion's leaf cap.
      final motion = MapMotion()..setLeaves([for (var i = 0; i < 60; i++) LeafSpot(tip: Offset(5, i * 10.0), angle: 0, scale: 0.5, seed: i)]);
      motion.visible = const Rect.fromLTWH(0, 0, 400, 800);
      expect(motion.activeLeaves().length, kMaxSwayLeaves);
      motion.visible = const Rect.fromLTWH(0, 5000, 400, 800);
      expect(motion.activeLeaves(), isEmpty);
      final pic = motion.leafPicture(leaves.first, MapInk.storybook);
      expect(identical(pic, motion.leafPicture(leaves.first, MapInk.storybook)), isTrue, reason: 'cached');
      motion.dispose();
    });
  });
}

/// Counts its paints: a widget outside the map that must not repaint while
/// the map's motion runs.
class _Sentinel extends StatelessWidget {
  const _Sentinel({super.key});
  static int paints = 0;

  @override
  Widget build(BuildContext context) => const CustomPaint(size: Size(40, 20), painter: _SentinelPainter());
}

class _SentinelPainter extends CustomPainter {
  const _SentinelPainter();

  @override
  void paint(Canvas canvas, Size size) => _Sentinel.paints++;

  @override
  bool shouldRepaint(_SentinelPainter old) => false;
}
