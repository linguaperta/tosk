import 'package:flutter/material.dart';

import '../../../core/core.dart';
import '../../ink/ink_pad.dart';
import '../../theme/bw_skin.dart';
import '../typing.dart';
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
    super.onCheck,
    this.typed = false,
    this.ink = false,
  });

  /// Typing mode: every asked cell is a text field (no tile bank).
  final bool typed;

  /// Handwriting: tap a cell (or start at the first), write its form on the
  /// pad below the table, "Next cell" moves on. No tile bank.
  final bool ink;

  @override
  State<ConjGridView> createState() => _ConjGridViewState();
}

class _ConjGridViewState extends State<ConjGridView> with ExerciseKeysMixin<ConjGridView> {
  /// cell index -> tile index
  final Map<int, int> _filled = {};
  int? _selectedCell;

  /// Typing mode: one controller and focus node per asked cell.
  final Map<int, TextEditingController> _inputs = {};
  final Map<int, FocusNode> _focus = {};

  /// The cell the accent bar types into (the focused one, or the last one).
  int? _activeInput;

  /// Handwriting: what the pad read per cell (best first).
  final Map<int, List<String>> _written = {};
  final _pad = GlobalKey<InkPadState>();

  @override
  void initState() {
    super.initState();
    _selectedCell = _nextEmpty(-1);
    if (widget.typed) {
      for (var i = 0; i < _cells.length; i++) {
        if (_cells[i].prefilled) continue;
        _inputs[i] = TextEditingController()..addListener(_reportTyped);
        _focus[i] = FocusNode(debugLabel: 'grid-input-$i')
          ..addListener(() {
            if (_focus[i]!.hasFocus) _activeInput = i;
          });
      }
      _activeInput = _inputs.keys.firstOrNull;
    }
  }

  @override
  void dispose() {
    for (final c in _inputs.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  String _typedText(int i) => _inputs[i]?.text.trim() ?? '';

  void _reportTyped() {
    if (widget.locked) return;
    final complete = _inputs.keys.every((i) => _typedText(i).isNotEmpty);
    widget.onChanged(
      complete
          ? GridAnswer([
              for (var i = 0; i < _cells.length; i++) _cells[i].prefilled ? '' : _typedText(i),
            ], inputMode: InputMode.keyboard)
          : null,
    );
    setState(() {});
  }

  /// Enter in a cell: the next empty cell, or Check when all are filled.
  void _submitTyped(int i) {
    final keys = _inputs.keys.toList()..sort();
    for (final k in [...keys.where((k) => k > i), ...keys.where((k) => k <= i)]) {
      if (_typedText(k).isEmpty) {
        _focus[k]!.requestFocus();
        return;
      }
    }
    widget.onCheck?.call();
  }

  List<GridCell> get _cells => widget.exercise.cells;

  // ------------------------------------------------------------ handwriting

  int? _nextUnwritten(int after) {
    for (var k = 1; k <= _cells.length; k++) {
      final i = (after + k) % _cells.length;
      if (!_cells[i].prefilled && !_written.containsKey(i)) return i;
    }
    return null;
  }

  void _onWritten(InkResult? r) {
    final cell = _selectedCell;
    if (widget.locked || cell == null) return;
    setState(() {
      if (r == null) {
        _written.remove(cell);
      } else {
        _written[cell] = r.candidates;
      }
    });
    _reportWritten();
  }

  void _reportWritten() {
    final asked = [for (var i = 0; i < _cells.length; i++) if (!_cells[i].prefilled) i];
    final complete = asked.every(_written.containsKey);
    widget.onChanged(
      complete
          ? GridAnswer(
              [for (var i = 0; i < _cells.length; i++) _cells[i].prefilled ? '' : _written[i]!.first],
              inputMode: InputMode.ink,
              candidates: [
                for (var i = 0; i < _cells.length; i++)
                  _cells[i].prefilled ? const <String>[] : _written[i]!.skip(1).take(kInkTopK - 1).toList(),
              ],
            )
          : null,
    );
  }

  /// "Next cell": the next cell without writing (or Check when all are written).
  void _nextCell() {
    final cell = _selectedCell ?? -1;
    final next = _nextUnwritten(cell);
    if (next == null) {
      widget.onCheck?.call();
      return;
    }
    _pad.currentState?.reset();
    setState(() => _selectedCell = next);
  }

  void _tapWrittenCell(int i) {
    if (widget.locked || _cells[i].prefilled) return;
    _pad.currentState?.reset();
    setState(() {
      _written.remove(i);
      _selectedCell = i;
    });
    _reportWritten();
  }

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
    if (widget.typed || widget.ink) return;
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
          if (widget.ink) ...[
            if (!widget.locked) ...[
              const SizedBox(height: 8),
              InkPad(
                key: _pad,
                padKey: const ValueKey('grid-ink-pad'),
                height: 150,
                hintText: _selectedCell == null ? 'Write here' : 'Write: ${_cells[_selectedCell!].personLabel}',
                preContext: _selectedCell == null ? null : _cells[_selectedCell!].personLabel.split(RegExp(r'[ /(]')).first,
                actionLabel: _nextUnwritten(_selectedCell ?? -1) == null ? 'Done' : 'Next cell',
                actionIcon: Icons.arrow_downward,
                onAction: _nextCell,
                onChanged: _onWritten,
              ),
            ],
          ] else if (widget.typed) ...[
            if (!widget.locked)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: AccentBar(
                  letters: AccentLetters.of(context),
                  onInsert: (l) {
                    final i = _activeInput;
                    if (i == null) return;
                    insertAtCursor(_inputs[i]!, l);
                    _focus[i]!.requestFocus();
                  },
                ),
              ),
          ] else ...[
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
    if (widget.typed && !widget.locked && !c.prefilled) return _typedCell(context, i);
    final selected = !widget.locked && _selectedCell == i && !widget.typed;
    final String text;
    final ink = widget.ink;
    final TextStyle? style;
    if (c.prefilled) {
      text = c.expected;
      style = theme.textTheme.bodyLarge?.copyWith(color: scheme.outline, fontStyle: FontStyle.italic);
    } else {
      text = ink
          ? (_written[i]?.first ?? '')
          : widget.typed
          ? _typedText(i)
          : (tile == null ? '' : widget.exercise.tiles[tile]);
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
          onTap: c.prefilled || widget.locked ? null : () => ink ? _tapWrittenCell(i) : _tapCell(i),
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

  /// Typing mode: an asked cell as a text field (48 px tall).
  Widget _typedCell(BuildContext context, int i) {
    final keys = _inputs.keys.toList()..sort();
    return Semantics(
      label: _cells[i].personLabel,
      child: TextField(
        key: ValueKey('grid-input-$i'),
        controller: _inputs[i],
        focusNode: _focus[i],
        autofocus: keys.isNotEmpty && keys.first == i,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: i == keys.last ? TextInputAction.done : TextInputAction.next,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          isDense: true,
          constraints: const BoxConstraints(minHeight: 48),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onSubmitted: (_) => _submitTyped(i),
      ),
    );
  }
}
