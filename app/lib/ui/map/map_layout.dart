/// Pure skill-map layout: no Flutter, fully unit-tested.
///
/// * **Layer** = length of the longest prerequisite path to a skill (roots are 0).
/// * **Bands**: each unit is a horizontal band, stacked top to bottom in unit order.
///   Inside a band, the distinct layers of its skills become the band's rows, so a
///   unit that starts deep in the graph doesn't leave empty rows.
/// * **Columns**: rows are centered on a common width (a row with fewer nodes sits
///   on half columns). The order within a row minimizes edge crossings with the
///   barycenter heuristic (alternating down and up sweeps, best result kept).
/// * **`pos` override**: `Skill.posY` sets the row inside the unit band and
///   `Skill.posX` the column; overridden nodes are fixed and free nodes in the same
///   row take the remaining integer columns.
/// * **Cycles** are rejected by the pipeline validator, but the layout guards
///   against them anyway: a back edge is ignored when computing layers.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../core/core.dart';

@immutable
class MapNode {
  const MapNode({
    required this.skillId,
    required this.unitId,
    required this.band,
    required this.row,
    required this.globalRow,
    required this.col,
    required this.layer,
    this.pinned = false,
  });

  final String skillId;
  final String unitId;

  /// Index of the unit band.
  final int band;

  /// Row inside the band.
  final int row;

  /// Row counted from the top of the map.
  final int globalRow;

  /// Column (may be fractional when a row is centered); node center is at `col + 0.5`.
  final double col;

  /// Longest-prerequisite-path depth.
  final int layer;

  /// True when the column was fixed by `pos.x`.
  final bool pinned;

  MapNode _withCol(double c) => MapNode(
    skillId: skillId,
    unitId: unitId,
    band: band,
    row: row,
    globalRow: globalRow,
    col: c,
    layer: layer,
    pinned: pinned,
  );

  @override
  String toString() => 'MapNode($skillId, band $band, row $row, col $col, layer $layer)';
}

@immutable
class MapBand {
  const MapBand({required this.unitId, required this.index, required this.firstRow, required this.rowCount});
  final String unitId;
  final int index;
  final int firstRow;
  final int rowCount;
}

@immutable
class MapEdge {
  const MapEdge(this.from, this.to);

  /// Prerequisite skill id.
  final String from;

  /// Dependent skill id.
  final String to;

  @override
  bool operator ==(Object other) => other is MapEdge && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
  @override
  String toString() => '$from->$to';
}

@immutable
class MapLayout {
  MapLayout({required this.nodes, required this.bands, required this.edges, required this.columns})
    : _byId = {for (final n in nodes) n.skillId: n};

  final List<MapNode> nodes;
  final List<MapBand> bands;
  final List<MapEdge> edges;

  /// Width of the map in columns.
  final double columns;
  final Map<String, MapNode> _byId;

  int get totalRows => bands.isEmpty ? 0 : bands.last.firstRow + bands.last.rowCount;

  MapNode? node(String skillId) => _byId[skillId];

  /// Nodes of one global row ordered left to right.
  List<MapNode> rowNodes(int globalRow) =>
      nodes.where((n) => n.globalRow == globalRow).toList()..sort((a, b) => a.col.compareTo(b.col));

  static final empty = MapLayout(nodes: const [], bands: const [], edges: const [], columns: 1);
}

/// Longest prerequisite path depth per skill. Unknown prerequisites are ignored and
/// back edges (cycles) are skipped, so this always terminates.
Map<String, int> computeLayers(List<Skill> skills) {
  final byId = {for (final s in skills) s.id: s};
  final layer = <String, int>{};
  final visiting = <String>{};

  int visit(String id) {
    final known = layer[id];
    if (known != null) return known;
    visiting.add(id);
    var depth = 0;
    for (final r in byId[id]!.requires) {
      if (r == id || !byId.containsKey(r) || visiting.contains(r)) continue; // cycle guard
      depth = math.max(depth, visit(r) + 1);
    }
    visiting.remove(id);
    layer[id] = depth;
    return depth;
  }

  for (final s in skills) {
    visit(s.id);
  }
  return layer;
}

