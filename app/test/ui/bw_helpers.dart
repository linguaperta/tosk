/// Black & white (e-ink) checks: the whole screen is rendered to an image and
/// every pixel must be gray (r = g = b, within a small tolerance for
/// antialiasing). Black, white and the one gray only blend into grays, so any
/// colored pixel means some widget still paints a theme or hard-coded color.
/// This catches every source (widgets, decorations, custom painters, icons,
/// shadows) without knowing how a widget paints.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Max channel spread still counted as gray.
const int kGrayTolerance = 6;

/// Pixels of the app (from `pumpApp`, or [root]) that aren't gray, as
/// "x,y rgb(...) <- widget path" strings (at most [limit], spread out).
Future<List<String>> colorPixels(WidgetTester tester, {Finder? root, int limit = 8}) async {
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(root ?? find.byKey(appRootKey));
  final view = tester.view;
  final hits = <Offset, String>{};
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final w = image.width, h = image.height;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final r = data.getUint8(i), g = data.getUint8(i + 1), b = data.getUint8(i + 2), a = data.getUint8(i + 3);
        if (a == 0) continue;
        final hi = r > g ? (r > b ? r : b) : (g > b ? g : b);
        final lo = r < g ? (r < b ? r : b) : (g < b ? g : b);
        if (hi - lo > kGrayTolerance) {
          // One sample per 24 px cell is enough to locate the culprit.
          final cell = Offset((x ~/ 24).toDouble(), (y ~/ 24).toDouble());
          hits.putIfAbsent(cell, () => '$x,$y rgb($r,$g,$b)');
        }
      }
    }
    image.dispose();
  });
  view.toString();
  final out = <String>[];
  for (final e in hits.entries.take(limit)) {
    final parts = e.value.split(' ').first.split(',');
    final at = Offset(double.parse(parts[0]) + 0.5, double.parse(parts[1]) + 0.5);
    final result = HitTestResult();
    tester.binding.hitTestInView(result, at, tester.view.viewId);
    final path = [
      for (final h in result.path.take(4))
        if (h.target is RenderObject) (h.target as RenderObject).debugCreator.toString().split('\n').first,
    ].join(' < ');
    out.add('${e.value} <- $path');
  }
  if (hits.length > limit) out.add('... ${hits.length - limit} more cells');
  return out;
}

/// The color of the app's pixel at [at] (logical = physical pixels in tests).
Future<ui.Color> pixelAt(WidgetTester tester, Offset at) async {
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(appRootKey));
  late ui.Color c;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final i = (at.dy.toInt() * image.width + at.dx.toInt()) * 4;
    c = ui.Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
    image.dispose();
  });
  return c;
}

/// Fails with the offending pixels when the screen isn't pure grayscale.
Future<void> expectGrayscale(WidgetTester tester, String what, {Finder? root}) async {
  final bad = await colorPixels(tester, root: root);
  expect(bad, isEmpty, reason: '$what has colored pixels:\n${bad.join('\n')}');
  expectReadableText(tester, what);
}

/// Text that the pixel scan can't judge:
///
/// * Every visible text must resolve a font family. A theme `TextStyle` built
///   from scratch (no family, no size) replaces the theme's text style. Under
///   `flutter test` that falls back to the test font, whose glyphs are solid
///   blocks; with real fonts loaded, QA screenshots showed "Preview" as black
///   bars. On a device it falls back to the engine default at the wrong size.
/// * A button's label must differ in color from the button's own fill (its
///   opaque `Material`), so no label is black on black or white on white.
void expectReadableText(WidgetTester tester, String what) {
  final bad = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || ro.size.isEmpty) continue;
    final text = (e.widget as RichText).text;
    final plain = text.toPlainText().trim();
    if (plain.isEmpty) continue;
    final style = text.style;
    if (style?.fontFamily == null) {
      bad.add('"$plain": no font family (a theme text style without a base)');
    }
    final color = style?.color;
    final fill = _buttonFill(e);
    if (color != null && fill != null && color.a > 0.5 && fill.toARGB32() == color.withValues(alpha: 1).toARGB32()) {
      bad.add('"$plain": label color equals the button fill #${fill.toARGB32().toRadixString(16)}');
    }
  }
  expect(bad, isEmpty, reason: '$what has unreadable text:\n${bad.take(10).join('\n')}');
}

/// The opaque fill of the button [e] sits in (the `Material` a
/// `ButtonStyleButton` paints), or null when the button is transparent or [e]
/// is not in a button.
Color? _buttonFill(Element e) {
  Material? material;
  var inButton = false;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Material && material == null) material = w;
    if (w is ButtonStyleButton) {
      inButton = true;
      return false;
    }
    return true;
  });
  final m = material;
  if (!inButton || m == null || m.type == MaterialType.transparency) return null;
  final c = m.color;
  return c != null && c.a > 0.99 ? c : null;
}
