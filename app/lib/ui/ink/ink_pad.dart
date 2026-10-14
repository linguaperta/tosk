/// The handwriting pad (v0.5): a large writing area at the bottom of
/// production exercises, with Undo, Clear, a keyboard fallback and an
/// optional "Next cell" / "Space" action.
///
/// * **Drawing.** Plain Flutter painting (a [CustomPaint] over the strokes),
///   fed by raw pointer events. An eager gesture recognizer claims every
///   pointer on the pad, so writing never scrolls the exercise. Once a stylus
///   has touched the pad, finger touches are ignored (palm rejection).
/// * **ONYX.** On Boox devices ([penSurfaceProvider]) the Onyx pen SDK draws
///   the stylus strokes itself with low latency (raw drawing inside the pad's
///   rectangle, tracked every frame and paused while another route covers the
///   pad); its strokes come back over the platform channel and are painted
///   here too. Fingers still draw through Flutter. If the SDK fails to open,
///   the pad simply keeps drawing with Flutter.
/// * **Recognition.** 450 ms after the last stroke (or at once on the action
///   button) the strokes go to the [InkRecognizer] with the course's model and
///   [InkPad.preContext]; the candidates (best first) are reported through
///   [InkPad.onChanged] as an [InkResult].
/// * **Segments.** With [InkPad.segmented] (whole sentences) "Space" commits
///   what was written and clears the pad, so a long sentence can be written in
///   parts; the result joins the parts and combines their candidates.
/// * **Model.** Until the course's recognition model is on the device the pad
///   shows its status: the one-time download (about 20 MB, Wi-Fi suggested),
///   progress, errors with Retry, or that the language has no model. The
///   keyboard fallback works in every state.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../device/device_providers.dart';
import '../../device/onyx.dart';
import '../../ink/ink_recognizer.dart';
import '../../providers.dart' show reduceMotionProvider;
import '../lesson/typing.dart';
import '../theme/bw_skin.dart';
import 'ink_providers.dart';

/// What the pad read (or the keyboard fallback typed).
@immutable
class InkResult {
  const InkResult(this.candidates, {this.inputMode = InputMode.ink});

  /// Best first; never empty.
  final List<String> candidates;
  final InputMode inputMode;

  String get text => candidates.first;

  /// As an answer: the best candidate, the next ones as alternatives.
  TextAnswer toAnswer({int topK = kInkTopK}) => TextAnswer(
        text,
        inputMode: inputMode,
        candidates: candidates.length > 1 ? candidates.sublist(1, math.min(candidates.length, topK)) : const [],
      );
}

/// Recognizer candidates that count (the engine accepts any of them).
const int kInkTopK = 3;

