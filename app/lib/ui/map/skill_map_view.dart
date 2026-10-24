import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/core.dart';
import '../brand/tosk.dart';
import '../theme/bw_skin.dart';
import '../theme/skin.dart';
import 'bough.dart';
import 'branch_style.dart';
import 'ink_art.dart';
import 'map_labels.dart';
import 'map_layout.dart';
import 'map_motion.dart';
import 'map_raster.dart';
import 'node_painter.dart';
import 'skill_node.dart';
import 'skill_stats.dart';
import 'topic_branch.dart';

export 'bough.dart' show BoughShape, LeafSpot, paintBough;
export 'map_labels.dart' show MapTextMetrics;
export 'topic_branch.dart' show TopicBranch, TopicRoot, TopicBranchTarget;

/// Which way the course grows on screen.
///
/// The layout itself is direction-free (bands and rows in course order);
/// [MapGeometry] turns it into pixels. [topDown] puts the first unit at the
/// top and scrolls down (today's map). [bottomUp] puts the roots at the
/// bottom, the first unit lowest and later units above it, so the learner
/// scrolls up as the tree grows; the branch painter draws every bough from
/// its parent to its child whichever is higher, and the marker, bands and
/// titles follow the geometry. To try it, change [kMapDirection] (and have
/// the map screen start scrolled to the bottom).
enum MapDirection { topDown, bottomUp }

/// The one setting for the map's growth direction.
const MapDirection kMapDirection = MapDirection.topDown;

/// Pixel geometry derived from a [MapLayout] for a given available width and zoom.
///
/// Under every stone it reserves the room for the node's title (two lines)
/// and its days chip at the current text size ([text], see
/// [MapTextMetrics]), so a wrapped title never runs under the chip or into
/// the next row; the band headers grow with the unit title's text size too.
class MapGeometry {
  MapGeometry({
    required this.layout,
    required double availableWidth,
    required this.zoom,
    this.direction = kMapDirection,
    this.text = MapTextMetrics.fallback,
    this.tallHeaders = const {},
    this.strips = const {},
  }) {
    final cols = math.max(1.0, layout.columns);
    final fit = (availableWidth - 2 * hPad) / cols;
    cellWidth = math.max(64.0, math.min(144.0, fit) * zoom);
    diameter = (cellWidth * 0.6).clamp(40.0, 76.0);
    rowHeight = labelTop + text.labelBlock + rowGap;
    gridWidth = cols * cellWidth;
    width = math.max(availableWidth, gridWidth + 2 * hPad);
    originX = (width - gridWidth) / 2;
    var y = 0.0;
    final tops = List<double>.filled(layout.bands.length, 0);
    final order = direction == MapDirection.topDown ? layout.bands : layout.bands.reversed;
    for (final b in order) {
      tops[b.index] = y;
      y += bandHeight(b) + bandGap;
    }
    bandTop.addAll(tops);
    height = y;
    for (final n in layout.nodes) {
      _rows.putIfAbsent((n.band, n.row), () => []).add(n.col);
    }
  }

  static const hPad = 12.0;

  /// The smallest band header (the unit title at text scale 1).
  static const bandHeader = 36.0;
  static const bandGap = 12.0;

  /// Space between a node's chip and the next row's cell.
  static const rowGap = 4.0;

  /// Inset of the band's rounded box from the map's sides.
  static const bandInset = 4.0;

  final MapLayout layout;
  final double zoom;
  final MapDirection direction;
  final MapTextMetrics text;

  /// Bands whose header has room for a two-line unit title (one squeezed
  /// between the boughs passing through it, see [planMap]).
  final Set<int> tallHeaders;
  late final double cellWidth;
  late final double diameter;
  late final double rowHeight;

  /// Height of band [band]'s header (the unit title), at least [bandHeader].
  double headerOf(int band) => text.headerHeight(tallHeaders.contains(band) ? 2 : 1);

  /// Extra room under some rows, by (band, row): the strips where topic
  /// branches leave the map (`topic_branch.dart`).
  final Map<(int, int), double> strips;

  /// The strips above visual row [visual] of [band] (rows counted from the band's top).
  double _stripsAbove(int band, int visual) {
    if (strips.isEmpty) return 0;
    var sum = 0.0;
    for (final e in strips.entries) {
      if (e.key.$1 != band) continue;
      final rowCount = layout.bands[band].rowCount;
      final v = direction == MapDirection.topDown ? e.key.$2 : rowCount - 1 - e.key.$2;
      if (v < visual) sum += e.value;
    }
    return sum;
  }

  /// A band's height: its header, rows and strips.
  double bandHeight(MapBand b) => headerOf(b.index) + b.rowCount * rowHeight + _stripsAbove(b.index, b.rowCount);

  /// The top of the strip under [row] of [band] (where its topic branches run).
  double stripTop(int band, int row) {
    final visual = direction == MapDirection.topDown ? row : layout.bands[band].rowCount - 1 - row;
    return bandTop[band] + headerOf(band) + (visual + 1) * rowHeight + _stripsAbove(band, visual);
  }
  late final double gridWidth;
  late final double width;
  late final double height;
  late final double originX;

  /// Top of each band, indexed by band index (not by position on screen).
  final List<double> bandTop = [];

  /// The columns of the nodes in each (band, row).
  final Map<(int, int), List<double>> _rows = {};

