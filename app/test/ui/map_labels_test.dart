// The map's text never collides: a node's title (up to two lines) and its
// days chip don't overlap each other or a neighbour's label, the room under
// every stone is reserved, and no bough runs through a unit title, on the
// real Italian and Spanish maps and the 30-skill fixture at phone widths
// 320, 360 and 412 with text 1.0 and 1.3. Plus the map action bar's short
// labels fitting on one line.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, RenderRepaintBoundary;
import 'package:flutter/services.dart' show ByteData;
import 'package:tosk/ui/map/map_action_bar.dart';
import 'package:tosk/ui/map/map_labels.dart';
import 'package:tosk/ui/map/map_layout.dart';
import 'package:tosk/ui/map/skill_map_view.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/theme/bw_skin.dart';
import 'package:tosk/ui/theme/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/real_packs.dart';
import '../fixtures/big_map_course.dart';
import '../qa/brand_preview.dart' show loadQaFonts;
import 'helpers.dart';

/// Every skill practiced (so every node has a chip), a mix of tiers, the
/// last third locked.
Map<String, SkillStats> _stats(CourseData c) => {
  for (var i = 0; i < c.skills.length; i++)
    c.skills[i].id: i > c.skills.length * 2 ~/ 3
        ? const SkillStats(tier: MapTier.locked)
        : SkillStats(
            tier: MapTier.values[2 + i % 4],
            strength: 0.6,
            lastPracticed: testNow.subtract(Duration(days: i % 12)),
            practicedFacets: 4,
            totalFacets: 8,
          ),
};

/// The map content (its RepaintBoundary) as RGBA, and where it is on screen.
class _Pixels {
  _Pixels(this.data, this.width, this.height, this.origin);
  final ByteData data;
  final int width, height;
  final Offset origin;
}

Future<_Pixels> _render(WidgetTester tester) async {
  final content = find.byKey(const ValueKey('map-content'));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.ancestor(of: content, matching: find.byType(RepaintBoundary)).first);
  late _Pixels out;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    out = _Pixels(data, image.width, image.height, boundary.localToGlobal(Offset.zero));
    image.dispose();
  });
  return out;
}

/// Pixels in [r] (image coordinates) within a few levels of [c].
int _count(_Pixels p, Rect r, Color c) {
  var n = 0;
  final cr = (c.r * 255).round(), cg = (c.g * 255).round(), cb = (c.b * 255).round();
  for (var y = math.max(0, r.top.floor()); y < math.min(p.height, r.bottom.ceil()); y++) {
    for (var x = math.max(0, r.left.floor()); x < math.min(p.width, r.right.ceil()); x++) {
      final i = (y * p.width + x) * 4;
      if ((p.data.getUint8(i) - cr).abs() < 10 && (p.data.getUint8(i + 1) - cg).abs() < 10 && (p.data.getUint8(i + 2) - cb).abs() < 10) n++;
    }
  }
  return n;
}

