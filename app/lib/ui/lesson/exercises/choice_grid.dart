/// The shared grid of answer options (cloze choices, conjugation endings,
/// match pairs, multiple choice and listen-and-pick lists).
///
/// Rules (docs/ui.md, "Option grids"):
///
/// * Every tile of a grid has the same width (the available width split in
///   columns) and the same height (the tallest tile's), at least 48 px.
/// * A label only wraps at spaces, never inside a word. When the longest word
///   doesn't fit a tile, every label of the grid shrinks a little (down to
///   85 %); when it still doesn't fit, the grid drops to fewer columns. A
///   board that prefers its columns (match pairs) shrinks down to 75 % first.
///   One column shrinks as far as needed (not below 50 %) as a last resort.
/// * A label that would need more than [kChoiceMaxLines] lines in a tile also
///   drops the grid to fewer columns.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'common.dart';

/// Font scales tried, in order, before the grid drops a column.
const kChoiceScales = [1.0, 0.95, 0.9, 0.85];

/// Font scales of a grid that prefers keeping its columns (match pairs).
const kChoiceKeepScales = [...kChoiceScales, 0.8, 0.75];

/// Font scales of one column, the last resort before a word would break.
const kChoiceLastResortScales = [...kChoiceKeepScales, 0.7, 0.65, 0.6, 0.55, 0.5];

/// Most lines a label may take in a multi-column grid.
const kChoiceMaxLines = 3;

/// Space between tiles, across and down.
const kChoiceSpacing = 10.0;

/// One option of a [ChoiceGrid].
@immutable
class ChoiceOption {
  const ChoiceOption({
    required this.label,
    this.key,
    this.number,
    this.state = OptionState.idle,
    this.onTap,
    this.labelWidget,
  });

  /// The label (also what the grid measures).
  final String label;

  /// The [OptionButton]'s key.
  final Key? key;

  /// The shortcut number shown in the badge.
  final int? number;
  final OptionState state;
  final VoidCallback? onTap;

  /// Replaces the label text (see [OptionButton.labelWidget]).
  final Widget? labelWidget;
}

/// How a grid lays out: [columns] and the font scale of every label.
@immutable
class ChoiceGridPlan {
  const ChoiceGridPlan(this.columns, this.textScale);
  final int columns;
  final double textScale;

  @override
  bool operator ==(Object other) => other is ChoiceGridPlan && other.columns == columns && other.textScale == textScale;

  @override
  int get hashCode => Object.hash(columns, textScale);

  @override
  String toString() => 'ChoiceGridPlan($columns columns, x$textScale)';
}

/// The words of [label]: what may not break.
Iterable<String> choiceWords(String label) => label.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);

/// Picks the columns and font scale for [labels] in [width].
///
/// [chrome] is the horizontal space a tile takes besides its label (padding,
/// badge, mark). [style] is the widest style a label is drawn in (bold in
/// black & white, where the right answer turns bold).
ChoiceGridPlan planChoiceGrid({
  required double width,
  required List<String> labels,
  required TextStyle style,
  required double chrome,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
  int maxColumns = 2,
  bool keepColumns = false,
  double spacing = kChoiceSpacing,
}) {
  final n = labels.length;
  final most = math.max(1, math.min(maxColumns, n));
  final painter = TextPainter(textDirection: textDirection, textScaler: textScaler);
  final words = {for (final l in labels) ...choiceWords(l)};
  final base = style.fontSize ?? 14;
  TextStyle at(double s) => s == 1 ? style : style.copyWith(fontSize: base * s);

  double widestWord(double s) {
    var w = 0.0;
    for (final word in words) {
      painter.text = TextSpan(text: word, style: at(s));
      painter.layout();
      w = math.max(w, painter.maxIntrinsicWidth);
    }
    return w;
  }

  int mostLines(double s, double avail) {
    var lines = 0;
    for (final l in labels) {
      painter.text = TextSpan(text: l, style: at(s));
      painter.layout(maxWidth: avail);
      lines = math.max(lines, painter.computeLineMetrics().length);
    }
    return lines;
  }

  try {
    for (var cols = most; cols >= 1; cols--) {
      final tile = (width - spacing * (cols - 1)) / cols;
      final avail = tile - chrome;
      final last = cols == 1;
      final scales = last ? kChoiceLastResortScales : (keepColumns ? kChoiceKeepScales : kChoiceScales);
      double? fit;
      for (final s in scales) {
        if (widestWord(s) <= avail) {
          fit = s;
          break;
        }
      }
      if (last) return ChoiceGridPlan(1, fit ?? scales.last);
      if (fit != null && (keepColumns || mostLines(fit, avail) <= kChoiceMaxLines)) return ChoiceGridPlan(cols, fit);
    }
    return const ChoiceGridPlan(1, 1);
  } finally {
    painter.dispose();
  }
}