  /// The row's position inside its band, counted from the band's top.
  int visualRow(MapNode n) =>
      direction == MapDirection.topDown ? n.row : layout.bands[n.band].rowCount - 1 - n.row;

  /// Top-left of the node's cell.
  Offset cellOrigin(MapNode n) => Offset(
    originX + n.col * cellWidth,
    bandTop[n.band] + headerOf(n.band) + visualRow(n) * rowHeight + _stripsAbove(n.band, visualRow(n)),
  );

  /// Center of the node's box (stone, ring and rays).
  Offset ringCenter(MapNode n) => cellOrigin(n) + Offset(cellWidth / 2, 8 + nodeBox / 2);

  /// The node widget's box (at least a 48 px target).
  double get nodeBox => math.max(diameter, 48);

  /// Top of the title under a stone, from the cell's top.
  double get labelTop => 8 + nodeBox + 4;

  /// How wide the node's label (title and chip) may be: up to half way to
  /// its neighbours in the row (less a gap), inside the band, at most 1.6
  /// cells; so labels of one row never touch.
  double labelWidth(MapNode n) {
    final cx = ringCenter(n).dx;
    var half = math.min(cx - bandInset - 2, width - bandInset - 2 - cx);
    for (final c in _rows[(n.band, n.row)] ?? const <double>[]) {
      final d = (c - n.col).abs() * cellWidth;
      if (d > 0.01) half = math.min(half, d / 2 - 3);
    }
    return math.max(nodeBox, math.min(2 * half, cellWidth * 1.6));
  }

  /// The room reserved for the node's title and chip, in map coordinates.
  Rect labelRect(MapNode n) {
    final w = labelWidth(n);
    return Rect.fromLTWH(ringCenter(n).dx - w / 2, cellOrigin(n).dy + labelTop, w, text.labelBlock);
  }
}

/// The first skill in course order that is available or started: where Tosk
/// sits on the map (null when every skill is locked or done).
String? currentSkillId(Iterable<String> skillsInOrder, Map<String, SkillStats> stats) {
  for (final id in skillsInOrder) {
    final tier = stats[id]?.tier ?? MapTier.available;
    if (tier == MapTier.available || tier == MapTier.started) return id;
  }
  return null;
}

/// The skill graph as a tree: unit bands, storybook boughs along the
/// prerequisite edges, stone-medallion nodes and Tosk at the current skill.
/// Scrolls horizontally when zoomed in beyond the available width; the parent
/// scrolls vertically.
///
/// With motion on ([twinkle], not [reduceMotion], not black & white) the
/// medals twinkle and the ash leaves sway when the parent scrolls, all from
/// one ticker on separate layers (see `map_motion.dart`).
class SkillMapView extends StatefulWidget {
  const SkillMapView({
    super.key,
    required this.course,
    required this.layout,
    required this.stats,
    required this.style,
    required this.lang,
    required this.now,
    this.zoom = 1,
    this.reduceMotion = false,
    this.twinkle = false,
    this.swayLeaves,
    this.branchStyle = BranchStyle.defaults,
    this.showMarker = true,
    this.onTap,
    this.onLongPress,
    this.unitKeys = const {},
    this.storyCounts = const {},
    this.storyUnitsOpen = const {},
    this.onUnitStories,
    this.branches = const [],
    this.onTopic,
    this.unitTitles = const {},
    this.root,
    this.needs = const {},
    this.onNeeds,
  });

  /// On a topic's map: locked skills that wait for a main-tree skill, by
  /// skill id (the title of the skill they need and its unit number), shown
  /// under their title ("needs The conditional · unit 12"); a tap on the
  /// note calls [onNeeds] with the needed skill's id.
  final Map<String, MapNeed> needs;
  final void Function(String skillId)? onNeeds;

  /// Topic branches leaving the main tree at their anchors (with a carved
  /// name and arrow); a tap on a branch calls [onTopic].
  final List<TopicBranch> branches;
  final void Function(String topicId)? onTopic;

  /// Band titles for units that are not the course's (a topic map's root band).
  final Map<String, String> unitTitles;

  /// On a topic's map: its root (the anchor skill it grows from), which
  /// leads back to the main tree instead of opening the skill.
  final TopicRoot? root;

  /// Stories per unit id: units with stories get a book button in their band
  /// header ([onUnitStories]); [storyUnitsOpen] are the units whose stories
  /// are unlocked (a closed book outline otherwise).
  final Map<String, int> storyCounts;
  final Set<String> storyUnitsOpen;
  final void Function(String unitId)? onUnitStories;

  /// Keys put on each unit band (by unit id), so the map can scroll to one.
  final Map<String, GlobalKey> unitKeys;

  final CourseData course;
  final MapLayout layout;
  final Map<String, SkillStats> stats;
  final MapStyle style;
  final String lang;
  final DateTime now;
  final double zoom;
  final bool reduceMotion;

  /// Animate the medal twinkles (motion on; off under `flutter test`).
  final bool twinkle;

  /// Let the ash leaves sway when the map scrolls (null: like [twinkle]).
  final bool? swayLeaves;
  final BranchStyle branchStyle;

  /// Tosk at the current skill.
  final bool showMarker;
  final void Function(Skill skill)? onTap;
  final void Function(Skill skill)? onLongPress;

  @override
  State<SkillMapView> createState() => _SkillMapViewState();
}

