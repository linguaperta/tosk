import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../common/async_view.dart';
import '../routes.dart';
import '../shell/course_switcher.dart';
import '../slots/progression_slots.dart';
import 'skill_map_view.dart';

/// Home: the skill map for the active course.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _minZoom = 0.7, _maxZoom = 1.9;
  double _zoom = 1;

  void _setZoom(double z) => setState(() => _zoom = z.clamp(_minZoom, _maxZoom));

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseDataProvider);
    final layout = ref.watch(mapLayoutProvider);
    final stats = ref.watch(skillStatsProvider);
    final lang = ref.watch(sourceLangProvider);
    final skin = ref.watch(skinProvider);
    final reduceMotion = ref.watch(reduceMotionProvider);
    final defaultFocus = ref.watch(settingsProvider.select((s) => s.value?.defaultFocus));
    final now = ref.watch(clockProvider)();
    final mistakeCount = ref.watch(openMistakesProvider).value?.length ?? 0;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const CourseSwitcher(),
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
            // Room below the last band for the action buttons.
            padding: EdgeInsets.only(top: 8, bottom: mistakeCount > 0 ? 168 : 96),
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
                  onTap: (skill) => context.push(Routes.lesson(skill.id, focus: defaultFocus)),
                  onLongPress: (skill) => context.push(Routes.skill(skill.id)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
