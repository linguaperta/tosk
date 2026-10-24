// The carved topic title sits in the middle of its branch (docs/ui.md "Topic
// trees"): its optical middle (between the middle of the x-height and of the
// cap height, [carvingOpticalCentre]) on the bark's middle line, within a
// pixel, at every branch thickness (stone sizes from the smallest zoom to the
// largest, both sides, tapering and fading branches, text scaled up), with the
// real font (Gelasio Bold).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/ui/map/branch_style.dart';
import 'package:tosk/ui/map/map_layout.dart';
import 'package:tosk/ui/map/topic_branch.dart';

import '../qa/brand_preview.dart' show loadQaFonts;

/// The bark's middle across the glyph at [g]: the halfway point between where
/// the silhouette ends on either side, marching along the letter's up
/// direction (0.05 px steps) — measured on the painted shape, not on the plan.
double _offCentre(BranchPlan p, CarvedGlyph g) {
  final up = Offset(math.sin(g.angle), -math.cos(g.angle));
  double edge(double sign) {
    var d = 0.0;
    while (d < 60 && p.shape.silhouette.contains(g.center + up * (d * sign))) {
      d += 0.05;
    }
    return d;
  }

  return (edge(1) - edge(-1)) / 2;
}

/// The vertical middle of [ch]'s ink when painted at [carvedGlyphOrigin] (0 is
/// where the plan puts the glyph's centre).
Future<(double top, double bottom)> _ink(String ch, double size) async {
  final tp = TextPainter(
    text: TextSpan(text: ch, style: carvingTextStyle(size).copyWith(color: const Color(0xFF000000))),
    textDirection: TextDirection.ltr,
  )..layout();
  const pad = 40.0, scale = 8.0; // 1/8 px resolution
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)
    ..scale(scale)
    ..translate(pad, pad);
  tp.paint(canvas, carvedGlyphOrigin(tp, size));
  tp.dispose();
  final image = rec.endRecording().toImageSync((2 * pad * scale).round(), (2 * pad * scale).round());
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  int? top, bottom;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (data.getUint8((y * image.width + x) * 4 + 3) > 127) {
        top ??= y;
        bottom = y;
        break;
      }
    }
  }
  image.dispose();
  return (top! / scale - pad, (bottom! + 1) / scale - pad);
}

void main() {
  setUpAll(loadQaFonts);

  testWidgets('the optical middle of the real font lands on the glyph centre', (tester) async {
    await tester.runAsync(() async {
      for (final size in [11.0, 14.0, 19.0, 24.0]) {
        final (xTop, xBottom) = await _ink('x', size);
        final (hTop, hBottom) = await _ink('H', size);
        // The font's own x-height and cap height (within the 1/8 px raster).
        expect(xBottom - xTop, closeTo(size * kCarvingXHeight, 0.3), reason: 'x at $size');
        expect(hBottom - hTop, closeTo(size * kCarvingCapHeight, 0.3), reason: 'H at $size');
        // x and H sit on one baseline; their middles average to the origin.
        expect(xBottom, closeTo(hBottom, 0.2));
        final optical = ((xTop + xBottom) / 2 + (hTop + hBottom) / 2) / 2;
        expect(optical.abs(), lessThan(0.5), reason: 'optical middle at $size is $optical px off');
      }
    });
  });

  testWidgets('every letter sits on the middle of the bark at every branch thickness', (tester) async {
    const branch = TopicBranch(id: 'salute', anchor: 'a', title: 'Body and health', shortTitle: 'Body');
    final widths = <double>{};
    var checked = 0;
    // From the smallest stone to the largest (the branch is 20–36 px wide), on
    // phones and on a wide map (where the branch tapers more and fades out).
    for (final diameter in [36.0, 48.0, 60.0, 72.0, 80.0, 96.0]) {
      final metrics = BranchMetrics(diameter);
      widths.add(metrics.width);
      for (final side in [1, -1]) {
        for (final (mapWidth, cell) in [(390.0, 120.0), (1280.0, 150.0)]) {
          for (final scale in [1.0, 1.3]) {
            final stone = Offset(side > 0 ? 80 : mapWidth - 80, 100);
            final p = buildBranch(
              lane: BranchLane(
                branch: branch,
                node: const MapNode(skillId: 'a', unitId: 'u', band: 0, row: 0, globalRow: 0, col: 0, layer: 0),
                side: side,
                lane: 0,
              ),
              stone: stone,
              r: diameter / 2,
              cellWidth: cell,
              laneTop: 100 + diameter,
              mapWidth: mapWidth,
              metrics: metrics,
              style: BranchStyle.defaults,
              scaler: TextScaler.linear(scale),
            )!;
            final c = p.carving!;
            expect(c.glyphs, isNotEmpty);
            for (final g in c.glyphs) {
              final off = _offCentre(p, g);
              expect(off.abs(), lessThan(1.0),
                  reason: '"${g.char}" is ${off.toStringAsFixed(2)} px off the middle (stone $diameter, side $side, '
                      'map $mapWidth, text x$scale)');
              checked++;
            }
            // The arrow too.
            for (final q in [if (c.hasArrow) ...[c.shaft.points.first, c.shaft.points.last]]) {
              final off = _offCentre(p, (char: '', center: q, angle: c.glyphs.first.angle));
              expect(off.abs(), lessThan(1.5));
            }
          }
        }
      }
    }
    expect(widths.length, greaterThan(3)); // several thicknesses
    expect(checked, greaterThan(100));
  });
}
