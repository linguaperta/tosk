/// Raster caches for the map's static art (see "Map performance" in
/// `docs/ui.md`). Impeller has no raster cache: every frame replays every
/// visible drawing op, and the storybook boughs and stones are thousands of
/// them (hatching, ink bands, clips). These widgets draw such art once into
/// GPU images and then only blit the images while the map scrolls:
///
/// - [RasterArt]: a large static layer (the boughs) cut into tiles of
///   [kRasterTilePx] device pixels. Only tiles in or near the viewport exist;
///   the ones in view are drawn as soon as they are needed, those just
///   outside are prepared ahead, one per frame, and far ones are dropped. It
///   repaints only when the set of tiles in reach changes, never per scroll
///   frame (its own layer just moves).
/// - [CachedPaint]: a small painter (a node's stone) drawn once into an image
///   at the device pixel ratio and redrawn only when the painter changes.
///
/// Images are rendered at the device pixel ratio and drawn 1:1 with nearest
/// sampling, so they look like the vector art they replace (at most half a
/// device pixel off where it was, never blurred).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Tile height of [RasterArt], in device pixels; a tile spans the layer's
/// width (up to [kRasterTileMaxWidthPx], then the layer is cut into columns).
const int kRasterTilePx = 384;
const int kRasterTileMaxWidthPx = 2048;

/// Paint the vector art directly instead of the cached images (tests compare
/// the two).
@visibleForTesting
bool debugDisableMapRasterCache = false;

/// Paints the static art of [RasterArt] that falls in [region] (local
/// coordinates); the canvas is already clipped to it.
typedef RasterArtPainter = void Function(Canvas canvas, Rect region);

/// A static layer the size of its parent, painted by [painter] into tiles
/// (see the library comment). [artKey] identifies the art: when it changes,
/// every tile is redrawn.
class RasterArt extends LeafRenderObjectWidget {
  const RasterArt({super.key, required this.painter, required this.artKey});

  final RasterArtPainter painter;
  final Object artKey;

  static List<ScrollPosition> _positions(BuildContext context) {
    final out = <ScrollPosition>[];
    var s = Scrollable.maybeOf(context);
    while (s != null) {
      out.add(s.position);
      s = Scrollable.maybeOf(s.context);
    }
    return out;
  }

  @override
  RenderRasterArt createRenderObject(BuildContext context) => RenderRasterArt(
    painter: painter,
    artKey: artKey,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    screen: MediaQuery.sizeOf(context),
    positions: _positions(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderRasterArt renderObject) {
    renderObject
      ..painter = painter
      ..artKey = artKey
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..screen = MediaQuery.sizeOf(context)
      ..positions = _positions(context);
  }
}

class _Tile {
  _Tile(this.image, this.rect);
  final ui.Image image;

  /// The tile's area in local coordinates (with its one-pixel overlap).
  final Rect rect;
}

class RenderRasterArt extends RenderBox {
  RenderRasterArt({
    required this._painter,
    required this._artKey,
    required double devicePixelRatio,
    required this._screen,
    required this._positions,
  }) : _dpr = devicePixelRatio;

  /// Tiles drawn so far, all instances (for tests).
  static int debugTileRenders = 0;

  RasterArtPainter _painter;
  set painter(RasterArtPainter v) => _painter = v;

  Object _artKey;
  set artKey(Object v) {
    if (v == _artKey) return;
    _artKey = v;
    _clear();
    markNeedsPaint();
  }

  double _dpr;
  set devicePixelRatio(double v) {
    if (v == _dpr) return;
    _dpr = v;
    _clear();
    markNeedsPaint();
  }

  Size _screen;
  set screen(Size v) {
    if (v == _screen) return;
    _screen = v;
    markNeedsPaint();
  }

  List<ScrollPosition> _positions;
  set positions(List<ScrollPosition> v) {
    if (_listEquals(v, _positions)) return;
    if (attached) {
      for (final p in _positions) {
        p.removeListener(_onScroll);
      }
      for (final p in v) {
        p.addListener(_onScroll);
      }
    }
    _positions = v;
  }

