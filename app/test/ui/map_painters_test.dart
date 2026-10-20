// The storybook map painters: nodes (six states, sparkly tiers), boughs,
// leaves and twinkles paint without exceptions on degenerate input, paint
// only black, white and gray in black & white, and the branch style spec
// parses with defaults.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:tosk/ui/map/branch_style.dart';
import 'package:tosk/ui/map/ink_art.dart';
import 'package:tosk/ui/map/map_layout.dart';
import 'package:tosk/ui/map/node_painter.dart';
import 'package:tosk/ui/map/skill_map_view.dart';
import 'package:tosk/ui/map/skill_node.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/theme/bw_skin.dart';
import 'package:tosk/ui/theme/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/big_map_course.dart';
import 'helpers.dart';

/// Paints with [paint] on a [size] canvas and returns the pixels (RGBA).
Future<ByteData> _render(Size size, void Function(Canvas) paint, {Color background = Colors.white}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = background);
  paint(canvas);
  final image = await recorder.endRecording().toImage(size.width.ceil(), size.height.ceil());
  return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
}

/// Pixels whose channels differ by more than the gray tolerance (any colour).
List<String> _coloured(ByteData px, {int tolerance = 6}) {
  final out = <String>[];
  for (var i = 0; i + 3 < px.lengthInBytes; i += 4) {
    final r = px.getUint8(i), g = px.getUint8(i + 1), b = px.getUint8(i + 2), a = px.getUint8(i + 3);
    if (a == 0) continue;
    final lo = [r, g, b].reduce((x, y) => x < y ? x : y);
    final hi = [r, g, b].reduce((x, y) => x > y ? x : y);
    if (hi - lo > tolerance) out.add('${i ~/ 4}: rgb($r,$g,$b)');
    if (out.length > 5) break;
  }
  return out;
}

bool _anyInk(ByteData px) {
  for (var i = 0; i + 3 < px.lengthInBytes; i += 4) {
    if (px.getUint8(i) < 200) return true;
  }
  return false;
}