class _SkillMapViewState extends State<SkillMapView> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  final MapMotion _motion = MapMotion();
  final GlobalKey _contentKey = GlobalKey(debugLabel: 'map-content');
  ScrollableState? _scrollable;
  ScrollPosition? _position;
  Duration _lastElapsed = Duration.zero;
  double? _lastPixels;
  double _velocity = 0;
  double _sinceSparkle = 1;
  bool _foreground = true;

  /// The scroll position changed since the last tick (keeps the ticker going).
  bool _scrolled = false;
  List<SparkleSpot> _spots = const [];
  Object? _planKey;
  MapPlan? _plan;
  MapInk? _leafInk;

  bool get _animate => !widget.reduceMotion && !widget.style.monochrome;
  bool get _twinkleOn => _animate && widget.twinkle;
  bool get _swayOn => _animate && (widget.swayLeaves ?? widget.twinkle);

  /// True while the shared motion ticker runs (for tests).
  @visibleForTesting
  bool get ticking => _ticker.isActive;

  /// The current layout plan: geometry, boughs and unit title places (for tests).
  @visibleForTesting
  MapPlan? get plan => _plan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = Scrollable.maybeOf(context);
    _scrollable = s;
    final p = s?.position;
    if (p != _position) {
      _position?.removeListener(_onScroll);
      _position = p;
      p?.addListener(_onScroll);
      _lastPixels = null;
    }
  }

  @override
  void didUpdateWidget(SkillMapView old) {
    super.didUpdateWidget(old);
    if (!_twinkleOn && !_swayOn) _ticker.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _sync();
    } else {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _position?.removeListener(_onScroll);
    _ticker.dispose();
    _motion.dispose();
    super.dispose();
  }

  void _onScroll() {
    _scrolled = true;
    if (_swayOn || (_twinkleOn && _spots.isNotEmpty)) _start();
  }

  void _start() {
    if (!_foreground || !mounted || _ticker.isActive) return;
    _lastElapsed = Duration.zero;
    _lastPixels = _position != null && _position!.hasPixels ? _position!.pixels : null;
    _ticker.start();
  }

  /// Starts the ticker when the twinkles want it, stops it when nothing moves.
  void _sync() {
    if (!mounted) return;
    if (_twinkleOn && _spots.isNotEmpty) {
      _start();
    } else if (!_swayOn || (_motion.sway.settled && _velocity == 0)) {
      _ticker.stop();
    }
  }

  void _updateVisible() {
    final content = _contentKey.currentContext?.findRenderObject();
    final viewport = _scrollable?.context.findRenderObject();
    if (content is! RenderBox || viewport is! RenderBox || !content.attached || !viewport.attached || !content.hasSize || !viewport.hasSize) {
      _motion.visible = null;
      return;
    }
    _motion.visible = content.globalToLocal(viewport.localToGlobal(Offset.zero)) & viewport.size;
  }

  bool _anySpotVisible() {
    final v = _motion.visible;
    if (v == null) return _spots.isNotEmpty;
    return _spots.any((s) => v.inflate(s.radius * 2).contains(s.center));
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastElapsed = elapsed;
    _motion.time += dt;
    _updateVisible();

    // The scroll velocity, smoothed (px/s; positive while the content moves up).
    var raw = 0.0;
    final pos = _position;
    if (pos != null && pos.hasPixels) {
      final px = pos.pixels;
      if (_lastPixels != null && dt > 0) raw = (px - _lastPixels!) / dt;
      _lastPixels = px;
    }
    _velocity += (raw - _velocity) * math.min(1.0, dt * 14);
    if (raw == 0 && _velocity.abs() < 0.5) _velocity = 0;

    final scrolled = _scrolled;
    _scrolled = false;
    var leavesMoving = false;
    if (_swayOn && _motion.leaves.isNotEmpty) {
      final wasSettled = _motion.sway.settled;
      _motion.sway.step(dt, _velocity, _motion.activeLeaves());
      leavesMoving = scrolled || !_motion.sway.settled || _velocity != 0;
      if (leavesMoving || !wasSettled) _motion.leafTick.tick();
    }

    final twinkling = _twinkleOn && _anySpotVisible();
    if (twinkling) {
      _sinceSparkle += dt;
      // About 30 fps is plenty for a twinkle.
      if (_sinceSparkle >= 1 / 30) {
        _sinceSparkle = 0;
        _motion.sparkleTick.tick();
      }
    }
    if (!twinkling && !leavesMoving) _ticker.stop();
  }

  /// The map's geometry, boughs and unit title places, computed once per
  /// layout, width, text size and progress (locked skills) and kept.
  MapPlan _planFor({
    required double width,
    required MapTextMetrics text,
    required Set<String> locked,
    required Map<int, String> titles,
    required Set<int> storyBands,
    required TextStyle? titleStyle,
    required TextScaler scaler,
  }) {
    final w = widget;
    final key = (
      w.layout,
      width,
      w.zoom,
      text,
      w.branchStyle,
      w.style,
      (locked.toList()..sort()).join(','),
      Object.hashAll([for (final e in titles.entries) (e.key, e.value)]),
      Object.hashAll(storyBands.toList()..sort()),
      titleStyle,
      scaler,
      Object.hashAll(w.branches),
    );
    if (key != _planKey || _plan == null) {
      _planKey = key;
      _plan = planMap(
        layout: w.layout,
        availableWidth: width,
        zoom: w.zoom,
        text: text,
        style: w.style,
        branchStyle: w.branchStyle,
        locked: locked,
        titles: titles,
        storyBands: storyBands,
        titleStyle: titleStyle,
        scaler: scaler,
        branches: w.branches,
      );
    }
    return _plan!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = widget;
    final course = w.course, layout = w.layout, stats = w.stats, style = w.style, lang = w.lang;
    final branchStyle = w.branchStyle;
    final onUnitStories = w.onUnitStories, storyCounts = w.storyCounts;
    return LayoutBuilder(
      builder: (context, constraints) {
        final unitTitles = {for (final u in course.units) u.id: pickLang(u.title, lang), ...w.unitTitles};
        final titleStyle = mapBandTitleStyle(theme)?.copyWith(color: style.bandTitleColor);
        final locked = {
          for (final e in stats.entries)
            if (e.value.tier == MapTier.locked) e.key,
        };
        final plan = _planFor(
          width: constraints.maxWidth,
          text: MapTextMetrics.of(context),
          locked: locked,
          titles: {for (final b in layout.bands) b.index: unitTitles[b.unitId] ?? b.unitId},
          storyBands: {
            for (final b in layout.bands)
              if ((storyCounts[b.unitId] ?? 0) > 0 && onUnitStories != null) b.index,
          },
          titleStyle: titleStyle,
          scaler: MediaQuery.textScalerOf(context),
        );
        final g = plan.geometry;
        // Tosk sits on the first open skill of this tree (never on a topic map's root).
        final current = w.showMarker
            ? currentSkillId([
                for (final u in course.units)
                  for (final s in course.skills)
                    if (s.unitId == u.id && layout.node(s.id) != null && s.id != w.root?.skillId) s.id,
              ], stats)
            : null;
        final markerNode = current == null ? null : layout.node(current);
        final markerSize = (g.diameter * 0.95).clamp(40.0, 56.0);

        // Motion: the boughs' leaves and the metal nodes' twinkles.
        final twinkleOn = _twinkleOn, swayOn = _swayOn;
        final boughs = plan.boughs;
        if (swayOn) {
          _motion.setLeaves([for (final b in boughs) ?b.shape.leaf]);
          if (_leafInk != style.ink) {
            _motion.clearPictures();
            _leafInk = style.ink;
          }
        }
        final titleSlots = plan.titles;
        final stoneR = NodePainter.stoneRadius(g.nodeBox, branchStyle.extent);
        final spots = !twinkleOn
            ? const <SparkleSpot>[]
            : [
                for (final n in layout.nodes)
                  if ((stats[n.skillId]?.tier.index ?? 0) >= MapTier.bronze.index)
                    SparkleSpot(
                      center: g.ringCenter(n),
                      radius: stoneR,
                      tier: stats[n.skillId]!.tier,
                      phase: (inkSeed(n.skillId) % 1000) / 1000,
                    ),
              ];
        if (!listEquals(spots, _spots) || spots.isEmpty != _spots.isEmpty) {
          _spots = spots;
          WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
        }

        final content = RepaintBoundary(
          child: SizedBox(
          key: _contentKey,
          width: g.width,
          height: g.height,
          child: Stack(
            key: const ValueKey('map-content'),
            children: [
              for (final b in layout.bands)
                Positioned(
                  left: 4,
                  right: 4,
                  top: g.bandTop[b.index],
                  height: g.bandHeight(b),
                  child: DecoratedBox(
                    key: w.unitKeys[b.unitId],
                    decoration: BoxDecoration(
                      color: style.bandColor(b.index),
                      borderRadius: BorderRadius.circular(16),
                      border: style.monochrome ? Border.all(color: kBwBlack, width: kBwBorder) : null,
                    ),
                  ),
                ),
              // The boughs: a static layer, drawn once per layout into raster
              // tiles near the viewport (`map_raster.dart`), which scrolling
              // only moves.
              Positioned.fill(
                child: RasterArt(
                  key: const ValueKey('map-boughs'),
                  artKey: (boughs, plan.branches, style.ink, style.monochrome, branchStyle, !swayOn),
                  painter: MapEdgesPainter(
                    layout: layout,
                    geometry: g,
                    style: style,
                    branchStyle: branchStyle,
                    lockedSkills: locked,
                    boughs: boughs,
                    paintLeaves: !swayOn,
                    branches: plan.branches,
                  ).paintRegion,
                ),
              ),
              // The leaves, swaying on their own layer while the map scrolls.
              if (swayOn)
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('map-leaves'),
                        painter: MapLeavesPainter(
                          motion: _motion,
                          ink: style.ink,
                          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                        ),
                      ),
                    ),
                  ),
                ),
              // Topic branches: each branch is the way into its topic (a band
              // at least 48 dp thick along the bark and its carving), a button
              // for semantics and the keyboard. It paints only while pressed
              // or focused; the branch itself is in the bough tiles. Under the
              // titles and nodes, so a stone or a label it passes keeps its tap.
              if (w.onTopic case final onTopic?)
                for (final p in plan.branches)
                  Positioned.fromRect(
                    rect: p.hitBounds,
                    child: TopicBranchTarget(
                      key: ValueKey('topic-branch-${p.branch.id}'),
                      plan: p,
                      ink: p.branch.locked ? MapEdgesPainter._lockedInk(style) : style.ink,
                      mono: style.monochrome,
                      reduceMotion: w.reduceMotion,
                      onTap: () => onTopic(p.branch.id),
                    ),
                  ),
              // Unit titles on a plaque above the branches (the band colour
              // with a hairline edge), so a bough crossing the header passes
              // behind the plaque and never through the text; no twig or leaf
              // hangs over it (`planMap`).
              for (final b in layout.bands)
                if (titleSlots[b.index] case final slot?)
                  Positioned(
                    key: ValueKey('band-title-${b.unitId}'),
                    left: slot.left,
                    width: slot.width,
                    top: g.bandTop[b.index] + kMapBandTitleTop,
                    child: Tooltip(
                      message: unitTitles[b.unitId] ?? b.unitId,
                      excludeFromSemantics: true,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: style.bandColor(b.index),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: style.monochrome ? kBwBlack : style.bandTitleColor.withValues(alpha: 0.3),
                            width: style.monochrome ? 1.5 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: kMapBandTitlePadding,
                          child: Text(
                            unitTitles[b.unitId] ?? b.unitId,
                            maxLines: slot.lines,
                            overflow: TextOverflow.ellipsis,
                            // A wordmark-style serif title for each bough.
                            style: titleStyle,
                          ),
                        ),
                      ),
                    ),
                  ),
              // The unit's stories: a book and the count at the right end of
              // the band header: the header plus the gap above the nodes (44 px).
              if (onUnitStories != null)
                for (final b in layout.bands)
                  if ((storyCounts[b.unitId] ?? 0) > 0)
                    Positioned(
                      right: 8,
                      top: g.bandTop[b.index],
                      width: _storyButtonWidth,
                      height: g.headerOf(b.index) + 8,
                      child: _UnitStoriesButton(
                        key: ValueKey('unit-stories-${b.unitId}'),
                        count: storyCounts[b.unitId]!,
                        open: w.storyUnitsOpen.contains(b.unitId),
                        unitTitle: unitTitles[b.unitId] ?? b.unitId,
                        background: style.bandColor(b.index),
                        foreground: style.bandTitleColor,
                        onTap: () => onUnitStories(b.unitId),
                      ),
                    ),
              for (final n in layout.nodes)
                if (course.skill(n.skillId) case final skill?)
                  Positioned(
                    left: g.ringCenter(n).dx - g.labelWidth(n) / 2,
                    top: g.cellOrigin(n).dy + 8,
                    width: g.labelWidth(n),
                    height: g.rowHeight - 8,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SkillNode(
                        skill: skill,
                        title: pickLang(skill.title, lang),
                        stats: stats[skill.id] ?? SkillStats.empty,
                        style: style,
                        diameter: g.diameter,
                        now: w.now,
                        reduceMotion: w.reduceMotion,
                        paintTwinkles: !twinkleOn,
                        branchStyle: branchStyle,
                        onTap: w.root?.skillId == skill.id
                            ? w.root!.onTap
                            : w.onTap == null
                            ? null
                            : () => w.onTap!(skill),
                        onLongPress: w.onLongPress == null ? null : () => w.onLongPress!(skill),
                        labelBackground: style.bandColor(n.band),
                        semanticsLabel: w.root?.skillId == skill.id ? w.root!.label : null,
                        needs: w.needs[skill.id]?.title,
                        needsUnit: w.needs[skill.id]?.unit,
                        onNeeds: switch ((w.needs[skill.id], w.onNeeds)) {
                          (final n?, final onNeeds?) => () => onNeeds(n.skillId),
                          _ => null,
                        },
                      ),
                    ),
                  ),
              // Every moving twinkle of the map, on one layer above the stones.
              if (twinkleOn)
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('map-sparkles'),
                        painter: MapSparklePainter(spots: spots, motion: _motion, ink: style.ink, style: branchStyle),
                      ),
                    ),
                  ),
                ),
              // Tosk sits on the current skill's stone (top left, peeking
              // over the ring; top right, mirrored, where the left would
              // cover the unit title's plaque); decorative, the node
              // underneath is the target.
              if (markerNode != null)
                if (markerRect(plan, markerNode, markerSize, avoid: [
                  if (onUnitStories != null && (storyCounts[layout.bands[markerNode.band].unitId] ?? 0) > 0)
                    Rect.fromLTWH(g.width - 8 - _storyButtonWidth, g.bandTop[markerNode.band], _storyButtonWidth,
                        g.headerOf(markerNode.band) + 8),
                  // a topic branch's carving just above the stone
                  for (final p in plan.branches)
                    if (p.carving case final c?) c.bounds,
                ]) case (final rect, final mirrored))
                  Positioned.fromRect(
                    rect: rect,
                    child: IgnorePointer(
                      child: Semantics(
                        key: const ValueKey('tosk-marker'),
                        label: 'Tosk: continue here',
                        child: Transform.flip(
                          flipX: mirrored,
                          child: ToskImage(pose: ToskPose.marker, height: markerSize),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
          ),
        );

        if (g.width <= constraints.maxWidth + 0.5) return content;
        return SingleChildScrollView(
          key: const ValueKey('map-hscroll'),
          scrollDirection: Axis.horizontal,
          child: content,
        );
      },
    );
  }
}

