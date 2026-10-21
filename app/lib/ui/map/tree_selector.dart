/// The map's app-bar title on a course with topics: a menu of the course's
/// trees (docs/ui.md "Topic trees"). The main tree comes first, then each
/// topic with its progress; picking one switches the map ([mapTreeProvider]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../shell/course_switcher.dart';
import '../theme/bw_skin.dart';
import 'skill_stats.dart';

/// Progress of a topic: how many of its skills are started (practised or tested out).
({int started, int total}) topicProgress(CourseTrees trees, String topicId, Map<String, SkillStats> stats) {
  final skills = [for (final s in trees.skillsOf(topicId)) if (trees.course.skillFacets(s.id).isNotEmpty) s];
  final started = skills.where((s) => (stats[s.id]?.tier.index ?? 0) >= MapTier.started.index).length;
  return (started: started, total: skills.length);
}

String topicProgressText(({int started, int total}) p) {
  final skills = p.total == 1 ? 'skill' : 'skills';
  return p.started == 0 ? '${p.total} $skills, not started' : '${p.started} of ${p.total} $skills started';
}

/// A main-tree skill a topic skill waits for, and its unit's number.
typedef TopicNeed = ({Skill skill, int? unit});

/// What locked topic skill [skillId] still needs from the main tree: the last
/// (in course order) of its main-tree requirements that is not started yet,
/// so "needs The conditional · unit 12" (pack format 1.2: a topic starts at
/// its anchor, and a later skill of it may require a later main-tree skill;
/// it stays locked until that skill is started). Null for a main-tree skill,
/// a skill that isn't locked, or when every main-tree requirement is started.
TopicNeed? topicSkillNeed(CourseTrees trees, String skillId, Map<String, SkillStats> stats) {
  if (!trees.inTopic(skillId) || (stats[skillId]?.tier ?? MapTier.available) != MapTier.locked) return null;
  for (final r in trees.mainRequirements(skillId).reversed) {
    if ((stats[r]?.tier.index ?? 0) >= MapTier.started.index) continue;
    if (trees.course.skill(r) case final s?) return (skill: s, unit: trees.mainUnitNumber(r));
  }
  return null;
}

/// "The conditional: parlerei · unit 12".
String topicNeedText(TopicNeed n, String lang) =>
    '${pickLang(n.skill.title, lang)}${n.unit == null ? '' : ' · unit ${n.unit}'}';

/// The skill sheet's line: "Needs The conditional: parlerei from unit 12 of
/// the main tree. It opens once you have started it."
String topicNeedSentence(TopicNeed n, String lang) =>
    'Needs ${pickLang(n.skill.title, lang)} ${n.unit == null ? 'from' : 'from unit ${n.unit} of'} the main tree. '
    'It opens once you have started it.';

/// The tree menu in the map's app bar. [onSelect] gets the chosen tree
/// (null: the main tree); without topics it is just the course title.
class TreeSelector extends ConsumerWidget {
  const TreeSelector({super.key, required this.course, required this.tree, required this.onSelect});
  final CourseData course;
  final String? tree;
  final void Function(String? tree) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trees = CourseTrees.of(course);
    if (!trees.hasTopics) return const CourseTitle();
    final lang = ref.watch(sourceLangProvider);
    final stats = ref.watch(skillStatsProvider).value ?? const <String, SkillStats>{};
    final theme = Theme.of(context);
    final mono = isBw(context);
    final courseTitle = pickLang(course.meta.title, lang);
    final topic = tree == null ? null : trees.topic(tree!);
    final current = topic?.titleIn(lang);

    Widget entry({required String title, required String subtitle, required bool selected, double? progress, IconData? icon}) =>
        Row(
          children: [
            SizedBox(
              width: 28,
              child: selected ? Icon(Icons.check, size: 20, color: theme.colorScheme.onSurface) : null,
            ),
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  if (progress != null) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      color: mono ? kBwBlack : theme.colorScheme.secondary,
                      backgroundColor: mono ? kBwGray : theme.colorScheme.surfaceContainerHighest,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );

    return PopupMenuButton<String>(
      key: const ValueKey('tree-selector'),
      tooltip: 'Switch tree',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
      onSelected: (v) => onSelect(v.isEmpty ? null : v),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          key: const ValueKey('tree-item-main'),
          value: '',
          height: 56,
          child: Semantics(
            selected: tree == null,
            child: entry(title: courseTitle, subtitle: 'Main tree', selected: tree == null, icon: Icons.park_outlined),
          ),
        ),
        for (final t in trees.topics)
          PopupMenuItem<String>(
            key: ValueKey('tree-item-${t.id}'),
            value: t.id,
            height: 64,
            child: Builder(builder: (context) {
              final p = topicProgress(trees, t.id, stats);
              return Semantics(
                selected: tree == t.id,
                child: entry(
                  title: t.titleIn(lang),
                  subtitle: 'Topic · ${topicProgressText(p)}',
                  selected: tree == t.id,
                  progress: p.total == 0 ? 0 : p.started / p.total,
                  icon: Icons.alt_route,
                ),
              );
            }),
          ),
      ],
      child: Semantics(
        button: true,
        label: '${current ?? courseTitle}, ${current == null ? 'main tree' : 'topic of $courseTitle'}. Switch tree',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: current == null
                    ? const CourseTitle()
                    : Text(current, key: const ValueKey('tree-title'), overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }
}
