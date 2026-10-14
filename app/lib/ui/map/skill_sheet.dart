import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../common/markdown.dart';
import '../routes.dart';
import '../settings/app_settings.dart';
import '../theme/skill_icons.dart';
import 'skill_stats.dart';

/// Skill details: start a lesson with a chosen focus, the grammar note and the item list.
/// Shown as a bottom sheet (route `/skill/:id`, opened by long-press on a node).
class SkillSheet extends ConsumerStatefulWidget {
  const SkillSheet({super.key, required this.skillId});
  final String skillId;

  @override
  ConsumerState<SkillSheet> createState() => _SkillSheetState();
}

class _SkillSheetState extends ConsumerState<SkillSheet> {
  LessonFocus? _focus;

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseDataProvider).value;
    final skill = course?.skill(widget.skillId);
    if (course == null || skill == null) {
      return const SizedBox(height: 200, child: Center(child: Text('Skill not found')));
    }
    final lang = ref.watch(sourceLangProvider);
    final stats = ref.watch(skillStatsProvider).value?[skill.id] ?? SkillStats.empty;
    final focus = _focus ?? ref.watch(settingsProvider).value?.defaultFocus ?? LessonFocus.mixed;
    final note = course.note(skill.id, lang);
    final items = course.skillItems(skill.id);
    final unit = course.units.where((u) => u.id == skill.unitId).firstOrNull;
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final days = stats.daysSince(now);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(skillIcon(skill), color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pickLang(skill.title, lang), style: theme.textTheme.titleLarge),
                    Text(
                      [
                        if (unit != null) pickLang(unit.title, lang),
                        skill.kind == SkillKind.grammar ? 'Grammar' : 'Vocabulary',
                        if (skill.tense != null) course.meta.tenseLabel(skill.tense!, lang),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Chip(
                avatar: const Icon(Icons.bolt, size: 16),
                label: Text('Strength ${(stats.strength * 100).round()}%'),
              ),
              Chip(
                avatar: const Icon(Icons.schedule, size: 16),
                label: Text(days == null ? 'Not practiced yet' : 'Practiced ${daysAgoLabel(days)}'),
              ),
              Chip(avatar: const Icon(Icons.workspace_premium_outlined, size: 16), label: Text(_tierLabel(stats.tier))),
            ],
          ),
          if (stats.tier == MapTier.locked) ...[
            const SizedBox(height: 8),
            Text(
              'Recommended first: ${[for (final r in skill.requires)
                if (course.skill(r) case final req?) pickLang(req.title, lang)].join(', ')}. You can start this one anyway.',
              key: const ValueKey('skill-locked-hint'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          Text('Lesson focus', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<LessonFocus>(
            key: const ValueKey('focus-chooser'),
            showSelectedIcon: false,
            segments: [for (final f in LessonFocus.values) ButtonSegment(value: f, label: Text(focusShortLabel(f)))],
            selected: {focus},
            onSelectionChanged: (s) => setState(() => _focus = s.first),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('start-lesson'),
            onPressed: () => context.pushReplacement(Routes.lesson(skill.id, focus: focus)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start lesson'),
          ),
          if (note != null) ...[
            const SizedBox(height: 24),
            Text('Grammar note', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(padding: const EdgeInsets.all(16), child: MarkdownView(note)),
            ),
          ],
          const SizedBox(height: 24),
          Text('Words (${items.length})', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final item in items) _ItemTile(course: course, item: item, lang: lang, tense: skill.tense),
          if (items.isEmpty) const Text('No items in this skill yet.'),
        ],
      ),
    );
  }
}

String _tierLabel(MapTier t) => switch (t) {
  MapTier.locked => 'Locked',
  MapTier.available => 'New',
  MapTier.started => 'Started',
  MapTier.bronze => 'Bronze',
  MapTier.silver => 'Silver',
  MapTier.gold => 'Gold',
};

/// "il pane", "l'acqua", "mangiare".
String itemLabel(Item item) {
  final a = item.article;
  if (a == null || a.isEmpty) return item.lemma;
  return a.endsWith("'") ? '$a${item.lemma}' : '$a ${item.lemma}';
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.course, required this.item, required this.lang, this.tense});
  final CourseData course;
  final Item item;
  final String lang;
  final String? tense;

  @override
  Widget build(BuildContext context) {
    final gloss = item.glosses(lang).join(', ');
    final forms = item.isVerb && tense != null ? course.verbFormsInTense(item.id, tense!) : const <VerbForm>[];
    if (forms.isEmpty) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(itemLabel(item)),
        subtitle: gloss.isEmpty ? null : Text(gloss),
      );
    }
    return ExpansionTile(
      dense: true,
      tilePadding: EdgeInsets.zero,
      title: Text(itemLabel(item)),
      subtitle: gloss.isEmpty ? null : Text(gloss),
      childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
      expandedAlignment: Alignment.centerLeft,
      children: [
        for (final f in forms)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    course.meta.personLabel(f.person, lang),
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(child: Text(f.form)),
              ],
            ),
          ),
      ],
    );
  }
}