/// Answer options as a grid of equal tiles that use the available width (the
/// player's column is at most 640 px wide).
///
/// [maxColumns] 2 is the grid of short options (cloze, endings); 1 the list of
/// long ones (multiple choice, listen and pick). [keepColumns] shrinks the
/// labels further (to 75 %) before dropping to one column (match pairs: left
/// and right). [columnMajor] fills the first column first. [uniformHeight] gives every tile the tallest tile's
/// height; without it only the tiles of a row share a height.
class ChoiceGrid extends StatelessWidget {
  const ChoiceGrid({
    super.key,
    required this.options,
    this.maxColumns = 2,
    this.keepColumns = false,
    this.columnMajor = false,
    this.uniformHeight = true,
    this.large = false,
    this.center = false,
    this.spacing = kChoiceSpacing,
  });

  final List<ChoiceOption> options;
  final int maxColumns;
  final bool keepColumns;
  final bool columnMajor;
  final bool uniformHeight;

  /// [OptionButton.large]: the bigger label of the list types.
  final bool large;

  /// [OptionButton.center]: centered labels.
  final bool center;
  final double spacing;

  /// The horizontal space an [OptionButton] takes besides its label.
  static double chromeOf({required bool numbered, required bool mono}) =>
      2 * OptionButton.hPadding +
      (numbered ? OptionButton.badgeSize + OptionButton.badgeGap : 0) +
      // The ✓ / ✗ of black & white appears after checking: reserved from the
      // start, so checking never re-wraps a label.
      (mono ? OptionButton.markGap + OptionButton.markSize : 0) +
      // Rounding headroom: a word measured to fit must fit in the paragraph.
      1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = FeedbackColors.of(context).mono;
    // What the label's Text resolves to inside the option's Material.
    var style = (theme.textTheme.bodyMedium ?? const TextStyle()).merge(OptionButton.baseStyle(context, large: large));
    if (mono) style = style.copyWith(fontWeight: FontWeight.w800);
    final chrome = chromeOf(numbered: options.any((o) => o.number != null), mono: mono);
    final textScaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
        final plan = planChoiceGrid(
          width: width,
          labels: [for (final o in options) o.label],
          style: style,
          chrome: chrome,
          textScaler: textScaler,
          textDirection: dir,
          maxColumns: maxColumns,
          keepColumns: keepColumns,
          spacing: spacing,
        );
        return _UniformGrid(
          key: const ValueKey('choice-grid'),
          columns: plan.columns,
          spacing: spacing,
          uniformHeight: uniformHeight,
          columnMajor: columnMajor,
          groups: columnMajor ? maxColumns : 1,
          children: [
            for (final o in options)
              OptionButton(
                key: o.key,
                label: o.label,
                labelWidget: o.labelWidget,
                number: o.number,
                state: o.state,
                onTap: o.onTap,
                large: large,
                center: center,
                textScale: plan.textScale,
              ),
          ],
        );
      },
    );
  }
}

class _UniformGrid extends MultiChildRenderObjectWidget {
  const _UniformGrid({
    super.key,
    required this.columns,
    required this.spacing,
    required this.uniformHeight,
    required this.columnMajor,
    this.groups = 1,
    super.children,
  });

  final int columns;
  final double spacing;
  final bool uniformHeight;
  final bool columnMajor;
  final int groups;

  @override
  RenderUniformGrid createRenderObject(BuildContext context) => RenderUniformGrid(
    columns: columns,
    spacing: spacing,
    uniformHeight: uniformHeight,
    columnMajor: columnMajor,
    groups: groups,
  );

  @override
  void updateRenderObject(BuildContext context, RenderUniformGrid renderObject) {
    renderObject
      ..columns = columns
      ..spacing = spacing
      ..uniformHeight = uniformHeight
      ..columnMajor = columnMajor
      ..groups = groups;
  }
}

class _GridParentData extends ContainerBoxParentData<RenderBox> {}

/// Equal-width tiles in [columns]; every tile as tall as the tallest
/// ([uniformHeight]) or as the tallest of its row. An incomplete last row is
/// centered (row-major order only). A column-major board of [groups] that
/// had to stack into one column keeps a wider gap between its groups.
class RenderUniformGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GridParentData> {
  RenderUniformGrid({
    required this._columns,
    required this._spacing,
    required this._uniformHeight,
    required this._columnMajor,
    this._groups = 1,
  });

