import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../common/async_view.dart';
import '../routes.dart';
import '../shell/course_switcher.dart';
import '../slots/progression_slots.dart';
import '../stories/story_providers.dart';
import 'branch_style.dart';
import 'map_action_bar.dart';
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
    final showBar = MapActionBar.shows(mistakes: mistakeCount > 0, fading: anyPracticed, jump: current != null);

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
      // The actions sit in a bar under the map (not floating over it), so
      // they never cover a skill node.
      bottomNavigationBar: showBar
          ? MapActionBar(
              mistakeCount: mistakeCount,
              onMistakes: mistakeCount > 0 ? () => context.push(Routes.review) : null,
              // Hidden on a fresh profile: nothing can fade before anything was practiced.
              onFading: anyPracticed ? () => context.push(Routes.fading) : null,
              onJump: current != null ? () => _jumpTo(current) : null,
            )
          : null,
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
            padding: const EdgeInsets.only(top: 8, bottom: 24),
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
                  twinkle: ref.watch(twinkleProvider),
                  branchStyle: ref.watch(branchStyleProvider),
                  // A tap opens the skill's sheet first: what it is, the
                  // learner's tier and what the next one needs, then Start
                  // lesson, Test out, the grammar note and the word list
                  // (locked skills: what to do before it, and Start anyway).
                  onTap: (skill) => context.push(Routes.skill(skill.id)),
                  onLongPress: (skill) => context.push(Routes.skill(skill.id)),
                  unitKeys: {for (final u in course.units) u.id: _unitKey(u.id)},
                  // Units with graded stories get a book button in their band.
                  storyCounts: {for (final s in course.stories) s.unitId: 0}
                    ..updateAll((unit, _) => course.stories.where((s) => s.unitId == unit).length),
                  storyUnitsOpen: ref.watch(storyUnitsUnlockedProvider).value ?? const {},
                  onUnitStories: (unitId) => context.push(Routes.unitStories(unitId)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
