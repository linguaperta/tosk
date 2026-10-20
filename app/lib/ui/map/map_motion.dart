/// The map's motion (v0.7.1): the medals' twinkles and the ash leaves that
/// sway when the map scrolls. Kept cheap on purpose:
///
/// - **One ticker** for the whole visible map ([SkillMapView]'s state), no
///   controller per node. It runs only while something moves: the twinkles
///   of metal nodes in view, or leaves still settling after a scroll. It is
///   muted when the map is off screen (another route or tab: `TickerMode`)
///   and stopped while the app is in the background.
/// - **Separate layers.** The twinkles ([MapSparklePainter]) and the leaves
///   ([MapLeavesPainter]) each paint on their own `RepaintBoundary` layer and
///   repaint through a [Listenable] (no rebuilds); the stones, boughs and
///   titles sit on static layers that never repaint for motion.
/// - **Culling and caps.** Only twinkles in (or near) the viewport are
///   painted; at most [kMaxSwayLeaves] leaves in view are simulated; each
///   leaf is a cached `Picture`, so a frame only replays it at a new angle.
///   Twinkle repaints are throttled to about 30 fps.
///
/// In black & white and with reduce motion none of this runs: the node
/// painter draws static twinkles and the boughs draw their leaves.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../theme/skin.dart';
import 'bough.dart';
import 'branch_style.dart';
import 'ink_art.dart';
import 'medal_art.dart';
import 'node_painter.dart';
import 'skill_stats.dart';

/// At most this many leaves sway at once (those nearest the viewport centre).
const int kMaxSwayLeaves = 24;

/// A metal node whose twinkles the shared sparkle layer animates.
@immutable
class SparkleSpot {
  const SparkleSpot({required this.center, required this.radius, required this.tier, required this.phase});
  final Offset center;

  /// The stone's radius.
  final double radius;
  final MapTier tier;

  /// 0..1, so neighbouring nodes don't pulse in step.
  final double phase;

  @override
  bool operator ==(Object other) =>
      other is SparkleSpot && other.center == center && other.radius == radius && other.tier == tier && other.phase == phase;

  @override
  int get hashCode => Object.hash(center, radius, tier, phase);
}

