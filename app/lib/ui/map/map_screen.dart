import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
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
import 'tree_selector.dart';

/// Home: the skill map for the active course.
///
/// A course with topics has several trees: the main tree (with a branch
/// leaving the map at each topic's anchor; a tap on it opens the topic) and one map per topic,
/// whose root leads back. The app bar's title is then a menu of the trees
/// ([TreeSelector]); each tree keeps its own scroll position.
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

  /// The scroll offset of each tree while another is shown ('' is the main tree).
  final Map<String, double> _offsets = {};
  ScrollController _scroll = ScrollController();
  String? _shownTree;

  GlobalKey _unitKey(String unitId) => _unitKeys[unitId] ??= GlobalKey(debugLabel: 'unit-$unitId');

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the map so [unitId]'s band is at the top.
  void _jumpTo(String unitId) {
    final ctx = _unitKeys[unitId]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: ref.read(motionProvider).long, curve: Curves.easeOutCubic);
  }

  void _setZoom(double z) => setState(() => _zoom = z.clamp(_minZoom, _maxZoom));

  void _showTree(String? tree) => ref.read(mapTreeProvider.notifier).show(tree);

  /// Brings [skillId] into view in its own tree ([mapFocusProvider]): shows
  /// that tree, then scrolls its unit's band to the top once it is built.
  void _focus(String skillId) {
    final course = ref.read(courseDataProvider).value;
    final skill = course?.skill(skillId);
    if (course == null || skill == null) return;
    _showTree(CourseTrees.of(course).treeOf(skillId));
    var frames = 0;
    void tryJump(Duration _) {
      if (!mounted) return;
      if (_unitKeys[skill.unitId]?.currentContext != null) {
        _jumpTo(skill.unitId);
      } else if (++frames < 10) {
        WidgetsBinding.instance.addPostFrameCallback(tryJump);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(tryJump);
  }

  /// Switches the scroll controller when the tree changes: the old tree's
  /// offset is kept, the new one starts where it was left.
  void _followTree(String? tree) {
    if (tree == _shownTree) return;
    if (_scroll.hasClients) _offsets[_shownTree ?? ''] = _scroll.offset;
    final old = _scroll;
    // The old scroll view still uses it until this frame is built.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _scroll = ScrollController(initialScrollOffset: _offsets[tree ?? ''] ?? 0);
    _shownTree = tree;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(mapFocusProvider, (_, skillId) {
      if (skillId == null) return;
      ref.read(mapFocusProvider.notifier).clear();
      _focus(skillId);
    });
    final course = ref.watch(courseDataProvider);
    final stats = ref.watch(skillStatsProvider);
    final lang = ref.watch(sourceLangProvider);
    final skin = ref.watch(skinProvider);
    final reduceMotion = ref.watch(reduceMotionProvider);
    final now = ref.watch(clockProvider)();
    final mistakeCount = ref.watch(openMistakesProvider).value?.length ?? 0;
    final anyPracticed = stats.value?.values.any((s) => s.practiced) ?? false;
    final c = course.value;
    final trees = c == null ? null : CourseTrees.of(c);
    // A topic that isn't there (another course) shows the main tree.
    final topic = switch (ref.watch(mapTreeProvider)) {
      final id? => trees?.topic(id),
      null => null,
    };
    _followTree(topic?.id);
    final layout = topic == null ? ref.watch(mapLayoutProvider) : ref.watch(topicLayoutProvider(topic.id));
    final treeUnits = trees?.unitsOf(topic?.id) ?? const <Unit>[];
    final longMap = treeUnits.length >= _longMapUnits;
    final current = !longMap || c == null
        ? null
        : currentUnitId([
            for (final u in treeUnits)
              for (final s in c.skills)
                if (s.unitId == u.id) (unitId: u.id, skillId: s.id),
          ], stats.value ?? const {});
    final showBar = MapActionBar.shows(mistakes: mistakeCount > 0, fading: anyPracticed, jump: current != null);

    return Scaffold(
      appBar: AppBar(
        // The active course, for orientation (switching courses is in
        // Settings); with topics, a menu of the course's trees.
        title: c == null ? const CourseTitle() : TreeSelector(course: c, tree: topic?.id, onSelect: _showTree),
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
          final trees = CourseTrees.of(course);
          final s = stats.value ?? const <String, SkillStats>{};
          final courseTitle = pickLang(course.meta.title, lang);
          final anchor = topic == null ? null : course.skill(topic.anchor);
          return SingleChildScrollView(
            key: ValueKey(topic == null ? 'map-scroll' : 'map-scroll-${topic.id}'),
            controller: _scroll,
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MapHeaderSlot(),
                SkillMapView(
                  key: ValueKey('map-${topic?.id ?? 'main'}'),
                  course: course,
                  layout: l,
                  stats: s,
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
                  // The main tree: a branch leaves the map at each topic's anchor.
                  branches: topic != null
                      ? const []
                      : [
                          for (final t in trees.topics)
                            TopicBranch(
                              id: t.id,
                              anchor: t.anchor,
                              title: t.titleIn(lang),
                              shortTitle: t.shortTitleIn(lang),
                              // Open once the anchor is started; browsable before.
                              locked: (s[t.anchor]?.tier.index ?? 0) < MapTier.started.index,
                              progress: topicProgressText(topicProgress(trees, t.id, s)),
                            ),
                        ],
                  onTopic: _showTree,
                  // A topic's map: its root says where it grows from and leads back.
                  unitTitles: topic == null
                      ? const {}
                      : {kTopicRootUnit: 'From $courseTitle · ${anchor == null ? '' : pickLang(anchor.title, lang)}'},
                  root: topic == null || anchor == null
                      ? null
                      : TopicRoot(
                          skillId: anchor.id,
                          label: 'Back to the $courseTitle main tree: ${topic.titleIn(lang)} grows from '
                              '${pickLang(anchor.title, lang)}',
                          onTap: () => _showTree(null),
                        ),
                  // A locked topic skill that waits for a main-tree skill (its
                  // anchor, or a later one it needs) says so under its title.
                  needs: topic == null
                      ? const {}
                      : {
                          for (final sk in trees.skillsOf(topic.id))
                            if (topicSkillNeed(trees, sk.id, s) case final n?)
                              sk.id: (skillId: n.skill.id, title: pickLang(n.skill.title, lang), unit: n.unit),
                        },
                  onNeeds: _focus,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