/// Where Tosk sits on [node]'s stone: peeking over its top-left edge; where
/// that would cover the unit title's plaque of the node's band or [avoid] (the
/// band's stories button, a topic branch's carving),
/// mirrored over its top-right edge, else beside the stone (left or right, at
/// its height, below the band's header), whichever first is clear of the
/// plaque, of [avoid] and of the other stones in its row. The second value says
/// whether Tosk is mirrored (on the right, facing left).
(Rect, bool) markerRect(MapPlan plan, MapNode node, double size, {List<Rect> avoid = const []}) {
  final g = plan.geometry;
  final c = g.ringCenter(node);
  final top = c.dy - g.nodeBox / 2 - size * 0.55;
  final left = Rect.fromLTWH(c.dx - g.nodeBox / 2 - size * 0.7, top, size, size);
  final plaque = plan.titles.containsKey(node.band) ? plan.titleRect(node.band).inflate(2) : null;
  bool onPlaque(Rect r) => plaque != null && r.overlaps(plaque);
  if (!onPlaque(left) && !avoid.any(left.overlaps)) return (left, false);
  final stones = [
    for (final n in g.layout.nodes)
      if (n != node && n.band == node.band && n.row == node.row)
        Rect.fromCircle(center: g.ringCenter(n), radius: g.nodeBox / 2),
  ];
  bool clear(Rect r) =>
      !onPlaque(r) && r.left >= 0 && r.right <= g.width && !avoid.any(r.overlaps) && !stones.any(r.overlaps);
  final mid = c.dy - size / 2;
  for (final (r, mirrored) in [
    (Rect.fromLTWH(c.dx + g.nodeBox / 2 - size * 0.3, top, size, size), true),
    (Rect.fromLTWH(c.dx - g.nodeBox / 2 - size * 0.95, mid, size, size), false),
    (Rect.fromLTWH(c.dx + g.nodeBox / 2 - size * 0.05, mid, size, size), true),
  ]) {
    if (clear(r)) return (r, mirrored);
  }
  return (left, false);
}