void main() {
  // Real fonts (Roboto, Gelasio), so text widths are the phone's.
  setUpAll(loadQaFonts);

  final courses = <String, CourseData Function()>{
    for (final id in bundledPackIds()) id: () => loadCourseFile('assets/courses/$id.sqlite'),
    'big fixture': bigMapCourse,
  };

  for (final MapEntry(key: name, value: load) in courses.entries) {
    group('map text on $name', () {
      late CourseData course;
      late MapLayout layout;
      setUpAll(() {
        course = load();
        layout = layoutSkillMap(course.units, course.skills);
      });

      for (final width in const [320.0, 360.0, 412.0]) {
        for (final scale in const [1.0, 1.3]) {
          for (final bw in const [false, true]) {
            testWidgets('${width.round()} dp, text $scale${bw ? ', black & white' : ''}', (tester) async {
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
              setSurface(tester, Size(width, 900));
              final stats = _stats(course);
              final skin = bw ? const BwSkin() : const ToskSkin() as Skin;
              final theme = skin.theme(Brightness.light);
              await tester.pumpWidget(
                MaterialApp(
                  theme: theme,
                  home: Scaffold(
                    body: SingleChildScrollView(
                      child: SkillMapView(
                        course: course,
                        layout: layout,
                        stats: stats,
                        style: skin.mapStyle(theme.colorScheme),
                        lang: 'en',
                        now: testNow,
                        storyCounts: {for (final u in course.units.take(3)) u.id: 2},
                        onUnitStories: (_) {},
                      ),
                    ),
                  ),
                ),
              );
              await tester.pump();
              expect(tester.takeException(), isNull, reason: 'no overflow');

              final plan = (tester.state(find.byType(SkillMapView)) as dynamic).plan as MapPlan;
              final g = plan.geometry;
              final origin = tester.getTopLeft(find.byKey(const ValueKey('map-content')));
              Rect local(Finder f) => tester.getRect(f).shift(-origin);

              // Node labels: the title above its chip, both in the reserved
              // room, no label touching another.
              final labels = <String, Rect>{};
              for (final n in layout.nodes) {
                final title = find.byKey(ValueKey('skill-title-${n.skillId}'), skipOffstage: false);
                final chip = find.byKey(ValueKey('skill-days-${n.skillId}'), skipOffstage: false);
                expect(title, findsOneWidget, reason: n.skillId);
                final t = local(title);
                final room = g.labelRect(n).inflate(0.5);
                expect(room.contains(t.topLeft) && room.contains(t.bottomRight), isTrue,
                    reason: '${n.skillId}: title $t in $room');
                var all = t;
                if (chip.evaluate().isNotEmpty) {
                  final c = local(chip);
                  expect(c.top, greaterThanOrEqualTo(t.bottom - 0.01), reason: '${n.skillId}: chip under the title');
                  expect(c.overlaps(t), isFalse, reason: '${n.skillId}: chip $c overlaps title $t');
                  expect(room.contains(c.topLeft) && room.contains(c.bottomRight), isTrue,
                      reason: '${n.skillId}: chip $c in $room');
                  all = all.expandToInclude(c);
                }
                // The title's lines fit (no hidden second line).
                final para = tester.renderObject<RenderParagraph>(
                  find.descendant(of: title, matching: find.byType(RichText), skipOffstage: false),
                );
                expect(para.size.height, lessThanOrEqualTo(g.text.titleBlock + 0.01), reason: n.skillId);
                labels[n.skillId] = all;
              }
              final ids = labels.keys.toList();
              for (var i = 0; i < ids.length; i++) {
                for (var j = i + 1; j < ids.length; j++) {
                  expect(labels[ids[i]]!.overlaps(labels[ids[j]]!), isFalse,
                      reason: '${ids[i]} ${labels[ids[i]]} and ${ids[j]} ${labels[ids[j]]}');
                }
              }

              // Unit titles: on a plaque above the boughs, with a margin
              // round the text, in the header, whole on one or two lines.
              final ink = skin.mapStyle(theme.colorScheme).ink;
              final pixels = bw ? null : await _render(tester);
              if (pixels != null) {
                // Not vacuous: the boughs' bark is found where it is.
                final all = Rect.fromLTWH(0, 0, pixels.width.toDouble(), pixels.height.toDouble());
                expect(_count(pixels, all, ink.bark), greaterThan(1000));
              }
              for (final b in layout.bands) {
                final title = find.descendant(
                  of: find.byKey(ValueKey('band-title-${b.unitId}'), skipOffstage: false),
                  matching: find.byType(RichText),
                  skipOffstage: false,
                );
                final r = local(title);
                final plaque = plan.titleRect(b.index);
                expect(plaque.deflate(3).contains(r.topLeft) && plaque.deflate(3).contains(r.bottomRight), isTrue,
                    reason: '${b.unitId}: text $r inside its plaque $plaque with a margin');
                expect(r.top, greaterThanOrEqualTo(g.bandTop[b.index]), reason: b.unitId);
                expect(r.bottom, lessThanOrEqualTo(g.bandTop[b.index] + g.headerOf(b.index)), reason: b.unitId);
                final para = tester.renderObject<RenderParagraph>(title);
                if (width >= 360) expect(para.didExceedMaxLines, isFalse, reason: '${b.unitId}: the whole title');
                // No twig or leaf over the plaque (a bough passes behind it).
                for (final x in plan.boughs) {
                  expect(leafTouches(x.shape, plaque), isFalse, reason: '${b.unitId}: a leaf over the title');
                }
                // And no bark shows inside the text: the plaque covers it.
                if (pixels != null) {
                  final bark = _count(pixels, r.shift(origin - pixels.origin), ink.bark);
                  expect(bark, 0, reason: '${b.unitId}: bark pixels inside the title $r');
                }
              }
              final order = tester.widget<Stack>(find.byKey(const ValueKey('map-content'))).children;
              final boughLayer = order.indexWhere((c) => c is Positioned && c.child.key == const ValueKey('map-boughs'));
              final firstTitle = order.indexWhere((c) => c.key is ValueKey<String> && (c.key! as ValueKey<String>).value.startsWith('band-title-'));
              expect(boughLayer, greaterThanOrEqualTo(0));
              expect(firstTitle, greaterThan(boughLayer), reason: 'titles paint above the boughs');
              await tester.pumpWidget(const SizedBox());
            });
          }
        }
      }
    });
  }

  for (final width in const [320.0, 360.0, 412.0]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('action bar labels at ${width.round()} dp, text $scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        setSurface(tester, Size(width, 400));
        await tester.pumpWidget(
          MaterialApp(
            theme: const ToskSkin().theme(Brightness.light),
            home: Scaffold(
              bottomNavigationBar: MapActionBar(mistakeCount: 12, onMistakes: () {}, onFading: () {}, onJump: () {}),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final (key, text, full) in const [
          ('mistakes-button', 'Mistakes · 12', 'Review mistakes (12)'),
          ('fading-button', 'Fading', "What's fading"),
        ]) {
          final label = find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text));
          expect(label, findsOneWidget, reason: key);
          final para = tester.renderObject<RenderParagraph>(
            find.descendant(of: label, matching: find.byType(RichText)),
          );
          expect(para.didExceedMaxLines, isFalse, reason: '$key: one line, not cut');
          // At 360 dp and wider the label keeps its full size (no scaling down).
          if (width >= 360) {
            final shown = tester.getRect(label);
            expect(shown.width, closeTo(para.size.width, 0.5), reason: '$key: not scaled down at ${width}dp');
          }
          expect(find.bySemanticsLabel(full), findsOneWidget, reason: key);
        }
      });
    }
  }
}
