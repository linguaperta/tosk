import 'package:flutter/material.dart';

import '../../../core/core.dart';
import '../../theme/bw_skin.dart';
import 'common.dart';

/// Fill a whole tense table: tap a cell, then a form from the bank. Prefilled
/// cells are shown greyed. Tapping a filled cell puts its tile back.
class ConjGridView extends ExerciseWidget<ConjGridExercise> {
  const ConjGridView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.result,
    super.keys,
    super.reduceMotion,
  });

  @override
  State<ConjGridView> createState() => _ConjGridViewState();
}

class _ConjGridViewState extends State<ConjGridView> with ExerciseKeysMixin<ConjGridView> {
  /// cell index -> tile index
  final Map<int, int> _filled = {};
  int? _selectedCell;

  @override
  void initState() {
    super.initState();
    _selectedCell = _nextEmpty(-1);
  }

  List<GridCell> get _cells => widget.exercise.cells;

  int? _nextEmpty(int after) {
    for (var k = 1; k <= _cells.length; k++) {
      final i = (after + k) % _cells.length;
      if (i < 0) continue;
      if (!_cells[i].prefilled && !_filled.containsKey(i)) return i;
    }
    return null;
  }

  void _tapCell(int i) {
    if (widget.locked || _cells[i].prefilled) return;
    setState(() {
      _filled.remove(i);
      _selectedCell = i;
    });
    _report();
  }

  void _tapTile(int t) {
    if (widget.locked || _filled.containsValue(t)) return;
    final cell = _selectedCell ?? _nextEmpty(-1);
    if (cell == null) return;
    setState(() {
      _filled[cell] = t;
      _selectedCell = _nextEmpty(cell);
    });
    _report();
  }

  void _report() {
    final e = widget.exercise;
    final complete = [for (var i = 0; i < _cells.length; i++) i]
        .every((i) => _cells[i].prefilled || _filled.containsKey(i));
    widget.onChanged(
      complete
          ? GridAnswer([for (var i = 0; i < _cells.length; i++) _cells[i].prefilled ? '' : e.tiles[_filled[i]!]])
          : null,
    );
  }

  @override
  void onDigit(int n) {
    if (n >= 1 && n <= widget.exercise.tiles.length) _tapTile(n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final theme = Theme.of(context);
    final marks = widget.result?.cellCorrect;
    return ExerciseLayout(
      prompt: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InstructionText(e.instruction),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: e.lemma,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (e.gloss.isNotEmpty) TextSpan(text: '  ·  ${e.gloss}'),
                TextSpan(
                  text: '  ·  ${e.tenseLabel}',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
      gap: 16,
      controls: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Person labels take the width they need (up to 40 %), so
          // "lui/lei (he/she)" isn't cut off; long ones wrap to two lines.
          Table(
            columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (var i = 0; i < _cells.length; i++)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 10, bottom: 8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 132),
                        child: Text(
                          _cells[i].personLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _cell(context, i, marks == null || i >= marks.length ? null : marks[i]),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (var t = 0; t < e.tiles.length; t++)
                WordTile(
                  key: ValueKey('grid-tile-$t'),
                  label: e.tiles[t],
                  hidden: _filled.containsValue(t),
                  onTap: widget.locked ? null : () => _tapTile(t),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, int i, bool? mark) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fb = FeedbackColors.of(context);
    final c = _cells[i];
    final tile = _filled[i];
    final selected = !widget.locked && _selectedCell == i;
    final String text;
    final TextStyle? style;
    if (c.prefilled) {
      text = c.expected;
      style = theme.textTheme.bodyLarge?.copyWith(color: scheme.outline, fontStyle: FontStyle.italic);
    } else {
      text = tile == null ? '' : widget.exercise.tiles[tile];
      // Black & white: a wrong form is struck through, a right one bold.
      style = theme.textTheme.bodyLarge?.copyWith(
        decoration: fb.mono && mark == false ? TextDecoration.lineThrough : null,
        decorationThickness: 2,
        fontWeight: fb.mono && mark == true ? FontWeight.w800 : null,
      );
    }
    final Color border = mark == null
        ? (selected ? scheme.secondary : scheme.outlineVariant)
        : (c.prefilled ? scheme.outlineVariant : (mark ? fb.correct : fb.wrong));
    final Color bg = c.prefilled
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
        : mark == null
        ? (selected && !fb.mono ? scheme.secondaryContainer.withValues(alpha: 0.5) : scheme.surface)
        : (mark ? fb.correctContainer : fb.wrongContainer);

    return Semantics(
      button: !c.prefilled,
      selected: selected,
      label: '${c.personLabel}: ${text.isEmpty ? 'empty' : text}',
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: border,
            // Black & white: the selected cell and right answers get a thick border.
            width: fb.mono
                ? ((selected || mark == true) && !c.prefilled ? 3.5 : kBwBorder)
                : (selected || mark != null ? 2 : 1.2),
          ),
        ),
        child: InkWell(
          key: ValueKey('grid-cell-$i'),
          borderRadius: BorderRadius.circular(10),
          onTap: c.prefilled || widget.locked ? null : () => _tapCell(i),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(text, style: style)),
                  if (mark != null && !c.prefilled && !mark)
                    Flexible(
                      child: Text(
                        c.expected,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: fb.correct, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (mark != null && !c.prefilled)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(mark ? Icons.check : Icons.close, size: 18, color: mark ? fb.correct : fb.wrong),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