void main() {
  group('NodePainter', () {
    for (final tier in MapTier.values) {
      test('${tier.name}: paints at any size, static and twinkling', () {
        for (final size in [0.0, 1.0, 8.0, 40.0, 76.0, 300.0]) {
          for (final twinkle in [null, 0.0, 0.37, 0.99]) {
            final recorder = ui.PictureRecorder();
            NodePainter(
              tier: tier,
              ink: MapInk.storybook,
              strength: 0.6,
              decay: 0.5,
              twinkle: twinkle,
              seed: inkSeed(tier.name),
            ).paint(Canvas(recorder), Size.square(size));
            recorder.endRecording();
          }
        }
      });
    }

    test('extreme strength and decay values', () {
      for (final s in [-1.0, 0.0, 1.0, 2.0, double.nan]) {
        final recorder = ui.PictureRecorder();
        NodePainter(tier: MapTier.started, ink: MapInk.storybook, strength: s, decay: s)
            .paint(Canvas(recorder), const Size.square(64));
        recorder.endRecording();
      }
    });

    testWidgets('black & white paints only black, white and gray', (tester) async {
      await tester.runAsync(() async {
        for (final tier in MapTier.values) {
          for (final decay in [0.0, 0.3, 0.6, 1.0]) {
            for (final sweep in [null, 0.5]) {
              final px = await _render(
                const Size.square(80),
                (c) => NodePainter(
                  tier: tier,
                  ink: kBwInk,
                  strength: 0.6,
                  monochrome: true,
                  decay: decay,
                  twinkle: 0.3,
                  sweep: sweep,
                ).paint(c, const Size.square(80)),
              );
              expect(_coloured(px), isEmpty, reason: '${tier.name} decay=$decay sweep=$sweep');
              expect(_anyInk(px), isTrue, reason: '${tier.name} painted nothing');
            }
          }
        }
      });
    });

    testWidgets('the metals sparkle: more twinkle ink from bronze to gold', (tester) async {
      await tester.runAsync(() async {
        int dark(ByteData px) {
          var n = 0;
          for (var i = 0; i + 3 < px.lengthInBytes; i += 4) {
            if (px.getUint8(i) < 120) n++;
          }
          return n;
        }

        // Count the ink outside the stone (rays and twinkles), per tier.
        final outside = <MapTier, int>{};
        for (final tier in [MapTier.bronze, MapTier.silver, MapTier.gold]) {
          final px = await _render(const Size.square(100), (c) {
            NodePainter(tier: tier, ink: kBwInk, strength: 0, monochrome: true, seed: 3)
                .paint(c, const Size.square(100));
            // Cover the stone and the strength ring, leave the sparkle zone.
            c.drawCircle(const Offset(50, 50), NodePainter.stoneRadius(100) * 1.3, Paint()..color = Colors.white);
          });
          outside[tier] = dark(px);
        }
        expect(outside[MapTier.bronze]!, greaterThan(0));
        expect(outside[MapTier.silver]!, greaterThan(outside[MapTier.bronze]!));
        expect(outside[MapTier.gold]!, greaterThan(outside[MapTier.silver]!));
      });
    });
  });

  group('boughs and leaves', () {
    test('degenerate paths paint without exceptions', () {
      final paths = [
        Path(),
        Path()..moveTo(10, 10),
        Path()
          ..moveTo(10, 10)
          ..lineTo(10, 10),
        Path()
          ..moveTo(10, 10)
          ..lineTo(10.5, 10.2),
        Path()
          ..moveTo(0, 0)
          ..lineTo(0, 300),
        Path()
          ..moveTo(0, 0)
          ..cubicTo(0, 100, 200, -100, 200, 0),
        Path()
          ..moveTo(0, 0)
          ..lineTo(100, 0)
          ..lineTo(0, 0),
      ];
      for (final p in paths) {
        for (final (w0, w1) in [(0.0, 0.0), (30.0, 12.0), (-5.0, 3.0), (400.0, 400.0)]) {
          final recorder = ui.PictureRecorder();
          paintBough(Canvas(recorder), p, ink: MapInk.storybook, style: BranchStyle.defaults, w0: w0, w1: w1, leafScale: 0.8, leafMinLength: 0);
          recorder.endRecording();
        }
      }
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      paintAshLeaf(c, Offset.zero, 0, 0, MapInk.storybook);
      paintAshLeaf(c, const Offset(10, 10), 1.2, 0.01, MapInk.storybook);
      paintAshLeaf(c, const Offset(10, 10), -2, 3, kBwInk);
      paintTwinkle(c, Offset.zero, 0, MapInk.storybook);
      paintTwinkle(c, const Offset(5, 5), 40, kBwInk);
      paintSprout(c, Offset.zero, 0, 0, MapInk.storybook);
      inkRing(c, Offset.zero, 0, Colors.black, wmin: 1, wmax: 2);
      inkRing(c, Offset.zero, -3, Colors.black, wmin: 1, wmax: 2);
      hatchRegion(c, Path(), Colors.black, angleDeg: 45, spacing: 0);
      hatchRegion(c, Path()..addRect(const Rect.fromLTWH(0, 0, 10, 10)), Colors.black, angleDeg: 45, spacing: 3);
      inkStroke(c, Polyline.sample(Path(), 2), Colors.black, wmin: 1, wmax: 2);
      inkStroke(c, Polyline.sample(Path()..moveTo(0, 0), 2), Colors.black, wmin: 1, wmax: 2);
      recorder.endRecording();
    });

    testWidgets('a black & white bough with a leaf is black, white and gray only', (tester) async {
      await tester.runAsync(() async {
        final path = Path()
          ..moveTo(60, 10)
          ..cubicTo(60, 120, 140, 80, 140, 230);
        for (final ink in [kBwInk, kBwInk.copyWith(ink: kBwGray)]) {
          final px = await _render(
            const Size(200, 240),
            (c) => paintBough(c, path, ink: ink, style: BranchStyle.defaults, w0: 24, w1: 12, leafScale: 0.7, leafMinLength: 10),
          );
          expect(_coloured(px), isEmpty);
          expect(_anyInk(px), isTrue);
        }
      });
    });

    test('a bough to a locked skill is painted thinner', () {
      expect(BranchStyle.defaults.lockedWidthScale, lessThan(1));
      expect(BranchStyle.defaults.twigWidth.first, greaterThan(BranchStyle.defaults.twigWidth.last));
    });
  });

  group('BranchStyle', () {
    test('parses the kit spec; missing keys and bad input give the defaults', () {
      final a = BranchStyle.parse(
        '{"bough": {"width_main": [48, 8], "knuckles": {"count": [2, "3"]}, "hatch": {"angle": "branch direction + 65 deg", "spacing": 9}},'
        ' "ink_outline": {"min_width": 1, "max_width": 5},'
        ' "nodes": {"extent": 2, "gleam": {"radius": 0.5, "arc_deg": [-100, -20]},'
        '   "sparkle": {"gold": {"twinkles": [{"angle": 10, "dist": 1.4, "size": 0.3, "rotate": 5}], "dots": [], "rays": {"count": 6}}}}}',
      );
      expect(a.widthStart, 48 / 80);
      expect(a.widthEnd, 8 / 80);
      expect(a.knucklesMin, 2);
      expect(a.knucklesMax, 3);
      expect(a.hatchAngle, 65);
      expect(a.hatchSpacing, 9);
      expect(a.outlineMin, 1);
      expect(a.outlineMax, 5);
      expect(a.extent, 2);
      expect(a.gleam.radius, 0.5);
      expect(a.gleam.to, -20);
      expect(a.sparkleFor('gold').twinkles.single.rotate, 5);
      expect(a.sparkleFor('gold').dots, isEmpty);
      expect(a.sparkleFor('gold').rays!.count, 6);
      expect(a.sparkleFor('gold').rays!.r1, const Rays().r1);
      expect(a.sparkleFor('silver').twinkles.length, 2);
      expect(a.sparkleFor('bronze').twinkles.length, 1);
      expect(a.grainOffsets, BranchStyle.defaults.grainOffsets);
      expect(BranchStyle.parse('not json').widthStart, BranchStyle.defaults.widthStart);
      expect(BranchStyle.parse('[1, 2]').widthStart, BranchStyle.defaults.widthStart);
      expect(BranchStyle.parse('{"nodes": {"sparkle": {"gold": {"rays": null}}}}').sparkleFor('gold').rays, isNull);
    });

    test('the bundled spec parses to the same numbers as the defaults', () {
      final spec = BranchStyle.parse(File('assets/brand/branch-style.json').readAsStringSync());
      final def = BranchStyle.defaults;
      expect(spec.widthStart, def.widthStart);
      expect(spec.widthEnd, def.widthEnd);
      expect(spec.knuckleAmp, def.knuckleAmp);
      expect(spec.grainOffsets, def.grainOffsets);
      expect(spec.hatchAngle, def.hatchAngle);
      expect(spec.outlineMax, def.outlineMax);
      expect(spec.leafScale, closeTo(def.leafScale, 1e-9));
      expect(spec.extent, def.extent);
      expect(spec.gleam.from, def.gleam.from);
      for (final tier in ['bronze', 'silver', 'gold']) {
        expect(spec.sparkleFor(tier).twinkles.length, def.sparkleFor(tier).twinkles.length, reason: tier);
        expect(spec.sparkleFor(tier).dots.length, def.sparkleFor(tier).dots.length, reason: tier);
        expect(spec.sparkleFor(tier).rays?.count, def.sparkleFor(tier).rays?.count, reason: tier);
      }
    });

    testWidgets('every mono PNG of the kit is strictly black, white and transparent', (tester) async {
      await tester.runAsync(() async {
        final files = Directory('assets/brand/png').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('-mono.png'));
        expect(files, isNotEmpty);
        for (final f in files) {
          final codec = await ui.instantiateImageCodec(f.readAsBytesSync());
          final frame = await codec.getNextFrame();
          final px = (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          expect(_coloured(px, tolerance: 0), isEmpty, reason: f.path);
          for (var i = 0; i + 3 < px.lengthInBytes; i += 4) {
            if (px.getUint8(i + 3) == 0) continue;
            final v = px.getUint8(i);
            expect(v == 0 || v == 255, isTrue, reason: '${f.path}: grey pixel $v');
          }
        }
      });
    });

    testWidgets('the provider falls back to the defaults without the asset', (tester) async {
      await pumpApp(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      await container.read(branchStyleAssetProvider.future);
      expect(container.read(branchStyleProvider), isA<BranchStyle>());
    });
  });

  group('MapGeometry direction', () {
    final course = bigMapCourse();
    final layout = layoutSkillMap(course.units, course.skills);

    test('top-down: the first band is at the top; bottom-up: at the bottom, rows flipped', () {
      final down = MapGeometry(layout: layout, availableWidth: 400, zoom: 1);
      final up = MapGeometry(layout: layout, availableWidth: 400, zoom: 1, direction: MapDirection.bottomUp);
      expect(down.height, up.height);
      expect(down.bandTop[0], 0);
      expect(up.bandTop[layout.bands.last.index], 0);
      expect(up.bandTop[0], greaterThan(up.bandTop[layout.bands.last.index]));
      // Every node still sits inside its band in both directions.
      for (final g in [down, up]) {
        for (final n in layout.nodes) {
          final b = layout.bands[n.band];
          final top = g.bandTop[b.index];
          final y = g.cellOrigin(n).dy;
          expect(y, greaterThanOrEqualTo(top + g.headerOf(b.index) - 0.01), reason: n.skillId);
          expect(y, lessThan(top + g.headerOf(b.index) + b.rowCount * g.rowHeight), reason: n.skillId);
        }
      }
      // A multi-row band flips its rows.
      final multi = layout.bands.firstWhere((b) => b.rowCount > 1);
      final first = layout.nodes.firstWhere((n) => n.band == multi.index && n.row == 0);
      expect(down.visualRow(first), 0);
      expect(up.visualRow(first), multi.rowCount - 1);
    });

    test('edge paths run from parent to child in both directions', () {
      for (final dir in MapDirection.values) {
        final g = MapGeometry(layout: layout, availableWidth: 400, zoom: 1, direction: dir);
        final painter = MapEdgesPainter(layout: layout, geometry: g, style: const ToskSkin().mapStyle(ThemeData().colorScheme));
        for (final e in layout.edges) {
          final a = layout.node(e.from)!, b = layout.node(e.to)!;
          final from = g.ringCenter(a), to = g.ringCenter(b);
          final p = painter.edgePath(a, b, from, to, g.diameter / 2);
          if (p == null) continue;
          final line = Polyline.sample(p, 4);
          expect((line.points.first - from).distance, lessThan((line.points.first - to).distance), reason: '$e $dir');
          expect((line.points.last - to).distance, lessThan((line.points.last - from).distance), reason: '$e $dir');
        }
        // The whole painter runs on the big course.
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), Size(g.width, g.height));
        recorder.endRecording();
      }
    });
  });

  group('current skill and the marker', () {
    test('currentSkillId is the first available or started skill in order', () {
      expect(currentSkillId(['a', 'b', 'c'], {'a': const SkillStats(tier: MapTier.gold), 'b': const SkillStats(tier: MapTier.started)}), 'b');
      expect(currentSkillId(['a', 'b'], {'a': const SkillStats(tier: MapTier.gold), 'b': const SkillStats(tier: MapTier.locked)}), isNull);
      expect(currentSkillId(['a'], const {}), 'a');
      expect(currentSkillId(const [], const {}), isNull);
    });

    testWidgets('Tosk marks the current skill on the map and never takes the tap', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const ValueKey('tosk-marker')), findsOneWidget);
      // The first skill is the current one on a fresh profile: still tappable.
      await tester.tap(find.byKey(const ValueKey('skill-node-greetings')));
      await tester.pumpAndSettle();
      expect(find.text('Start lesson'), findsOneWidget);
    });
  });

  group('twinkle animation', () {
    testWidgets('runs when enabled (no exceptions, repaints) and stops with reduce motion', (tester) async {
      final course = bigMapCourse();
      final layout = layoutSkillMap(course.units, course.skills);
      final stats = {for (final s in course.skills) s.id: const SkillStats(tier: MapTier.gold, strength: 1, practicedFacets: 3, totalFacets: 3)};
      Widget map({required bool twinkle, required bool reduceMotion}) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SkillMapView(
              course: course,
              layout: layout,
              stats: stats,
              style: const ToskSkin().mapStyle(ThemeData().colorScheme),
              lang: 'en',
              now: testNow,
              twinkle: twinkle,
              reduceMotion: reduceMotion,
            ),
          ),
        ),
      );
      await tester.pumpWidget(map(twinkle: true, reduceMotion: false));
      await tester.pump();
      expect(find.byType(SkillNode), findsWidgets);
      // A repeating animation: frames keep coming without settling.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(tester.hasRunningAnimations, isTrue);
      // Reduce motion (or twinkle off): the twinkles freeze.
      await tester.pumpWidget(map(twinkle: true, reduceMotion: true));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(map(twinkle: false, reduceMotion: false));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