/// Combines the candidates of written parts into whole answers: every
/// combination of each part's top [perPart], best (lowest rank sum) first,
/// at most [max].
List<String> combineSegments(List<List<String>> parts, {int perPart = kInkTopK, int max = 9}) {
  final lists = [for (final p in parts) if (p.isNotEmpty) p.take(perPart).toList()];
  if (lists.isEmpty) return const [];
  var combos = <(int, List<String>)>[(0, const [])];
  for (final l in lists) {
    combos = [
      for (final (rank, words) in combos)
        for (var i = 0; i < l.length; i++) (rank + i, [...words, l[i]]),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (combos.length > max * 3) combos = combos.sublist(0, max * 3);
  }
  final seen = <String>{};
  return [
    for (final (_, words) in combos)
      if (seen.add(words.join(' '))) words.join(' '),
  ].take(max).toList();
}

class InkPad extends ConsumerStatefulWidget {
  const InkPad({
    super.key,
    required this.onChanged,
    this.preContext,
    this.enabled = true,
    this.height,
    this.hintText = 'Write here',
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.segmented = false,
    this.padKey = const ValueKey('ink-pad'),
  });

  /// The current reading (null when the pad is empty).
  final ValueChanged<InkResult?> onChanged;

  /// Text just before what is written (words before a gap, a verb stem).
  final String? preContext;
  final bool enabled;

  /// Pad height; by default about a quarter of the screen (150–240 px).
  final double? height;
  final String hintText;

  /// An extra action (the grid's "Next cell"), run after recognition.
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  /// Whole sentences: a "Space" action commits a part and clears the pad.
  final bool segmented;
  final Key padKey;

  @override
  ConsumerState<InkPad> createState() => InkPadState();
}

class InkPadState extends ConsumerState<InkPad> {
  final List<InkStroke> _strokes = [];
  List<InkPoint>? _current;
  int? _pointer;
  bool _stylusSeen = false;

  /// Committed parts (segmented): each part's candidates.
  final List<List<String>> _parts = [];
  List<String> _reading = const [];
  bool _recognizing = false;
  int _seq = 0;
  Timer? _debounce;
  bool _keyboard = false;

  // Onyx raw drawing.
  PenSurface? _pen;
  bool _penOpen = false;
  bool _penFailed = false;
  bool _penEnabled = false;
  Rect? _penRect;
  StreamSubscription<PenPoints>? _penStrokes;
  StreamSubscription<PenPoints>? _penErase;
  final _padBox = GlobalKey();
  bool _frameLoop = false;
  ModalRoute<Object?>? _route;
  bool _tickers = true;

  @override
  void dispose() {
    _debounce?.cancel();
    _closePen();
    super.dispose();
  }

  // ------------------------------------------------------------ results

  List<String> get _combined => widget.segmented ? combineSegments([..._parts, _reading]) : _reading;

  void _report() {
    final c = _combined;
    widget.onChanged(c.isEmpty ? null : InkResult(c));
  }

  void _scheduleRecognition({Duration delay = const Duration(milliseconds: 450)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, () => unawaited(_recognize()));
  }

  Future<void> _recognize() async {
    _debounce?.cancel();
    final model = ref.read(inkModelProvider);
    final tag = model.tag;
    final seq = ++_seq;
    if (_strokes.isEmpty || tag == null || !model.ready) {
      setState(() {
        _reading = const [];
        _recognizing = false;
      });
      _report();
      return;
    }
    setState(() => _recognizing = true);
    final box = _padBox.currentContext?.size;
    final pre = [widget.preContext ?? '', ..._parts.map((p) => p.first)].join(' ').trimLeft();
    List<String> out;
    try {
      out = await ref.read(inkRecognizerProvider).recognize(
            List.of(_strokes),
            tag,
            preContext: pre.isEmpty ? null : pre,
            area: box,
          );
    } catch (e) {
      debugPrint('[ink] recognition failed: $e');
      out = const [];
    }
    if (!mounted || seq != _seq) return;
    setState(() {
      _reading = out;
      _recognizing = false;
    });
    _report();
  }

  // ------------------------------------------------------------ actions

  void _undo() {
    if (_strokes.isEmpty) {
      if (widget.segmented && _parts.isNotEmpty) {
        setState(() => _reading = _parts.removeLast());
        _report();
      }
      return;
    }
    setState(() => _strokes.removeLast());
    _syncPenOverlay();
    _strokes.isEmpty ? unawaited(_recognize()) : _scheduleRecognition(delay: Duration.zero);
  }

  /// Clears the pad (and, segmented, every part).
  void clear() {
    _debounce?.cancel();
    _seq++;
    setState(() {
      _strokes.clear();
      _current = null;
      _parts.clear();
      _reading = const [];
      _recognizing = false;
    });
    _syncPenOverlay(force: true);
    widget.onChanged(null);
  }

  /// Segmented: commits the current part and starts a fresh pad.
  Future<void> _space() async {
    if (_strokes.isNotEmpty) await _recognize();
    if (!mounted || _reading.isEmpty) return;
    setState(() {
      _parts.add(_reading);
      _reading = const [];
      _strokes.clear();
    });
    _syncPenOverlay(force: true);
    _report();
  }

  Future<void> _runAction() async {
    if (_strokes.isNotEmpty && (_debounce?.isActive ?? false)) await _recognize();
    if (!mounted) return;
    widget.onAction?.call();
  }

  /// Starts empty again (the grid moved to another cell).
  void reset() => clear();

  // ------------------------------------------------------------ pointer input

  bool get _penActive => _penOpen && _penEnabled;

  bool _accepts(PointerEvent e) {
    if (!widget.enabled || _keyboard) return false;
    final stylus = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    // The Onyx SDK draws stylus strokes and sends them over the channel.
    if (stylus && _penActive) return false;
    if (stylus) _stylusSeen = true;
    // Palm rejection: once a stylus wrote here, fingers don't.
    if (!stylus && _stylusSeen && e.kind == PointerDeviceKind.touch) return false;
    return true;
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null || !_accepts(e) || !ref.read(inkModelProvider).ready) return;
    _debounce?.cancel();
    _pointer = e.pointer;
    setState(() => _current = [InkPoint(e.localPosition.dx, e.localPosition.dy, e.timeStamp.inMilliseconds)]);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _current == null) return;
    setState(() => _current!.add(InkPoint(e.localPosition.dx, e.localPosition.dy, e.timeStamp.inMilliseconds)));
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final s = _current;
    _current = null;
    if (s == null) return;
    if (e is PointerCancelEvent) {
      setState(() {});
      return;
    }
    setState(() => _strokes.add(s));
    _scheduleRecognition();
  }

  // ------------------------------------------------------------ Onyx pen

  void _ensurePen() {
    final pen = ref.read(penSurfaceProvider);
    if (pen == null || _penFailed) return;
    if (!_frameLoop) {
      _frameLoop = true;
      SchedulerBinding.instance.addPostFrameCallback(_onFrame);
    }
  }

  /// After every frame while mounted: keeps the raw-drawing rectangle on the
  /// pad, and pauses it when the pad is disabled or covered by another route.
  void _onFrame(Duration _) {
    if (!mounted) {
      _frameLoop = false;
      return;
    }
    final pen = ref.read(penSurfaceProvider);
    if (pen == null || _penFailed) {
      _frameLoop = false;
      _closePen();
      return;
    }
    final box = _padBox.currentContext?.findRenderObject() as RenderBox?;
    final visible = box != null &&
        box.attached &&
        box.hasSize &&
        widget.enabled &&
        !_keyboard &&
        ref.read(inkModelProvider).ready &&
        (_route?.isCurrent ?? true) &&
        _tickers;
    if (visible) {
      final dpr = View.of(context).devicePixelRatio;
      final topLeft = box.localToGlobal(Offset.zero);
      final rect = Rect.fromLTWH(topLeft.dx * dpr, topLeft.dy * dpr, box.size.width * dpr, box.size.height * dpr);
      unawaited(_openOrMove(pen, rect));
    } else if (_penOpen && _penEnabled) {
      _penEnabled = false;
      unawaited(pen.setEnabled(false));
    }
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
    // Frames stop when nothing changes; one more keeps the rect in sync after
    // a scroll settles.
  }

  Future<void> _openOrMove(PenSurface pen, Rect rect) async {
    if (!_penOpen) {
      if (_pen != null) return; // opening
      _pen = pen;
      final ok = await pen.open(rect, strokeWidth: 3);
      if (!mounted) {
        if (ok) unawaited(pen.close());
        return;
      }
      if (!ok) {
        setState(() => _penFailed = true);
        _pen = null;
        return;
      }
      _penOpen = true;
      _penEnabled = true;
      _penRect = rect;
      _penStrokes = pen.strokes.listen(_onPenStroke);
      _penErase = pen.erasures.listen(_onPenErase);
      setState(() {});
      return;
    }
    if (_penRect != rect) {
      _penRect = rect;
      await pen.setRect(rect);
    }
    if (!_penEnabled) {
      _penEnabled = true;
      await pen.setEnabled(true);
    }
  }

  Offset? _toLocal((double, double, int) p) {
    final box = _padBox.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final dpr = View.of(context).devicePixelRatio;
    return box.globalToLocal(Offset(p.$1 / dpr, p.$2 / dpr));
  }

  void _onPenStroke(PenPoints points) {
    if (!mounted || !widget.enabled) return;
    final stroke = <InkPoint>[
      for (final p in points)
        if (_toLocal(p) case final o?) InkPoint(o.dx, o.dy, p.$3),
    ];
    if (stroke.isEmpty) return;
    setState(() => _strokes.add(stroke));
    _scheduleRecognition();
  }

  void _onPenErase(PenPoints points) {
    if (!mounted || !widget.enabled) return;
    final erased = [for (final p in points) ?_toLocal(p)];
    final before = _strokes.length;
    setState(() {
      _strokes.removeWhere((s) => s.any((q) => erased.any((o) => (Offset(q.x, q.y) - o).distance < 14)));
    });
    if (_strokes.length != before) {
      _syncPenOverlay(force: true);
      _strokes.isEmpty ? unawaited(_recognize()) : _scheduleRecognition(delay: Duration.zero);
    }
  }

  /// The e-ink overlay keeps what the pen drew; after an undo or clear it is
  /// dropped so the pad shows the remaining strokes (painted by Flutter).
  void _syncPenOverlay({bool force = false}) {
    if (_penOpen) unawaited(_pen?.clear());
  }

  void _closePen() {
    unawaited(_penStrokes?.cancel());
    unawaited(_penErase?.cancel());
    _penStrokes = null;
    _penErase = null;
    final pen = _pen;
    if (pen != null && _penOpen) unawaited(pen.close());
    _pen = null;
    _penOpen = false;
    _penEnabled = false;
  }

  // ------------------------------------------------------------ build

  @override
  void didUpdateWidget(InkPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _debounce?.cancel();
      if (_penOpen) {
        _penEnabled = false;
        unawaited(_pen?.setEnabled(false));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(inkModelProvider);
    ref.watch(penSurfaceProvider);
    // For the Onyx pen: paused while another route covers the pad.
    _route = ModalRoute.of(context);
    _tickers = TickerMode.valuesOf(context).enabled;
    final mono = isMonochrome(Theme.of(context).colorScheme);
    final size = MediaQuery.sizeOf(context);
    final height = widget.height ?? (size.height * 0.28).clamp(150.0, 240.0);
    final reading = _combined;

    if (!widget.enabled) {
      // Checked: just what was read (the exercise shows the marks).
      return _ReadingLine(text: reading.isEmpty ? null : reading.first, busy: false, mono: mono);
    }
    if (_keyboard) return _keyboardFallback(context);
    if (model.ready) _ensurePen();

    final Widget area = model.ready
        ? _canvas(context, height, mono)
        : SizedBox(
            height: height,
            child: _ModelPanel(state: model, mono: mono),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ReadingLine(
          text: reading.isEmpty ? null : reading.first,
          busy: _recognizing,
          mono: mono,
          parts: widget.segmented ? _parts.length : 0,
        ),
        const SizedBox(height: 8),
        area,
        const SizedBox(height: 8),
        _toolbar(context, model.ready, mono),
      ],
    );
  }

  Widget _canvas(BuildContext context, double height, bool mono) {
    final scheme = Theme.of(context).colorScheme;
    final ink = mono ? kBwBlack : scheme.onSurface;
    return Semantics(
      label: 'Writing pad. ${widget.hintText}',
      container: true,
      child: RawGestureDetector(
        // Claims every pointer on the pad at once, so writing never scrolls.
        gestures: {
          EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            EagerGestureRecognizer.new,
            (_) {},
          ),
        },
        child: Listener(
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: Container(
            key: widget.padKey,
            height: height,
            decoration: BoxDecoration(
              color: mono ? kBwWhite : scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: mono ? kBwBlack : scheme.outline, width: mono ? kBwBorder : 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: CustomPaint(
                key: _padBox,
                painter: _InkPainter(
                  strokes: _strokes,
                  current: _current,
                  ink: ink,
                  guide: mono ? kBwGray : scheme.outlineVariant,
                ),
                child: _strokes.isEmpty && _current == null
                    ? Center(
                        child: Text(
                          widget.hintText,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: mono ? kBwGray : scheme.onSurfaceVariant,
                              ),
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context, bool ready, bool mono) {
    final hasInk = _strokes.isNotEmpty || _parts.isNotEmpty;
    Widget button(String key, IconData icon, String label, VoidCallback? onPressed) => Tooltip(
          message: label,
          child: OutlinedButton(
            key: ValueKey(key),
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 12)),
            child: Semantics(label: label, excludeSemantics: true, child: Icon(icon)),
          ),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        button('ink-undo', Icons.undo, 'Undo stroke', ready && hasInk ? _undo : null),
        button('ink-clear', Icons.backspace_outlined, 'Clear', ready && hasInk ? clear : null),
        button('ink-keyboard', Icons.keyboard_outlined, 'Type instead', () {
          clear();
          setState(() => _keyboard = true);
        }),
        if (widget.segmented)
          OutlinedButton.icon(
            key: const ValueKey('ink-space'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: ready && _strokes.isNotEmpty ? () => unawaited(_space()) : null,
            icon: const Icon(Icons.space_bar),
            label: const Text('Next word'),
          ),
        if (widget.onAction != null)
          FilledButton.icon(
            key: const ValueKey('ink-action'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => unawaited(_runAction()),
            icon: Icon(widget.actionIcon ?? Icons.arrow_forward),
            label: Text(widget.actionLabel ?? 'Next'),
          ),
      ],
    );
  }

  Widget _keyboardFallback(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TypedAnswerField(
            fieldKey: const ValueKey('ink-typed'),
            autofocus: true,
            multiline: widget.segmented,
            hintText: 'Type your answer',
            onChanged: (t) => widget.onChanged(t.trim().isEmpty ? null : InkResult([t], inputMode: InputMode.keyboard)),
            onSubmitted: widget.onAction,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('ink-back-to-pad'),
              onPressed: () {
                widget.onChanged(null);
                setState(() => _keyboard = false);
              },
              icon: const Icon(Icons.draw_outlined),
              label: const Text('Write instead'),
            ),
          ),
          if (widget.onAction != null)
            FilledButton.icon(
              key: const ValueKey('ink-action'),
              onPressed: widget.onAction,
              icon: Icon(widget.actionIcon ?? Icons.arrow_forward),
              label: Text(widget.actionLabel ?? 'Next'),
            ),
        ],
      );
}

/// "Read as: …" above the pad.
class _ReadingLine extends StatelessWidget {
  const _ReadingLine({required this.text, required this.busy, required this.mono, this.parts = 0});
  final String? text;
  final bool busy;
  final bool mono;
  final int parts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('ink-reading'),
        constraints: const BoxConstraints(minHeight: 40),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(Icons.draw_outlined, size: 20, color: mono ? kBwBlack : scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text == null ? (busy ? 'Reading…' : 'Nothing written yet') : 'Read as: $text',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text == null
                    ? theme.textTheme.bodyMedium?.copyWith(color: mono ? kBwGray : scheme.onSurfaceVariant)
                    : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (busy) const Icon(Icons.hourglass_empty, size: 18),
          ],
        ),
      ),
    );
  }
}

