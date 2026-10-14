/// ONYX (Boox) e-reader extras (v0.5), over the app's own platform channels
/// (`OnyxBridge.kt`, Onyx SDK):
///
/// * [EinkScreen.fullRefresh]: a full GC refresh that clears e-ink ghosting
///   (after a lesson, when leaving the player).
/// * [PenSurface]: low-latency raw drawing with the Onyx pen SDK inside the
///   writing pad; the strokes come back as point lists for recognition.
///
/// Elsewhere both are no-ops ([NoEinkScreen], no pen surface), and the
/// writing pad draws with Flutter.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Full-screen e-ink refresh.
abstract interface class EinkScreen {
  /// Whether this device has a controllable e-ink screen (ONYX).
  bool get supported;

  /// A full (GC) refresh of the whole screen. Returns whether it ran.
  Future<bool> fullRefresh();
}

class NoEinkScreen implements EinkScreen {
  const NoEinkScreen();
  @override
  bool get supported => false;
  @override
  Future<bool> fullRefresh() async => false;
}

class OnyxEinkScreen implements EinkScreen {
  const OnyxEinkScreen();
  static const MethodChannel _channel = MethodChannel('tosk/onyx');
  @override
  bool get supported => true;
  @override
  Future<bool> fullRefresh() async {
    try {
      return await _channel.invokeMethod<bool>('fullRefresh') ?? false;
    } catch (e) {
      debugPrint('[onyx] full refresh failed: $e');
      return false;
    }
  }
}

/// One stroke from the native pen: points in physical pixels of the Flutter
/// view, with timestamps in milliseconds.
typedef PenPoints = List<(double, double, int)>;

/// Low-latency pen drawing on the device's own screen layer.
abstract interface class PenSurface {
  /// Starts raw drawing inside [physicalRect] (physical pixels of the Flutter
  /// view). Returns false when the SDK can't (the pad then draws itself).
  Future<bool> open(Rect physicalRect, {double strokeWidth});

  /// The pad moved or resized.
  Future<void> setRect(Rect physicalRect);

  /// Pauses (a dialog over the pad, the answer checked) or resumes drawing.
  Future<void> setEnabled(bool enabled);

  /// Drops what the pen drew on the e-ink overlay.
  Future<void> clear();

  Future<void> close();

  /// Finished pen strokes.
  Stream<PenPoints> get strokes;

  /// Strokes of the pen's eraser (side button or eraser end).
  Stream<PenPoints> get erasures;
}

/// [PenSurface] over `tosk/onyx_pen` (`OnyxBridge.kt`).
class OnyxPenSurface implements PenSurface {
  OnyxPenSurface() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const MethodChannel _channel = MethodChannel('tosk/onyx_pen');
  final _strokes = StreamController<PenPoints>.broadcast();
  final _erasures = StreamController<PenPoints>.broadcast();

  @override
  Stream<PenPoints> get strokes => _strokes.stream;
  @override
  Stream<PenPoints> get erasures => _erasures.stream;

  Future<void> _onCall(MethodCall call) async {
    final points = decodePenPoints(call.arguments);
    if (points.isEmpty) return;
    switch (call.method) {
      case 'stroke':
        _strokes.add(points);
      case 'erase':
        _erasures.add(points);
    }
  }

  Map<String, Object> _rect(Rect r) => {
        'left': r.left.round(),
        'top': r.top.round(),
        'right': r.right.round(),
        'bottom': r.bottom.round(),
      };

  Future<bool> _call(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } catch (e) {
      debugPrint('[onyx] pen $method failed: $e');
      return false;
    }
  }

  @override
  Future<bool> open(Rect physicalRect, {double strokeWidth = 3}) =>
      _call('open', {..._rect(physicalRect), 'strokeWidth': strokeWidth});
  @override
  Future<void> setRect(Rect physicalRect) => _call('setRect', _rect(physicalRect));
  @override
  Future<void> setEnabled(bool enabled) => _call('setEnabled', {'enabled': enabled});
  @override
  Future<void> clear() => _call('clear');
  @override
  Future<void> close() => _call('close');
}

/// Decodes the native `[x, y, t, x, y, t, ...]` list.
PenPoints decodePenPoints(Object? raw) {
  final List<num> flat = switch (raw) {
    Float64List l => l,
    List l => [for (final v in l) if (v is num) v],
    _ => const [],
  };
  return [
    for (var i = 0; i + 2 < flat.length; i += 3) (flat[i].toDouble(), flat[i + 1].toDouble(), flat[i + 2].toInt()),
  ];
}