  int _columns;
  int get columns => _columns;
  set columns(int v) {
    if (v == _columns) return;
    _columns = v;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  bool _uniformHeight;
  set uniformHeight(bool v) {
    if (v == _uniformHeight) return;
    _uniformHeight = v;
    markNeedsLayout();
  }

  bool _columnMajor;
  set columnMajor(bool v) {
    if (v == _columnMajor) return;
    _columnMajor = v;
    markNeedsLayout();
  }

  int _groups;
  set groups(int v) {
    if (v == _groups) return;
    _groups = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GridParentData) child.parentData = _GridParentData();
  }

  int get _cols => math.max(1, math.min(_columns, childCount));
  int get _rows => (childCount / _cols).ceil();

  (int row, int col) _cell(int i) => _columnMajor ? (i % _rows, i ~/ _rows) : (i ~/ _cols, i % _cols);

  double _width(BoxConstraints c) {
    if (c.hasBoundedWidth) return c.maxWidth;
    var w = 0.0;
    for (final k in getChildrenAsList()) {
      w = math.max(w, k.getMaxIntrinsicWidth(double.infinity));
    }
    return c.constrainWidth(w * _cols + _spacing * (_cols - 1));
  }

  double _tileWidth(double width) => math.max(0, (width - _spacing * (_cols - 1)) / _cols);

  /// Row heights for tiles of [heights] (in child order).
  List<double> _rowHeights(List<double> heights) {
    final rows = List<double>.filled(_rows, 0);
    final all = heights.fold(0.0, math.max);
    for (var i = 0; i < heights.length; i++) {
      final r = _cell(i).$1;
      rows[r] = _uniformHeight ? all : math.max(rows[r], heights[i]);
    }
    return rows;
  }

  /// The space above row [r] (r >= 1): wider between the groups of a
  /// stacked column-major board.
  double _gapAbove(int r) {
    if (!_columnMajor || _cols != 1 || _groups < 2) return _spacing;
    final groupSize = (childCount / _groups).ceil();
    return r % groupSize == 0 ? 2.4 * _spacing : _spacing;
  }

  double _total(List<double> rows) {
    var h = 0.0;
    for (var r = 0; r < rows.length; r++) {
      h += rows[r] + (r > 0 ? _gapAbove(r) : 0);
    }
    return h;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    if (childCount == 0) return constraints.smallest;
    final w = _width(constraints);
    final tile = BoxConstraints.tightFor(width: _tileWidth(w));
    final heights = [for (final k in getChildrenAsList()) k.getDryLayout(tile).height];
    return constraints.constrain(Size(w, _total(_rowHeights(heights))));
  }

  @override
  void performLayout() {
    final kids = getChildrenAsList();
    if (kids.isEmpty) {
      size = constraints.smallest;
      return;
    }
    final w = _width(constraints);
    final tileW = _tileWidth(w);
    final heights = <double>[];
    for (final k in kids) {
      k.layout(BoxConstraints.tightFor(width: tileW), parentUsesSize: true);
      heights.add(k.size.height);
    }
    final rows = _rowHeights(heights);
    final tops = <double>[];
    var y = 0.0;
    for (var r = 0; r < rows.length; r++) {
      if (r > 0) y += _gapAbove(r);
      tops.add(y);
      y += rows[r];
    }
    final lastRowCount = childCount - (_rows - 1) * _cols;
    for (var i = 0; i < kids.length; i++) {
      final (r, c) = _cell(i);
      final k = kids[i];
      if (heights[i] != rows[r]) k.layout(BoxConstraints.tightFor(width: tileW, height: rows[r]), parentUsesSize: true);
      // An incomplete last row (row-major) is centered.
      final shift = !_columnMajor && r == _rows - 1 ? (_cols - lastRowCount) * (tileW + _spacing) / 2 : 0.0;
      (k.parentData! as _GridParentData).offset = Offset(c * (tileW + _spacing) + shift, tops[r]);
    }
    size = constraints.constrain(Size(w, _total(rows)));
  }

  double _intrinsicHeight(double width, double Function(RenderBox, double) f) {
    if (childCount == 0) return 0;
    final tileW = width.isFinite ? _tileWidth(width) : double.infinity;
    return _total(_rowHeights([for (final k in getChildrenAsList()) f(k, tileW)]));
  }

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width, (k, w) => k.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width, (k, w) => k.getMaxIntrinsicHeight(w));

  double _intrinsicWidth(double Function(RenderBox) f) {
    if (childCount == 0) return 0;
    final widest = getChildrenAsList().fold(0.0, (a, k) => math.max(a, f(k)));
    return widest * _cols + _spacing * (_cols - 1);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _intrinsicWidth((k) => k.getMinIntrinsicWidth(double.infinity));

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsicWidth((k) => k.getMaxIntrinsicWidth(double.infinity));

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