/// Lays out the map. [units] and [skills] may come in any order; skills whose unit
/// is unknown are put in an extra band at the end.
MapLayout layoutSkillMap(List<Unit> units, List<Skill> skills, {int sweeps = 6}) {
  if (skills.isEmpty) return MapLayout.empty;
  final byId = {for (final s in skills) s.id: s};
  final layers = computeLayers(skills);

  // Band order: units by ord, then unknown units in order of first appearance.
  final unitOrder = <String>[for (final u in (List.of(units)..sort((a, b) => a.ord.compareTo(b.ord)))) u.id];
  for (final s in skills) {
    if (!unitOrder.contains(s.unitId)) unitOrder.add(s.unitId);
  }
  final skillOrder = {for (var i = 0; i < skills.length; i++) skills[i].id: i};

  final bands = <MapBand>[];
  final placed = <String, ({int band, int row, int globalRow})>{};
  var firstRow = 0;
  for (final unitId in unitOrder) {
    final members = skills.where((s) => s.unitId == unitId).toList();
    if (members.isEmpty) continue;
    final autoLayers = {
      for (final s in members)
        if (s.posY == null) layers[s.id]!,
    }.toList()..sort();
    final rowOfLayer = {for (var i = 0; i < autoLayers.length; i++) autoLayers[i]: i};
    var rowCount = autoLayers.length;
    for (final s in members) {
      if (s.posY != null) rowCount = math.max(rowCount, s.posY!.clamp(0, 1 << 20) + 1);
    }
    final bandIndex = bands.length;
    for (final s in members) {
      final row = s.posY != null ? s.posY!.clamp(0, 1 << 20) : rowOfLayer[layers[s.id]]!;
      placed[s.id] = (band: bandIndex, row: row, globalRow: firstRow + row);
    }
    bands.add(MapBand(unitId: unitId, index: bandIndex, firstRow: firstRow, rowCount: rowCount));
    firstRow += rowCount;
  }
  final totalRows = firstRow;

  // Initial order per row: course order (unit ord, skill ord).
  final rows = List.generate(totalRows, (_) => <String>[]);
  for (final s in skills) {
    rows[placed[s.id]!.globalRow].add(s.id);
  }
  for (final r in rows) {
    r.sort((a, b) => skillOrder[a]!.compareTo(skillOrder[b]!));
  }

  // Width: the widest row, or the right-most pinned column.
  var columns = 1;
  for (final r in rows) {
    columns = math.max(columns, r.length);
  }
  for (final s in skills) {
    if (s.posX != null) columns = math.max(columns, s.posX!.clamp(0, 1 << 20) + 1);
  }

  final edges = <MapEdge>[
    for (final s in skills)
      for (final r in s.requires)
        if (r != s.id && byId.containsKey(r)) MapEdge(r, s.id),
  ];
  final parents = <String, List<String>>{};
  final children = <String, List<String>>{};
  for (final e in edges) {
    (parents[e.to] ??= []).add(e.from);
    (children[e.from] ??= []).add(e.to);
  }

  bool isPinned(String id) => byId[id]!.posX != null;

  /// Column per skill for the given row orders.
  Map<String, double> assignColumns(List<List<String>> order) {
    final col = <String, double>{};
    for (final row in order) {
      final pinned = row.where(isPinned).toList();
      final free = row.where((id) => !isPinned(id)).toList();
      if (pinned.isEmpty) {
        final offset = (columns - free.length) / 2;
        for (var i = 0; i < free.length; i++) {
          col[free[i]] = offset + i;
        }
      } else {
        final taken = <int>{};
        for (final id in pinned) {
          final c = byId[id]!.posX!.clamp(0, 1 << 20);
          taken.add(c);
          col[id] = c.toDouble();
        }
        var next = 0;
        for (final id in free) {
          while (taken.contains(next)) {
            next++;
          }
          taken.add(next);
          col[id] = next.toDouble();
        }
      }
    }
    return col;
  }

  int crossingsFor(Map<String, double> col) =>
      _countCrossings(edges, (id) => col[id]!, (id) => placed[id]!.globalRow.toDouble());

  var best = [for (final r in rows) List.of(r)];
  var bestCol = assignColumns(best);
  var bestCrossings = crossingsFor(bestCol);

  var current = [for (final r in rows) List.of(r)];
  var col = Map.of(bestCol);
  for (var sweep = 0; sweep < sweeps && bestCrossings > 0; sweep++) {
    final down = sweep.isEven;
    final indices = down ? [for (var r = 1; r < totalRows; r++) r] : [for (var r = totalRows - 2; r >= 0; r--) r];
    for (final r in indices) {
      final row = current[r];
      final free = row.where((id) => !isPinned(id)).toList();
      final key = <String, double>{};
      for (var i = 0; i < free.length; i++) {
        final id = free[i];
        final neighbours = (down ? parents[id] : children[id]) ?? const [];
        final relevant = neighbours.where((n) {
          final nr = placed[n]!.globalRow;
          return down ? nr < r : nr > r;
        }).toList();
        key[id] = relevant.isEmpty
            ? col[id]!
            : relevant.map((n) => col[n]! + 0.0).reduce((a, b) => a + b) / relevant.length;
      }
      final indexOf = {for (var i = 0; i < free.length; i++) free[i]: i};
      free.sort((a, b) {
        final c = key[a]!.compareTo(key[b]!);
        return c != 0 ? c : indexOf[a]!.compareTo(indexOf[b]!);
      });
      current[r] = [...row.where(isPinned), ...free];
      col = assignColumns(current);
    }
    final crossings = crossingsFor(col);
    if (crossings < bestCrossings) {
      bestCrossings = crossings;
      best = [for (final r in current) List.of(r)];
      bestCol = Map.of(col);
    }
  }

  final nodes = <MapNode>[
    for (final s in skills)
      MapNode(
        skillId: s.id,
        unitId: s.unitId,
        band: placed[s.id]!.band,
        row: placed[s.id]!.row,
        globalRow: placed[s.id]!.globalRow,
        col: 0,
        layer: layers[s.id]!,
        pinned: isPinned(s.id),
      )._withCol(bestCol[s.id]!),
  ];
  return MapLayout(nodes: nodes, bands: bands, edges: edges, columns: columns.toDouble());
}