  static bool _listEquals(List<Object> a, List<Object> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  final Map<(int, int), _Tile> _tiles = {};

  /// How many tiles exist right now (for tests).
  @visibleForTesting
  int get debugTileCount => _tiles.length;

  /// How many tiles the whole layer has (for tests).
  @visibleForTesting
  int get debugTilesTotal => hasSize ? (size.width / _tileW).ceil() * (size.height / _tileH).ceil() : 0;

  /// The tiles the last paint drew.
  Set<(int, int)> _drawn = const {};
  bool _prefetchScheduled = false;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (final p in _positions) {
      p.addListener(_onScroll);
    }
  }

  @override
  void detach() {
    for (final p in _positions) {
      p.removeListener(_onScroll);
    }
    super.detach();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final t in _tiles.values) {
      t.image.dispose();
    }
    _tiles.clear();
    _drawn = const {};
  }

  /// Logical size of a tile.
  double get _tileW => size.width * _dpr <= kRasterTileMaxWidthPx ? size.width : kRasterTileMaxWidthPx / 2 / _dpr;
  double get _tileH => kRasterTilePx / _dpr;

  /// What of this box is in view (local coordinates): inside every enclosing
  /// scroll viewport and the screen; everything when unknown.
  Rect _visible() {
    final all = Offset.zero & size;
    if (!attached || !hasSize) return all;
    Rect clip(Matrix4 m, Rect r) => m.determinant() == 0 ? all : MatrixUtils.inverseTransformRect(m, r);
    var v = all.intersect(clip(getTransformTo(null), Offset.zero & _screen));
    for (final p in _positions) {
      final box = p.context.notificationContext?.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) v = v.intersect(clip(getTransformTo(box), Offset.zero & box.size));
    }
    return v.isEmpty ? Rect.fromLTWH(v.left, v.top, 0, 0) : v;
  }

  /// How far beyond the viewport tiles are prepared and kept.
  double get _margin => math.max(_screen.height * 0.25, _tileH);

  Iterable<(int, int)> _tilesIn(Rect r) sync* {
    if (r.isEmpty || !hasSize) return;
    final cols = (size.width / _tileW).ceil(), rows = (size.height / _tileH).ceil();
    final c0 = (r.left / _tileW).floor().clamp(0, cols - 1), c1 = ((r.right - 0.001) / _tileW).floor().clamp(0, cols - 1);
    final r0 = (r.top / _tileH).floor().clamp(0, rows - 1), r1 = ((r.bottom - 0.001) / _tileH).floor().clamp(0, rows - 1);
    for (var y = r0; y <= r1; y++) {
      for (var x = c0; x <= c1; x++) {
        yield (x, y);
      }
    }
  }

  void _onScroll() {
    if (!attached || !hasSize) return;
    // Repaint only when a tile in reach is not drawn yet.
    final want = _visible().inflate(_margin / 2).intersect(Offset.zero & size);
    if (want.isEmpty) return;
    if (!_tilesIn(want).every(_drawn.contains)) markNeedsPaint();
  }

  _Tile _render((int, int) id) {
    debugTileRenders++;
    final (cx, cy) = id;
    // One device pixel of overlap on each side, so no seam shows between tiles.
    final px = 1 / _dpr;
    final rect = Rect.fromLTWH(cx * _tileW - px, cy * _tileH - px, _tileW + 2 * px, _tileH + 2 * px);
    final w = (rect.width * _dpr).round(), h = (rect.height * _dpr).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_dpr);
    canvas.translate(-rect.left, -rect.top);
    canvas.clipRect(rect);
    _painter(canvas, rect);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    return _Tile(image, rect);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (debugDisableMapRasterCache) {
      final canvas = context.canvas;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      _painter(canvas, Offset.zero & size);
      canvas.restore();
      _drawn = _tilesIn(Offset.zero & size).toSet();
      return;
    }
    final visible = _visible();
    final reach = visible.inflate(_margin);
    // In view: drawn now. Just outside: prepared ahead, one per frame.
    for (final id in _tilesIn(visible)) {
      _tiles.putIfAbsent(id, () => _render(id));
    }
    final ahead = [for (final id in _tilesIn(reach)) if (!_tiles.containsKey(id)) id];
    if (ahead.isNotEmpty) {
      _tiles[ahead.first] = _render(ahead.first);
      if (ahead.length > 1 && !_prefetchScheduled) {
        _prefetchScheduled = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _prefetchScheduled = false;
          if (attached) markNeedsPaint();
        });
        SchedulerBinding.instance.ensureVisualUpdate();
      }
    }
    // Drop the tiles far away.
    final keep = _tilesIn(visible.inflate(_margin + _tileH)).toSet();
    _tiles.removeWhere((id, t) {
      if (keep.contains(id)) return false;
      t.image.dispose();
      return true;
    });

    final canvas = context.canvas;
    final paint = Paint()..filterQuality = FilterQuality.none;
    final drawn = <(int, int)>{};
    for (final id in _tilesIn(reach)) {
      final t = _tiles[id];
      if (t == null) continue;
      canvas.drawImageRect(
        t.image,
        Rect.fromLTWH(0, 0, t.image.width.toDouble(), t.image.height.toDouble()),
        t.rect.shift(offset),
        paint,
      );
      drawn.add(id);
    }
    _drawn = drawn;
  }
}