/// A main-tree skill a locked topic skill waits for: its id, title and unit number.
typedef MapNeed = ({String skillId, String title, int? unit});

/// Where a unit title goes in its band header: the plaque's left edge and
/// width, and its lines (2 when it is too long for the header on one line).
typedef MapTitleSlot = ({double left, double width, int lines});

/// What the map lays out once per layout, width, text size and progress:
/// the [geometry], the [boughs] and the unit [titles] (by band index).
class MapPlan {
  const MapPlan({required this.geometry, required this.boughs, required this.titles, this.branches = const []});
  final MapGeometry geometry;
  final List<MapBough> boughs;
  final Map<int, MapTitleSlot> titles;

  /// The topic branches leaving the map (main tree only).
  final List<BranchPlan> branches;

  /// The plaque behind band [band]'s title, in map coordinates.
  Rect titleRect(int band) {
    final t = titles[band]!;
    return Rect.fromLTWH(
      t.left,
      geometry.bandTop[band] + kMapBandTitleTop,
      t.width,
      geometry.text.headerText(t.lines) + kMapBandTitlePadding.vertical,
    );
  }
}

/// Lays out the map: the geometry, the boughs along the edges and each unit
/// title's plaque ([titles] by band index) at the left of its band header;
/// [storyBands] have a stories button at the header's right end. A title too
/// long for the header on one line gets a header with room for two lines
/// (ellipsized after that). The plaques sit above the boughs (a bough passes
/// behind one, never through its text), and a twig and leaf that would hang
/// over a plaque are left off their bough.
MapPlan planMap({
  required MapLayout layout,
  required double availableWidth,
  required double zoom,
  required MapStyle style,
  MapTextMetrics text = MapTextMetrics.fallback,
  BranchStyle branchStyle = BranchStyle.defaults,
  Set<String> locked = const {},
  Map<int, String> titles = const {},
  Set<int> storyBands = const {},
  TextStyle? titleStyle,
  TextScaler scaler = TextScaler.noScaling,
  MapDirection direction = kMapDirection,
  List<TopicBranch> branches = const [],
}) {
  final flat = MapGeometry(layout: layout, availableWidth: availableWidth, zoom: zoom);
  final width = math.max(availableWidth, flat.width);
  const minX = MapGeometry.bandInset + 8;
  final want = <int, double>{}, room = <int, double>{};
  final tall = <int>{};
  for (final b in layout.bands) {
    final tp = TextPainter(
      text: TextSpan(text: titles[b.index] ?? b.unitId, style: titleStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    want[b.index] = tp.width.ceilToDouble() + 1 + kMapBandTitlePadding.horizontal;
    tp.dispose();
    room[b.index] = width - MapGeometry.bandInset - (storyBands.contains(b.index) ? 4 + _storyButtonWidth : 8) - minX;
    if (want[b.index]! > room[b.index]!) tall.add(b.index);
  }
  // Topic branches: a side and a lane each, and a strip under their anchors' rows.
  final metrics = BranchMetrics(flat.diameter);
  final lanes = branches.isEmpty
      ? const <BranchLane>[]
      : planBranchLanes(
          layout: layout,
          branches: branches,
          centerX: (n) => flat.ringCenter(n).dx,
          width: flat.width,
          maxRun: metrics.maxRun(flat.cellWidth),
        );
  final g = MapGeometry(
    layout: layout,
    availableWidth: availableWidth,
    zoom: zoom,
    direction: direction,
    text: text,
    tallHeaders: tall,
    strips: {for (final e in branchLaneCounts(lanes).entries) e.key: e.value * metrics.laneHeight},
  );
  final slots = <int, MapTitleSlot>{
    for (final b in layout.bands)
      b.index: (left: minX, width: math.min(want[b.index]!, room[b.index]!), lines: tall.contains(b.index) ? 2 : 1),
  };
  final raw = MapEdgesPainter(layout: layout, geometry: g, style: style, branchStyle: branchStyle, lockedSkills: locked)
      .boughShapes();
  final plan = MapPlan(geometry: g, boughs: raw, titles: slots);
  final r = NodePainter.stoneRadius(g.nodeBox, branchStyle.extent);
  final planned = <BranchPlan>[
    for (final l in lanes)
      ?buildBranch(
            lane: l,
            stone: g.ringCenter(l.node),
            r: r,
            cellWidth: g.cellWidth,
            laneTop: g.stripTop(l.node.band, l.node.row) + l.lane * metrics.laneHeight,
            mapWidth: g.width,
            metrics: metrics,
            style: branchStyle,
            // The branch is painted in front of the boughs it crosses, so the
            // carving needs no gap between them.
            scaler: scaler,
          ),
  ];
  // No twig or leaf over a unit title or a carving.
  final keepClear = [
    for (final b in layout.bands) plan.titleRect(b.index).inflate(2),
    for (final p in planned)
      if (p.carving case final c?) c.bounds.inflate(2),
  ];
  return MapPlan(
    geometry: g,
    boughs: [
      for (final b in raw)
        if (keepClear.any((t) => leafTouches(b.shape, t))) MapBough(b.shape.withoutLeaf(), b.locked) else b,
    ],
    titles: slots,
    branches: planned,
  );
}

/// Paints the prerequisite edges as storybook boughs: a tapered bark
/// silhouette with knuckles, grain dashes on the lit side, hatching in the
/// shadow, an ink outline whose weight follows the light, and an ash leaf on
/// a twig along the longer ones. Forks and joins come from the layout's
/// edges. Boughs to locked skills are thinner and paler (gray in black &
/// white). Edges that would pass behind another node detour through a free
/// lane ([detourLane]).
///
/// The bough shapes come precomputed from the map ([boughs], kept between
/// frames) or are built here. With [paintLeaves] false the leaves are left
/// to the map's swaying leaf layer.
class MapEdgesPainter extends CustomPainter {
  MapEdgesPainter({
    required this.layout,
    required this.geometry,
    required this.style,
    this.branchStyle = BranchStyle.defaults,
    this.lockedSkills = const {},
    this.boughs,
    this.paintLeaves = true,
    this.branches = const [],
  });
  final MapLayout layout;
  final MapGeometry geometry;
  final MapStyle style;
  final BranchStyle branchStyle;
  final Set<String> lockedSkills;
  final List<MapBough>? boughs;
  final bool paintLeaves;

  /// The topic branches with their carvings, painted in front of the boughs they cross.
  final List<BranchPlan> branches;

  void _paintBranches(Canvas canvas, Rect? region) {
    if (branches.isEmpty) return;
    final lockedInk = _lockedInk(style);
    for (final b in branches) {
      if (region != null && !b.bounds.overlaps(region)) continue;
      paintBranch(canvas, b, b.branch.locked ? lockedInk : style.ink, branchStyle,
          mono: style.monochrome, locked: b.branch.locked);
    }
  }

  /// How many times the boughs were painted (for the repaint tests).
  static int debugPaintCount = 0;

  /// The boughs of every drawable edge, in edge order.
  List<MapBough> boughShapes() {
    final r = geometry.diameter / 2;
    final d = geometry.diameter;
    final out = <MapBough>[];
    for (final e in layout.edges) {
      final a = layout.node(e.from), b = layout.node(e.to);
      if (a == null || b == null) continue;
      final locked = lockedSkills.contains(e.to);
      final from = geometry.ringCenter(a);
      final to = geometry.ringCenter(b);
      final path = edgePath(a, b, from, to, r);
      if (path == null) continue;
      final scale = locked ? branchStyle.lockedWidthScale : 1.0;
      final shape = BoughShape.build(
        path,
        style: branchStyle,
        w0: branchStyle.widthStart * d * scale,
        w1: branchStyle.widthEnd * d * scale,
        seed: inkSeed('${e.from}>${e.to}'),
        leaves: !locked,
        leafScale: branchStyle.leafScale * d / 80,
        leafMinLength: branchStyle.leafMinLength * d,
      );
      if (shape != null) out.add(MapBough(shape, locked));
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    debugPaintCount++;
    final lockedInk = _lockedInk(style);
    for (final b in boughs ?? boughShapes()) {
      b.shape.paint(canvas, b.locked ? lockedInk : style.ink, branchStyle, leaf: paintLeaves);
    }
    _paintBranches(canvas, null);
  }

  /// How many map regions (raster tiles) were painted (for the repaint tests).
  static int debugRegionPaints = 0;

  /// Paints the boughs that reach into [region] (a raster tile of the map).
  void paintRegion(Canvas canvas, Rect region) {
    debugRegionPaints++;
    final lockedInk = _lockedInk(style);
    for (final b in boughs ?? boughShapes()) {
      if (!b.shape.bounds.overlaps(region)) continue;
      b.shape.paint(canvas, b.locked ? lockedInk : style.ink, branchStyle, leaf: paintLeaves);
    }
    _paintBranches(canvas, region);
  }

  static MapInk _lockedInk(MapStyle style) => style.monochrome
      ? style.ink.copyWith(ink: kBwGray)
      : style.ink.copyWith(
          bark: Color.lerp(style.ink.bark, style.ink.paper, 0.4),
          ink: style.ink.ink.withValues(alpha: 0.55),
        );

  /// The bough's centre line from the parent's box to the child's, in the
  /// parent→child direction; null when the nodes overlap.
  @visibleForTesting
  Path? edgePath(MapNode a, MapNode b, Offset from, Offset to, double r) {
    final inset = r * 0.5;
    final down = to.dy > from.dy;
    if ((to.dy - from.dy).abs() > 1) {
      final top = down ? from : to;
      final bottom = down ? to : from;
      final topNode = down ? a : b;
      final bottomNode = down ? b : a;
      final lane = detourLane(topNode, bottomNode, top + Offset(0, inset), bottom - Offset(0, inset), r);
      final p = lane != null
          ? _detourPath(top + Offset(0, inset), bottom - Offset(0, inset), lane)
          : const CurvedEdgePainter().path(top + Offset(0, inset), bottom - Offset(0, inset));
      return down ? p : _reversed(p);
    }
    // Same row (pinned nodes): a straight bough between the boxes.
    final v = to - from;
    final len = v.distance;
    if (len <= 2 * inset) return null;
    final u = v / len;
    return Path()
      ..moveTo(from.dx + u.dx * inset, from.dy + u.dy * inset)
      ..lineTo(to.dx - u.dx * inset, to.dy - u.dy * inset);
  }

  static Path _reversed(Path p) {
    final line = Polyline.sample(p, 2);
    final out = Path();
    for (var i = line.length - 1; i >= 0; i--) {
      final q = line.points[i];
      i == line.length - 1 ? out.moveTo(q.dx, q.dy) : out.lineTo(q.dx, q.dy);
    }
    return out;
  }

  /// When the straight edge from [a] to [b] would pass behind another node
  /// (an edge skipping rows, often across unit bands), the x of a free lane
  /// between columns to route it through instead; null when the way is clear.
  @visibleForTesting
  double? detourLane(MapNode a, MapNode b, Offset from, Offset to, double r) {
    final g = geometry;
    final blockers = <Offset>[];
    final between = <Offset>[];
    for (final n in layout.nodes) {
      if (n.skillId == a.skillId || n.skillId == b.skillId) continue;
      final c = g.ringCenter(n);
      if (c.dy <= from.dy + r || c.dy >= to.dy - r) continue;
      between.add(c);
      final t = (c.dy - from.dy) / (to.dy - from.dy);
      final x = from.dx + (to.dx - from.dx) * t;
      // The node plus its title below it.
      if ((c.dx - x).abs() < g.cellWidth * 0.45) blockers.add(c);
    }
    if (blockers.isEmpty) return null;
    // Lanes are the column boundaries; take the one closest to the straight
    // line that no blocker sits on.
    final mid = (from.dx + to.dx) / 2;
    final candidates = <double>[];
    for (var k = 0; k <= 2 * layout.columns.ceil() + 2; k++) {
      candidates.add(g.originX + (k / 2 - 0.5) * g.cellWidth + g.cellWidth / 2);
    }
    candidates.sort((x, y) => (x - mid).abs().compareTo((y - mid).abs()));
    for (final lane in candidates) {
      if (between.every((c) => (c.dx - lane).abs() >= g.cellWidth * 0.45)) return lane;
    }
    return null;
  }

  Path _detourPath(Offset from, Offset to, double lane) {
    final h = geometry.rowHeight;
    final top = Offset(lane, from.dy + h * 0.45);
    final bottom = Offset(lane, to.dy - h * 0.45);
    return Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(from.dx, from.dy + h * 0.25, lane, top.dy - h * 0.2, top.dx, top.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..cubicTo(lane, bottom.dy + h * 0.2, to.dx, to.dy - h * 0.25, to.dx, to.dy);
  }

  @override
  bool shouldRepaint(MapEdgesPainter old) =>
      old.layout != layout ||
      old.geometry.cellWidth != geometry.cellWidth ||
      old.geometry.width != geometry.width ||
      old.geometry.rowHeight != geometry.rowHeight ||
      old.geometry.text != geometry.text ||
      !setEquals(old.geometry.tallHeaders, geometry.tallHeaders) ||
      old.geometry.direction != geometry.direction ||
      old.style != style ||
      old.branchStyle != branchStyle ||
      old.lockedSkills.length != lockedSkills.length ||
      old.boughs != boughs ||
      old.paintLeaves != paintLeaves ||
      old.branches != branches ||
      !mapEquals(old.geometry.strips, geometry.strips);
}

/// A bough of the map and whether it leads to a locked skill.
@immutable
class MapBough {
  const MapBough(this.shape, this.locked);
  final BoughShape shape;
  final bool locked;
}

const double _storyButtonWidth = 64;

/// The book button of a unit band: an open book when the unit's stories are
/// unlocked, an outline otherwise, plus the number of stories.
class _UnitStoriesButton extends StatelessWidget {
  const _UnitStoriesButton({
    super.key,
    required this.count,
    required this.open,
    required this.unitTitle,
    required this.background,
    required this.foreground,
    required this.onTap,
  });
  final int count;
  final bool open;
  final String unitTitle;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mono = isBw(context);
    return Semantics(
      button: true,
      label: '$count ${count == 1 ? 'story' : 'stories'}, $unitTitle${open ? '' : ', locked'}',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Stories',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: mono ? kBwBlack : foreground.withValues(alpha: 0.5), width: mono ? kBwBorder : 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(open ? Icons.menu_book : Icons.menu_book_outlined, size: 18, color: foreground),
                  const SizedBox(width: 4),
                  Text('$count', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foreground)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