/// A [ChangeNotifier] the motion ticker pokes to repaint one layer.
class MotionTick extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Damped springs, one per leaf: each leans with the scroll velocity (the
/// map moves, the leaf lags behind like in a breeze) and swings back when
/// the scrolling stops, with a slightly different stiffness and damping per
/// leaf so they don't move in lockstep.
class LeafSway {
  LeafSway(List<LeafSpot> leaves)
    : _angle = List.filled(leaves.length, 0),
      _speed = List.filled(leaves.length, 0),
      _stiff = [for (final l in leaves) _stiffness(l.seed)],
      _damp = [for (final l in leaves) _damping(l.seed)],
      _gain = [for (final l in leaves) math.cos(l.angle) * (0.85 + 0.3 * _frac(l.seed * 0.37))];

  final List<double> _angle;
  final List<double> _speed;
  final List<double> _stiff;
  final List<double> _damp;
  final List<double> _gain;

  /// Radians of lean per px/s of scroll velocity, and the largest lean.
  static const double gain = 0.00045;
  static const double maxLean = 0.5;

  static double _frac(double x) => x - x.floorToDouble();
  static double _stiffness(int seed) {
    final f = 1.5 * (0.85 + 0.3 * _frac(seed * 0.618)); // natural frequency, Hz
    return math.pow(2 * math.pi * f, 2).toDouble();
  }

  static double _damping(int seed) => 2 * (0.17 + 0.05 * _frac(seed * 0.291)) * math.sqrt(_stiffness(seed));

  int get length => _angle.length;

  /// The leaf's extra angle (radians) right now.
  double angleOf(int i) => i < _angle.length ? _angle[i] : 0;

  /// True when every leaf hangs still.
  bool get settled {
    for (var i = 0; i < _angle.length; i++) {
      if (_angle[i].abs() > 0.002 || _speed[i].abs() > 0.02) return false;
    }
    return true;
  }

  /// Advances the leaves in [active] by [dt] seconds under scroll [velocity]
  /// (px/s, positive while the content moves up); the others hang still.
  void step(double dt, double velocity, Set<int> active) {
    if (dt <= 0 || dt.isNaN) return;
    final steps = (dt / (1 / 120)).ceil().clamp(1, 8);
    final h = math.min(dt, 1 / 15) / steps;
    for (var i = 0; i < _angle.length; i++) {
      if (!active.contains(i)) {
        _angle[i] = 0;
        _speed[i] = 0;
        continue;
      }
      final target = (velocity * gain * _gain[i]).clamp(-maxLean, maxLean);
      for (var s = 0; s < steps; s++) {
        _speed[i] += (_stiff[i] * (target - _angle[i]) - _damp[i] * _speed[i]) * h;
        _angle[i] += _speed[i] * h;
      }
      if (_angle[i].abs() < 0.002 && _speed[i].abs() < 0.02 && target.abs() < 0.002) {
        _angle[i] = 0;
        _speed[i] = 0;
      }
    }
  }
}

/// What the motion layers share: the clock, the viewport and the leaves.
class MapMotion {
  MapMotion();

  /// Seconds of motion so far (the twinkles' clock).
  double time = 0;

  /// The part of the map in view (map coordinates); null: assume all of it.
  Rect? visible;

  final MotionTick sparkleTick = MotionTick();
  final MotionTick leafTick = MotionTick();

  List<LeafSpot> _leaves = const [];
  LeafSway _sway = LeafSway(const []);
  LeafSway get sway => _sway;
  List<LeafSpot> get leaves => _leaves;

  final Map<(int, double, MapInk), ui.Picture> _pictures = {};

  /// Sets the leaves (after a layout change); keeps the springs when unchanged.
  void setLeaves(List<LeafSpot> leaves) {
    if (listEquals(leaves, _leaves)) return;
    _leaves = leaves;
    _sway = LeafSway(leaves);
    clearPictures(); // new sizes or seeds (zoom, another layout)
  }

  /// The leaves to simulate: those near the viewport, nearest its centre
  /// first, at most [kMaxSwayLeaves].
  Set<int> activeLeaves() {
    final v = visible;
    final ids = <int>[
      for (var i = 0; i < _leaves.length; i++)
        if (v == null || v.inflate(80).contains(_leaves[i].tip)) i,
    ];
    if (ids.length > kMaxSwayLeaves && v != null) {
      ids.sort((a, b) => (_leaves[a].tip - v.center).distance.compareTo((_leaves[b].tip - v.center).distance));
    }
    return ids.take(kMaxSwayLeaves).toSet();
  }

  /// A leaf drawn once at the origin pointing along +x (replayed each frame).
  ui.Picture leafPicture(LeafSpot leaf, MapInk ink) => _pictures.putIfAbsent((leaf.seed, leaf.scale, ink), () {
    final recorder = ui.PictureRecorder();
    paintAshLeaf(Canvas(recorder), Offset.zero, 0, leaf.scale, ink, seed: leaf.seed);
    return recorder.endRecording();
  });

  void clearPictures() {
    for (final p in _pictures.values) {
      p.dispose();
    }
    _pictures.clear();
  }

  void dispose() {
    clearPictures();
    sparkleTick.dispose();
    leafTick.dispose();
  }
}

/// The moving twinkles of every metal node in view, on one layer.
class MapSparklePainter extends CustomPainter {
  MapSparklePainter({required this.spots, required this.motion, required this.ink, this.style = BranchStyle.defaults})
    : super(repaint: motion.sparkleTick);
  final List<SparkleSpot> spots;
  final MapMotion motion;
  final MapInk ink;
  final BranchStyle style;

  /// How many times the layer was painted (for the repaint tests).
  static int debugPaintCount = 0;

  @override
  void paint(Canvas canvas, Size size) {
    debugPaintCount++;
    final v = motion.visible;
    final t = motion.time;
    for (final s in spots) {
      if (v != null && !v.inflate(s.radius * 2).contains(s.center)) continue;
      final twinkles = style.sparkleFor(s.tier.name).twinkles;
      for (var i = 0; i < twinkles.length; i++) {
        final tw = twinkles[i];
        final m = twinkleMotion(s.tier, i, t, s.phase);
        paintTwinkle(canvas, NodePainter.sparklePosition(s.center, s.radius, tw), s.radius * tw.size * m.scale, ink,
            rotate: tw.rotate * math.pi / 180 + m.rotate, opacity: m.opacity);
      }
    }
  }

  @override
  bool shouldRepaint(MapSparklePainter old) =>
      !listEquals(old.spots, spots) || old.motion != motion || old.ink != ink || old.style != style;
}

/// The boughs' ash leaves, swaying, on one layer.
class MapLeavesPainter extends CustomPainter {
  MapLeavesPainter({required this.motion, required this.ink}) : super(repaint: motion.leafTick);
  final MapMotion motion;
  final MapInk ink;

  /// How many times the layer was painted (for the repaint tests).
  static int debugPaintCount = 0;

  @override
  void paint(Canvas canvas, Size size) {
    debugPaintCount++;
    final leaves = motion.leaves;
    final v = motion.visible?.inflate(120);
    for (var i = 0; i < leaves.length; i++) {
      final l = leaves[i];
      if (v != null && !v.contains(l.tip)) continue;
      canvas.save();
      canvas.translate(l.tip.dx, l.tip.dy);
      canvas.rotate(l.angle + motion.sway.angleOf(i));
      canvas.drawPicture(motion.leafPicture(l, ink));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(MapLeavesPainter old) => old.motion != motion || old.ink != ink;
}