/// Draws [painter] at [size] once into an image (at the device pixel ratio)
/// and then just that image, on its own layer, until the painter changes
/// ([CustomPainter.shouldRepaint]) or the size or pixel ratio does. The image
/// reaches [overflow] beyond the box on every side, for art that paints
/// outside it (a stone's sparkles and rays).
class CachedPaint extends LeafRenderObjectWidget {
  const CachedPaint({super.key, required this.painter, required this.size, this.overflow = 0});

  final CustomPainter painter;
  final Size size;
  final double overflow;

  @override
  RenderCachedPaint createRenderObject(BuildContext context) =>
      RenderCachedPaint(
        painter: painter,
        preferredSize: size,
        overflow: overflow,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );

  @override
  void updateRenderObject(BuildContext context, RenderCachedPaint renderObject) {
    renderObject
      ..painter = painter
      ..preferredSize = size
      ..overflow = overflow
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class RenderCachedPaint extends RenderBox {
  RenderCachedPaint({
    required this._painter,
    required this._preferredSize,
    required double devicePixelRatio,
    this._overflow = 0,
  }) : _dpr = devicePixelRatio;

  /// Images drawn so far, all instances (for tests).
  static int debugRenders = 0;

  CustomPainter _painter;
  set painter(CustomPainter v) {
    if (identical(v, _painter)) return;
    final old = _painter;
    _painter = v;
    if (v.runtimeType != old.runtimeType || v.shouldRepaint(old)) _invalidate();
  }

  Size _preferredSize;
  set preferredSize(Size v) {
    if (v == _preferredSize) return;
    _preferredSize = v;
    markNeedsLayout();
  }

  double _overflow;
  set overflow(double v) {
    if (v == _overflow) return;
    _overflow = v;
    _invalidate();
  }

  double _dpr;
  set devicePixelRatio(double v) {
    if (v == _dpr) return;
    _dpr = v;
    _invalidate();
  }

  ui.Image? _image;
  Size? _imageSize;

  void _invalidate() {
    _image?.dispose();
    _image = null;
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(_preferredSize);

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    if (_imageSize != null && _imageSize != size) _invalidate();
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    if (debugDisableMapRasterCache) {
      context.canvas.save();
      context.canvas.translate(offset.dx, offset.dy);
      _painter.paint(context.canvas, size);
      context.canvas.restore();
      return;
    }
    var image = _image;
    if (image == null) {
      debugRenders++;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..scale(_dpr)
        ..translate(_overflow, _overflow);
      _painter.paint(canvas, size);
      final picture = recorder.endRecording();
      final full = size + Offset(2 * _overflow, 2 * _overflow);
      image = _image = picture.toImageSync(math.max(1, (full.width * _dpr).ceil()), math.max(1, (full.height * _dpr).ceil()));
      picture.dispose();
      _imageSize = size;
    }
    context.canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      (offset - Offset(_overflow, _overflow)) & Size(image.width / _dpr, image.height / _dpr),
      Paint()..filterQuality = FilterQuality.none,
    );
  }
}
