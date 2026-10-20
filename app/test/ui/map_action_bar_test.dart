// The map's action bar ("Review mistakes (N)", "What's fading", "Jump to
// current unit"): under the map, never over a skill node, 48 px targets with
// their tooltips, in color and black & white, at phone and desktop sizes and
// with large text.
import 'package:tosk/ui/map/map_screen.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/providers.dart' show courseCatalogProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/big_map_course.dart';
import 'bw_helpers.dart';
import 'helpers.dart';
import 'overflow_test.dart' show seedMistakes, seeded;

const _sizes = {
  'small phone 320x568': Size(320, 568),
  'phone 360x640': Size(360, 640),
  'desktop 1280x800': Size(1280, 800),
};

final _nodes = find.byWidgetPredicate(
  (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('skill-node-'),
);

/// The bar sits below the map's viewport (the map is clipped there) and
/// nothing floats over the map: a tap on every node in view reaches that
/// node, at the top and at the end of the map; the last node clears the bar.
Future<void> expectNothingCovered(WidgetTester tester, String what) async {
  final bar = tester.getRect(find.byKey(const ValueKey('map-action-bar')));
  final viewport = tester.getRect(find.byKey(const ValueKey('map-scroll')));
  expect(viewport.bottom, lessThanOrEqualTo(bar.top + 0.5), reason: '$what: the map ends above the bar');

  void tapsReachNodes(String where) {
    var checked = 0;
    for (final e in _nodes.evaluate()) {
      final r = tester.getRect(find.byElementPredicate((x) => x == e));
      final visible = r.intersect(viewport);
      if (visible.width < 8 || visible.height < 8) continue; // scrolled away
      final node = e.renderObject;
      final hits = tester.hitTestOnBinding(visible.center).path.map((h) => h.target).whereType<RenderObject>();
      expect(
        hits.any((t) => _isInside(t, node)),
        isTrue,
        reason: '$what ($where): ${(e.widget.key! as ValueKey<String>).value} is covered',
      );
      checked++;
    }
    expect(checked, greaterThan(0), reason: '$what ($where): nodes in view');
  }

  tapsReachNodes('top');
  await tester.drag(find.byKey(const ValueKey('map-scroll')), const Offset(0, -20000));
  await tester.pumpAndSettle();
  tapsReachNodes('end');
  final last = _nodes
      .evaluate()
      .map((e) => tester.getRect(find.byElementPredicate((x) => x == e)))
      .reduce((a, b) => a.bottom > b.bottom ? a : b);
  expect(last.bottom, lessThanOrEqualTo(bar.top), reason: '$what: the last node clears the bar');
}

/// Whether [target] is [node] or inside it in the render tree.
bool _isInside(RenderObject target, RenderObject? node) {
  RenderObject? o = target;
  while (o != null) {
    if (identical(o, node)) return true;
    o = o.parent;
  }
  return false;
}

void _expectTargets(WidgetTester tester, String what) {
  for (final key in ['mistakes-button', 'fading-button', 'jump-current-unit']) {
    final f = find.byKey(ValueKey(key));
    if (f.evaluate().isEmpty) continue;
    final s = tester.getSize(f);
    expect(s.height, greaterThanOrEqualTo(48), reason: '$what: $key height');
    expect(s.width, greaterThanOrEqualTo(48), reason: '$what: $key width');
  }
}

void main() {
  for (final entry in _sizes.entries) {
    for (final bw in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        final what = '${entry.key}, ${bw ? 'black & white' : 'color'}, text $scale';
        testWidgets('mistakes and fading: $what', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final store = await seeded(settings: bw ? {SettingKeys.display: 'bw'} : const {});
          await seedMistakes(store);
          await pumpApp(tester, size: entry.value, store: store);
          expect(find.byType(MapScreen), findsOneWidget);
          expect(find.byKey(const ValueKey('mistakes-button')), findsOneWidget);
          expect(find.byKey(const ValueKey('fading-button')), findsOneWidget);
          expect(find.byTooltip('Practice your open mistakes'), findsOneWidget);
          expect(find.byTooltip('Practice what you are forgetting'), findsOneWidget);
          expect(find.byType(FloatingActionButton), findsNothing);
          _expectTargets(tester, what);
          if (bw) await expectGrayscale(tester, what);
          await expectNothingCovered(tester, what);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('long map: the jump button is in the bar too (black & white, small phone)', (tester) async {
    final course = bigMapCourse();
    await pumpApp(
      tester,
      size: const Size(320, 568),
      store: TestProgressStore(
        settings: {
          SettingKeys.display: 'bw',
          SettingKeys.course: course.meta.id,
          SettingKeys.coursesAdded: course.meta.id,
        },
      ),
      overrides: [courseCatalogProvider.overrideWithValue(BigCourseCatalog())],
    );
    final bar = find.byKey(const ValueKey('map-action-bar'));
    expect(find.descendant(of: bar, matching: find.byKey(const ValueKey('jump-current-unit'))), findsOneWidget);
    expect(find.byTooltip('Jump to current unit'), findsOneWidget);
    _expectTargets(tester, 'long map');
    await expectGrayscale(tester, 'long map bar');
    await expectNothingCovered(tester, 'long map');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fresh profile on a short map has no bar', (tester) async {
    await pumpApp(tester, size: const Size(360, 640));
    expect(find.byKey(const ValueKey('map-action-bar')), findsNothing);
  });
}
