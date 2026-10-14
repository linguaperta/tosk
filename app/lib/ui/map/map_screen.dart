import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../common/async_view.dart';
import '../routes.dart';
import '../shell/course_switcher.dart';
import '../slots/progression_slots.dart';
import 'skill_map_view.dart';
import 'skill_stats.dart';

/// Home: the skill map for the active course.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _minZoom = 0.7, _maxZoom = 1.9;
  double _zoom = 1;

  /// Maps with at least this many units get "Jump to current unit".
  static const _longMapUnits = 4;
  final Map<String, GlobalKey> _unitKeys = {};

  GlobalKey _unitKey(String unitId) => _unitKeys[unitId] ??= GlobalKey(debugLabel: 'unit-$unitId');

  /// Scrolls the map so [unitId]'s band is at the top.
  void _jumpTo(String unitId) {
    final ctx = _unitKeys[unitId]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: ref.read(motionProvider).long, curve: Curves.easeOutCubic);
  }

  void _setZoom(double z) => setState(() => _zoom = z.clamp(_minZoom, _maxZoom));

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseDataProvider);
    final layout = ref.watch(mapLayoutProvider);
    final stats = ref.watch(skillStatsProvider);
    final lang = ref.watch(sourceLangProvider);
    final skin = ref.watch(skinProvider);
    final reduceMotion = ref.watch(reduceMotionProvider);
    final now = ref.watch(clockProvider)();
    final mistakeCount = ref.watch(openMistakesProvider).value?.length ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final anyPracticed = stats.value?.values.any((s) => s.practiced) ?? false;
    final c = course.value;
    final longMap = c != null && c.units.length >= _longMapUnits;
    final current = !longMap
        ? null
        : currentUnitId([
            for (final u in c.units)
              for (final s in c.skills)
                if (s.unitId == u.id) (unitId: u.id, skillId: s.id),
          ], stats.value ?? const {});
    // Room below the last band for the action buttons.
    final fabRoom = 96.0 + (mistakeCount > 0 ? 72 : 0) + (current != null ? 52 : 0);

    return Scaffold(
      appBar: AppBar(
        // The active course, for orientation; switching is in Settings.
        title: const CourseTitle(),
        actions: [
          IconButton(
            tooltip: 'Zoom out',
            onPressed: _zoom <= _minZoom ? null : () => _setZoom(_zoom - 0.2),
            icon: const Icon(Icons.zoom_out),
          ),
          IconButton(
            tooltip: 'Zoom in',
            onPressed: _zoom >= _maxZoom ? null : () => _setZoom(_zoom + 0.2),
            icon: const Icon(Icons.zoom_in),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Long maps: back to where the learner is (first unfinished unit).
          if (current != null) ...[
            FloatingActionButton.small(
              key: const ValueKey('jump-current-unit'),
              heroTag: 'jump-fab',
              tooltip: 'Jump to current unit',
              onPressed: () => _jumpTo(current),
              child: const Icon(Icons.my_location),
            ),
            const SizedBox(height: 12),
          ],
          if (mistakeCount > 0) ...[
            FloatingActionButton.extended(
              key: const ValueKey('mistakes-button'),
              heroTag: 'mistakes-fab',
              tooltip: 'Practice your open mistakes',
              backgroundColor: scheme.tertiaryContainer,
              foregroundColor: scheme.onTertiaryContainer,
              onPressed: () => context.push(Routes.review),
              icon: const Icon(Icons.replay),
              label: Text('Review mistakes ($mistakeCount)'),
            ),
            const SizedBox(height: 12),
          ],
          // Hidden on a fresh profile: nothing can fade before anything was practiced.
          if (anyPracticed)
            FloatingActionButton.extended(
              key: const ValueKey('fading-button'),
              heroTag: 'fading-fab',
              tooltip: 'Practice what you are forgetting',
              onPressed: () => context.push(Routes.fading),
              icon: const Icon(Icons.restore),
              label: const Text("What's fading"),
            ),
        ],
      ),
      body: AsyncView(
        value: course,
        onRetry: () => ref.invalidate(courseDataProvider),
        builder: (course) {
          final l = layout.value;
          if (l == null) return const Center(child: CircularProgressIndicator());
          if (course.skills.isEmpty) {
            return const Center(child: Text('This course has no skills yet.'));
          }
          return SingleChildScrollView(
            key: const ValueKey('map-scroll'),
            padding: EdgeInsets.only(top: 8, bottom: fabRoom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MapHeaderSlot(),
                SkillMapView(
                  course: course,
                  layout: l,
                  stats: stats.value ?? const {},
                  style: skin.mapStyle(Theme.of(context).colorScheme),
                  lang: lang,
                  now: now,
                  zoom: _zoom,
                  reduceMotion: reduceMotion,
                  // A tap opens the skill's sheet first: what it is, the
                  // learner's tier and what the next one needs, then Start
                  // lesson, Test out, the grammar note and the word list
                  // (locked skills: what to do before it, and Start anyway).
                  onTap: (skill) => context.push(Routes.skill(skill.id)),
                  onLongPress: (skill) => context.push(Routes.skill(skill.id)),
                  unitKeys: {for (final u in course.units) u.id: _unitKey(u.id)},
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
