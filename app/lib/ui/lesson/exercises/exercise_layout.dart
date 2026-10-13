import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

enum ExerciseLayoutSlot { prompt, controls }

/// Lays out an exercise as a [prompt] at the top and its interactive
/// [controls] (options, tiles, grid, buttons) at the bottom, in the thumb
/// zone. Both span the full width.
///
/// When the incoming constraints have a minimum height (the player gives the
/// visible height of its scroll view), the free space goes between the two,
/// so the controls sit at the bottom of the screen. When the content is taller
/// than that, the two simply stack with [gap] between them and the parent
/// scrolls. Without a minimum height (tests, embedding) it is a plain column.
class ExerciseLayout extends SlottedMultiChildRenderObjectWidget<ExerciseLayoutSlot, RenderBox> {
  const ExerciseLayout({super.key, required this.prompt, required this.controls, this.gap = 24});

  final Widget prompt;
  final Widget controls;
  final double gap;

  @override
  Iterable<ExerciseLayoutSlot> get slots => ExerciseLayoutSlot.values;

  @override
  Widget? childForSlot(ExerciseLayoutSlot slot) => switch (slot) {
    ExerciseLayoutSlot.prompt => prompt,
    ExerciseLayoutSlot.controls => controls,
  };

  @override
  RenderExerciseLayout createRenderObject(BuildContext context) => RenderExerciseLayout(gap);

  @override
  void updateRenderObject(BuildContext context, RenderExerciseLayout renderObject) => renderObject.gap = gap;
}

class RenderExerciseLayout extends RenderBox with SlottedContainerRenderObjectMixin<ExerciseLayoutSlot, RenderBox> {
  RenderExerciseLayout(this._gap);

  double _gap;
  double get gap => _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  RenderBox? get _prompt => childForSlot(ExerciseLayoutSlot.prompt);
  RenderBox? get _controls => childForSlot(ExerciseLayoutSlot.controls);

  List<RenderBox> get _kids => [?_prompt, ?_controls];

  BoxConstraints _childConstraints(BoxConstraints c) =>
      c.hasBoundedWidth ? BoxConstraints.tightFor(width: c.maxWidth) : const BoxConstraints();

  Size _size(BoxConstraints c, Size p, Size k) {
    final w = c.hasBoundedWidth ? c.maxWidth : math.max(p.width, k.width);
    return c.constrain(Size(w, p.height + _gap + k.height));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final cc = _childConstraints(constraints);
    final p = _prompt?.getDryLayout(cc) ?? Size.zero;
    final k = _controls?.getDryLayout(cc) ?? Size.zero;
    return _size(constraints, p, k);
  }

  @override
  void performLayout() {
    final cc = _childConstraints(constraints);
    final p = _prompt, k = _controls;
    p?.layout(cc, parentUsesSize: true);
    k?.layout(cc, parentUsesSize: true);
    final ps = p?.size ?? Size.zero, ks = k?.size ?? Size.zero;
    size = _size(constraints, ps, ks);
    if (p != null) (p.parentData! as BoxParentData).offset = Offset.zero;
    if (k != null) {
      final y = math.max(ps.height + _gap, size.height - ks.height);
      (k.parentData! as BoxParentData).offset = Offset(0, y);
    }
  }

  double _sum(double Function(RenderBox) f) => _kids.fold(0.0, (a, c) => a + f(c)) + _gap;
  double _max(double Function(RenderBox) f) => _kids.fold(0.0, (a, c) => math.max(a, f(c)));

  @override
  double computeMinIntrinsicWidth(double height) => _max((c) => c.getMinIntrinsicWidth(double.infinity));

  @override
  double computeMaxIntrinsicWidth(double height) => _max((c) => c.getMaxIntrinsicWidth(double.infinity));

  @override
  double computeMinIntrinsicHeight(double width) => _sum((c) => c.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) => _sum((c) => c.getMaxIntrinsicHeight(width));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _prompt?.getDistanceToActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final c in _kids) {
      context.paintChild(c, offset + (c.parentData! as BoxParentData).offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final c in [?_controls, ?_prompt]) {
      final o = (c.parentData! as BoxParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: o,
        position: position,
        hitTest: (r, transformed) => c.hitTest(r, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}
