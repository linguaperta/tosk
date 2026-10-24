// The map with a course the size of the expanded v1 courses (10 units, 30
// skills, long titles): usable and legible from 320 px phones to desktop.
import 'package:tosk/providers.dart';
import 'package:tosk/ui/map/map_layout.dart';
import 'package:tosk/ui/map/skill_map_view.dart';
import 'package:tosk/ui/map/skill_node.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/ui/theme/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/big_map_course.dart';
import 'helpers.dart';

void main() {
  final course = bigMapCourse();

  for (final (size, scale) in const [
    (Size(320, 568), 1.0),
    (Size(360, 640), 1.3),
    (Size(400, 800), 1.0),
    (Size(1280, 800), 1.0),
  ]) {
    testWidgets('30 skills at ${size.width.round()}x${size.height.round()}, text $scale', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(
        tester,
        size: size,
        // A first run on this catalog: the welcome was seen, the picker opens over the map.
        store: TestProgressStore(settings: {SettingKeys.welcomeDone: 'true'}),
        overrides: [courseCatalogProvider.overrideWithValue(BigCourseCatalog())],
      );
      final scroll = find.byKey(const ValueKey('map-scroll'));
      // Every node and band title is reachable by scrolling, with a 48 px tap target.
      for (final s in course.skills) {
        final node = find.byKey(ValueKey('skill-node-${s.id}'));
        await tester.scrollUntilVisible(
          node,
          200,
          scrollable: find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        );
        final box = tester.getSize(node);
        expect(box.width, greaterThanOrEqualTo(48), reason: s.id);
        expect(box.height, greaterThanOrEqualTo(48), reason: s.id);
        // The node's semantics carry the title.
        expect(
          tester.getSemantics(find.ancestor(of: node, matching: find.byType(SkillNode)).first).label,
          contains(s.title['en']!),
        );
      }
      for (final u in course.units) {
        expect(find.text(u.title['en']!, skipOffstage: false), findsOneWidget, reason: u.id);
      }
      // No horizontal scrolling at the default zoom.
      expect(find.byKey(const ValueKey('map-hscroll')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('edges never run behind another node', (tester) async {
    final layout = layoutSkillMap(course.units, course.skills);
    for (final width in [320.0, 400.0, 1280.0]) {
      final g = MapGeometry(layout: layout, availableWidth: width, zoom: 1);
      final painter = MapEdgesPainter(
        layout: layout,
        geometry: g,
        style: const ToskSkin().mapStyle(ColorScheme.fromSeed(seedColor: Colors.green)),
      );
      final r = g.diameter / 2;
      var detours = 0;
      for (final e in layout.edges) {
        final a = layout.node(e.from)!, b = layout.node(e.to)!;
        final from = g.ringCenter(a), to = g.ringCenter(b);
        if (to.dy <= from.dy) continue;
        final lane = painter.detourLane(a, b, from + Offset(0, r), to - Offset(0, r), r);
        if (lane == null) {
          // Straight (curved) edge: no node center close to the line between.
          for (final n in layout.nodes) {
            if (n.skillId == e.from || n.skillId == e.to) continue;
            final c = g.ringCenter(n);
            if (c.dy <= from.dy + 2 * r || c.dy >= to.dy - 2 * r) continue;
            final t = (c.dy - from.dy) / (to.dy - from.dy);
            final x = from.dx + (to.dx - from.dx) * t;
            expect(
              (c.dx - x).abs(),
              greaterThanOrEqualTo(g.cellWidth * 0.45),
              reason: '${e.from}->${e.to} via ${n.skillId}',
            );
          }
        } else {
          detours++;
        }
      }
      expect(detours, greaterThan(0)); // the unit-skipping edges
    }
  });
}
