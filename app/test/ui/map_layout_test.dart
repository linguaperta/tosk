import 'package:tosk/core/core.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/map/map_layout.dart';
import 'package:flutter_test/flutter_test.dart';

Skill sk(String id, {String unit = 'u1', int ord = 0, List<String> requires = const [], int? x, int? y}) => Skill(
  id: id,
  unitId: unit,
  ord: ord,
  kind: SkillKind.vocab,
  title: {'en': id},
  requires: requires,
  posX: x,
  posY: y,
);

const u1 = Unit(id: 'u1', ord: 1, title: {'en': 'One'});
const u2 = Unit(id: 'u2', ord: 2, title: {'en': 'Two'});
const u3 = Unit(id: 'u3', ord: 3, title: {'en': 'Three'});

void main() {
  group('computeLayers', () {
    test('layer is the longest prerequisite path', () {
      final layers = computeLayers([
        sk('a'),
        sk('b', requires: ['a']),
        sk('c', requires: ['b']),
        sk('d', requires: ['a', 'c']), // long path a-b-c-d wins over a-d
      ]);
      expect(layers, {'a': 0, 'b': 1, 'c': 2, 'd': 3});
    });

    test('unknown prerequisites and self-references are ignored', () {
      final layers = computeLayers([
        sk('a', requires: ['missing', 'a']),
        sk('b', requires: ['a']),
      ]);
      expect(layers, {'a': 0, 'b': 1});
    });

    test('cycles terminate', () {
      final layers = computeLayers([
        sk('a', requires: ['c']),
        sk('b', requires: ['a']),
        sk('c', requires: ['b']),
      ]);
      expect(layers.keys, containsAll(['a', 'b', 'c']));
      expect(layers.values.every((l) => l >= 0 && l <= 2), isTrue);
    });
  });

  group('layoutSkillMap', () {
    test('empty course', () {
      final l = layoutSkillMap(const [], const []);
      expect(l.nodes, isEmpty);
      expect(l.totalRows, 0);
    });

    test('units are stacked bands; rows inside a band are its distinct layers', () {
      final l = layoutSkillMap(
        [u2, u1], // order by ord, not list order
        [
          sk('a', unit: 'u1'),
          sk('b', unit: 'u1', requires: ['a']),
          sk('c', unit: 'u2', requires: ['b']), // layer 2, but row 0 of band u2
          sk('d', unit: 'u2', requires: ['c']),
        ],
      );
      expect(l.bands.map((b) => b.unitId), ['u1', 'u2']);
      expect(l.bands[0].firstRow, 0);
      expect(l.bands[0].rowCount, 2);
      expect(l.bands[1].firstRow, 2);
      expect(l.bands[1].rowCount, 2);
      expect(l.node('c')!.layer, 2);
      expect(l.node('c')!.band, 1);
      expect(l.node('c')!.row, 0);
      expect(l.node('d')!.globalRow, 3);
      expect(l.totalRows, 4);
    });

    test('every node of a band sits inside the band', () {
      final course = buildDemoItalian();
      final l = layoutSkillMap(course.units, course.skills);
      for (final n in l.nodes) {
        final b = l.bands[n.band];
        expect(n.globalRow, inInclusiveRange(b.firstRow, b.firstRow + b.rowCount - 1));
        expect(course.skill(n.skillId)!.unitId, b.unitId);
      }
      // Prerequisites within the graph always sit in an earlier row, unless pinned.
      for (final e in l.edges) {
        final to = course.skill(e.to)!;
        if (to.posY != null) continue;
        expect(l.node(e.from)!.globalRow, lessThan(l.node(e.to)!.globalRow), reason: '$e');
      }
    });

    test('rows are centered on the widest row', () {
      final l = layoutSkillMap(
        [u1],
        [
          sk('a'),
          sk('b', requires: ['a'], ord: 1),
          sk('c', requires: ['a'], ord: 2),
          sk('d', requires: ['a'], ord: 3),
        ],
      );
      expect(l.columns, 3);
      expect(l.node('a')!.col, 1); // (3 - 1) / 2
      expect(l.rowNodes(1).map((n) => n.col), [0, 1, 2]);
    });

    test('pos overrides row and column inside the unit band', () {
      final l = layoutSkillMap(
        [u1, u2],
        [
          sk('a'),
          sk('b', requires: ['a']),
          sk('p', unit: 'u2', x: 3, y: 2),
          sk('q', unit: 'u2', requires: ['b']),
        ],
      );
      final p = l.node('p')!;
      expect(p.pinned, isTrue);
      expect(p.band, 1);
      expect(p.row, 2);
      expect(p.col, 3);
      expect(l.bands[1].rowCount, 3); // grows to fit the pinned row
      expect(l.columns, 4); // grows to fit the pinned column
      expect(l.node('q')!.row, 0);
    });

    test('free nodes avoid columns taken by pinned nodes', () {
      final l = layoutSkillMap([u1], [sk('p', x: 0, y: 0), sk('a', ord: 1), sk('b', ord: 2)]);
      final cols = l.rowNodes(0).map((n) => n.col).toList();
      expect(cols.toSet().length, 3);
      expect(l.node('p')!.col, 0);
    });

    test('barycenter ordering removes avoidable crossings', () {
      // Course order puts c (child of b) left of d (child of a): one crossing.
      final skills = [
        sk('a', ord: 0),
        sk('b', ord: 1),
        sk('c', ord: 2, requires: ['b']),
        sk('d', ord: 3, requires: ['a']),
      ];
      final naive = layoutSkillMap([u1], skills, sweeps: 0);
      expect(countCrossings(naive), 1);
      final l = layoutSkillMap([u1], skills);
      expect(countCrossings(l), 0);
      expect(l.node('d')!.col, lessThan(l.node('c')!.col));
    });

    test('crossings never increase versus course order', () {
      final course = buildDemoItalian();
      final naive = layoutSkillMap(course.units, course.skills, sweeps: 0);
      final l = layoutSkillMap(course.units, course.skills);
      expect(countCrossings(l), lessThanOrEqualTo(countCrossings(naive)));
    });

    test('skills of unknown units get their own band at the end', () {
      final l = layoutSkillMap([u1], [sk('a'), sk('x', unit: 'zz')]);
      expect(l.bands.map((b) => b.unitId), ['u1', 'zz']);
      expect(l.node('x')!.band, 1);
    });

    test('a cycle still lays out every skill', () {
      final l = layoutSkillMap(
        [u1, u3],
        [
          sk('a', requires: ['b']),
          sk('b', requires: ['a']),
          sk('c', unit: 'u3', requires: ['a']),
        ],
      );
      expect(l.nodes.length, 3);
      expect(l.edges.length, 3);
    });
  });
}