/// The recognition model isn't ready: download, progress, errors.
class _ModelPanel extends ConsumerWidget {
  const _ModelPanel({required this.state, required this.mono});
  final InkModelState state;
  final bool mono;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = state.tag == null ? 'this language' : inkModelName(state.tag!);
    final ctl = ref.read(inkModelProvider.notifier);
    final (String text, Widget? action) = switch (state.status) {
      InkModelStatus.checking => ('Checking the handwriting model…', null),
      InkModelStatus.ready => ('', null),
      InkModelStatus.missing => (
          'Handwriting needs the $name recognition model: a one-time download of about 20 MB '
              '(Wi-Fi recommended). After that it works offline.',
          FilledButton.icon(
            key: const ValueKey('ink-download'),
            onPressed: () => unawaited(ctl.download()),
            icon: const Icon(Icons.download),
            label: const Text('Download'),
          ),
        ),
      InkModelStatus.downloading => ('Downloading the $name handwriting model…', null),
      InkModelStatus.unsupported => ("Handwriting isn't available for this language here. Type instead.", null),
      InkModelStatus.error => (
          "The handwriting model couldn't be loaded. Check the connection and try again.",
          OutlinedButton.icon(
            key: const ValueKey('ink-retry'),
            onPressed: () => unawaited(state.tag == null ? ctl.refresh() : ctl.download()),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
    };
    final busy = state.status == InkModelStatus.checking || state.status == InkModelStatus.downloading;
    // No moving bar with reduced motion (e-ink): an hourglass instead.
    final reduce = ref.watch(reduceMotionProvider);
    return Container(
      key: const ValueKey('ink-model'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mono ? kBwWhite : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mono ? kBwBlack : scheme.outlineVariant, width: mono ? kBwBorder : 1),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            if (busy) ...[
              const SizedBox(height: 12),
              // ML Kit reports no byte progress: an indeterminate bar.
              reduce
                  ? const Icon(Icons.hourglass_empty, key: ValueKey('ink-progress'))
                  : const LinearProgressIndicator(key: ValueKey('ink-progress')),
            ],
            if (action != null) ...[const SizedBox(height: 12), Center(child: action)],
          ],
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter({required this.strokes, required this.current, required this.ink, required this.guide})
  ;

  final List<InkStroke> strokes;
  final List<InkPoint>? current;
  final Color ink;
  final Color guide;

  @override
  void paint(Canvas canvas, Size size) {
    // A writing line at two thirds of the height.
    final y = size.height * 0.68;
    final g = Paint()
      ..color = guide
      ..strokeWidth = 1.5;
    for (var x = 12.0; x < size.width - 12; x += 14) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 7, size.width - 12), y), g);
    }
    final p = Paint()
      ..color = ink
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final s in [...strokes, ?current]) {
      if (s.isEmpty) continue;
      if (s.length == 1) {
        canvas.drawCircle(Offset(s.first.x, s.first.y), 1.8, p..style = PaintingStyle.fill);
        p.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.x, s.first.y);
      for (final q in s.skip(1)) {
        path.lineTo(q.x, q.y);
      }
      canvas.drawPath(path, p);
    }
  }

  // The stroke lists change in place: always repaint (cheap: a few paths).
  @override
  bool shouldRepaint(_InkPainter old) => true;
}