/// Number of pairwise edge crossings in [layout] (edges drawn as straight segments
/// between node centers; edges sharing an endpoint never count).
int countCrossings(MapLayout layout) =>
    _countCrossings(layout.edges, (id) => layout.node(id)!.col, (id) => layout.node(id)!.globalRow.toDouble());

int _countCrossings(List<MapEdge> edges, double Function(String) x, double Function(String) y) {
  var count = 0;
  for (var i = 0; i < edges.length; i++) {
    for (var j = i + 1; j < edges.length; j++) {
      final a = edges[i], b = edges[j];
      if (a.from == b.from || a.from == b.to || a.to == b.from || a.to == b.to) continue;
      if (_segmentsCross(x(a.from), y(a.from), x(a.to), y(a.to), x(b.from), y(b.from), x(b.to), y(b.to))) {
        count++;
      }
    }
  }
  return count;
}

bool _segmentsCross(double ax, double ay, double bx, double by, double cx, double cy, double dx, double dy) {
  double orient(double px, double py, double qx, double qy, double rx, double ry) =>
      (qx - px) * (ry - py) - (qy - py) * (rx - px);
  final o1 = orient(ax, ay, bx, by, cx, cy);
  final o2 = orient(ax, ay, bx, by, dx, dy);
  final o3 = orient(cx, cy, dx, dy, ax, ay);
  final o4 = orient(cx, cy, dx, dy, bx, by);
  return ((o1 > 0 && o2 < 0) || (o1 < 0 && o2 > 0)) && ((o3 > 0 && o4 < 0) || (o3 < 0 && o4 > 0));
}
