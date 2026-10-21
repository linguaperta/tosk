import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../progression/progression.dart';
import '../../providers.dart';
import '../common/markdown.dart';
import '../routes.dart';
import '../settings/app_settings.dart';
import '../theme/skill_icons.dart';
import 'branch_style.dart';
import 'ink_art.dart';
import 'node_painter.dart';
import 'skill_node.dart' show nodeIconColor;
import 'skill_stats.dart';
import 'tree_selector.dart' show topicNeedSentence, topicSkillNeed;

/// What a skill is and where the learner stands, then what to do with it.
///
/// Shown as a bottom sheet (route `/skill/:id`), opened by a tap (or long
/// press) on a map node: the title, kind and a short description (the grammar
/// note's first line, or sample words), the tier, strength and last practice,
/// what the next tier needs, then Start lesson (focus and length), Test out,
/// the grammar note and the word list (collapsed; [section] `note` or `words`
/// opens one). Locked skills say what to do first.
class SkillSheet extends ConsumerStatefulWidget {
  const SkillSheet({super.key, required this.skillId, this.section});
  final String skillId;

  /// `note` or `words`: that section starts expanded.
  final String? section;

  @override
  ConsumerState<SkillSheet> createState() => _SkillSheetState();
}

class _SkillSheetState extends ConsumerState<SkillSheet> {
  LessonFocus? _focus;
  SessionLength? _length;

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseDataProvider).value;
    final skill = course?.skill(widget.skillId);
    if (course == null || skill == null) {
      return const SizedBox(height: 200, child: Center(child: Text('Skill not found')));
    }
    final lang = ref.watch(sourceLangProvider);
    final allStats = ref.watch(skillStatsProvider).value ?? const <String, SkillStats>{};
    final stats = allStats[skill.id] ?? SkillStats.empty;
    final focus = _focus ?? ref.watch(settingsProvider).value?.defaultFocus ?? LessonFocus.mixed;
    final length = _length ?? ref.watch(settingsProvider).value?.defaultLength ?? SessionLength.normal;
    final note = course.note(skill.id, lang);
    final items = course.skillItems(skill.id);
    final unit = course.units.where((u) => u.id == skill.unitId).firstOrNull;
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final days = stats.daysSince(now);
    final needs = ref.watch(skillNextTierProvider(skill.id)).value;
    final noun = skillItemNoun(course.skillFacets(skill.id));
    final description = skillDescription(note, items, lang);
    final need = topicSkillNeed(CourseTrees.of(course), skill.id, allStats);
    // What to do first when locked (the main-tree skill a topic skill waits
    // for has its own line above).
    final recommended = [
      for (final r in skill.requires)
        if (r != need?.skill.id)
          if (course.skill(r) case final req?) pickLang(req.title, lang),
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      // Not a lazy list: the sheet is short (note and words collapsed), and
      // every action is built (and reachable for tests and accessibility).
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // The skill's stone as on the map: its tier, and cracks when it fades.
                _SkillMedal(skill: skill, stats: stats),
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
                        key: const ValueKey('skill-kind'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 10),
              Text(description, key: const ValueKey('skill-description'), style: theme.textTheme.bodyMedium),
            ],
            // A topic's skill: how many of its words the learner already
            // knows from the main tree or another topic (they aren't taught again).
            if (CourseTrees.of(course).treeOf(skill.id) case final topicId?)
              if (ref.watch(skillKnownWordsProvider(skill.id)).value case final k? when k.total > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.alt_route, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${CourseTrees.of(course).topic(topicId)?.titleIn(lang) ?? topicId} · '
                        '${k.known} of ${k.total} words already known',
                        key: const ValueKey('skill-known-words'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],
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
                Chip(
                  avatar: const Icon(Icons.workspace_premium_outlined, size: 16),
                  label: Text(_tierLabel(stats.tier)),
                ),
              ],
            ),
            if (stats.tier == MapTier.locked) ...[
              const SizedBox(height: 8),
              // A topic skill waiting for a main-tree skill (the topic's
              // anchor, or a later one this skill needs): which, where, and a
              // way there.
              if (need != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_outline, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        topicNeedSentence(need, lang),
                        key: const ValueKey('skill-needs'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('skill-needs-go'),
                    onPressed: () {
                      ref.read(mapFocusProvider.notifier).focus(need.skill.id);
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(need.unit == null ? 'Go there' : 'Go to unit ${need.unit}'),
                  ),
                ),
              ],
              Text(
                recommended.isEmpty
                    ? 'You can start this one anyway.'
                    : 'Recommended first: ${recommended.join(', ')}. You can start this one anyway.',
                key: const ValueKey('skill-locked-hint'),
                style: theme.textTheme.bodyMedium,
              ),
            ] else if (needs != null && needs.total > 0) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(needs.next == null ? Icons.emoji_events_outlined : Icons.flag_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nextTierText(needs, noun: noun),
                      key: const ValueKey('skill-next-tier'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, box) {
                final focusChooser = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Lesson focus', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    SegmentedButton<LessonFocus>(
                      key: const ValueKey('focus-chooser'),
                      showSelectedIcon: false,
                      segments: [
                        for (final f in LessonFocus.values) ButtonSegment(value: f, label: Text(focusShortLabel(f))),
                      ],
                      selected: {focus},
                      onSelectionChanged: (s) => setState(() => _focus = s.first),
                    ),
                  ],
                );
                final lengthChooser = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Length', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    SegmentedButton<SessionLength>(
                      key: const ValueKey('length-chooser'),
                      showSelectedIcon: false,
                      segments: [
                        for (final l in SessionLength.values)
                          ButtonSegment(
                            value: l,
                            label: Text('${l.exercises}', key: ValueKey('length-${l.name}')),
                            tooltip: '${sessionLengthLabel(l)}: ${l.exercises} exercises',
                          ),
                      ],
                      selected: {length},
                      onSelectionChanged: (s) => setState(() => _length = s.first),
                    ),
                  ],
                );
                // Side by side when there is room, else stacked.
                if (box.maxWidth >= 520) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: focusChooser),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: lengthChooser),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [focusChooser, const SizedBox(height: 10), lengthChooser],
                );
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('start-lesson'),
              onPressed: () => context.pushReplacement(Routes.lesson(skill.id, focus: focus, length: length.exercises)),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start lesson'),
            ),
            if (course.skillFacets(skill.id).isNotEmpty && stats.tier.index < MapTier.bronze.index) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('test-out'),
                onPressed: () => context.pushReplacement(Routes.testOut(skill.id)),
                icon: const Icon(Icons.fast_forward),
                label: const Text('Test out'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Already know this? A short quiz; pass it to mark the skill as learned.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (note != null)
              ExpansionTile(
                key: const ValueKey('skill-note'),
                initiallyExpanded: widget.section == 'note',
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.menu_book_outlined),
                title: Text('Grammar note', style: theme.textTheme.titleMedium),
                childrenPadding: const EdgeInsets.only(bottom: 12),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(padding: const EdgeInsets.all(16), child: MarkdownView(note)),
                  ),
                ],
              ),
            ExpansionTile(
              key: const ValueKey('skill-words'),
              initiallyExpanded: widget.section == 'words',
              tilePadding: EdgeInsets.zero,
              leading: const Icon(Icons.list_alt),
              title: Text('Word list (${items.length})', style: theme.textTheme.titleMedium),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items) _ItemTile(course: course, item: item, lang: lang, tense: skill.tense),
                if (items.isEmpty) const Text('No items in this skill yet.'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What a skill's items are called: verbs for a conjugation skill, nouns for
/// an article skill, else words.
String skillItemNoun(List<SkillFacet> facets) {
  if (facets.isNotEmpty && facets.every((f) => f.kind == FacetKind.form)) return 'verb';
  if (facets.isNotEmpty && facets.every((f) => f.kind == FacetKind.article)) return 'noun';
  return 'word';
}

String _plural(int n, String noun) => n == 1 ? noun : '${noun}s';

/// "Learn 6 more words to reach Bronze", "Get every word to 85% recall and
/// 7-day stability for Silver — 4 words to go".
String nextTierText(NextTierNeeds n, {String noun = 'word', TierRules rules = const TierRules()}) {
  final left = '${n.remaining} ${_plural(n.remaining, noun)}';
  switch (n.next) {
    case null:
      return 'Gold, the top tier. Practice now and then to keep it.';
    case SkillTier.bronze:
      if (n.tier == SkillTier.available || n.tier == SkillTier.locked || n.remaining == n.total) {
        return 'Learn all ${n.total} ${_plural(n.total, noun)} to reach Bronze.';
      }
      return 'Learn ${n.remaining} more ${_plural(n.remaining, noun)} to reach Bronze.';
    case SkillTier.silver:
      return 'Get every $noun to ${(rules.silverRecall * 100).round()}% recall and '
          '${rules.silverStabilityDays.round()}-day stability for Silver — $left to go. '
          'That takes spaced reviews over several days.';
    case SkillTier.gold:
      return 'Get every $noun to ${(rules.goldRecall * 100).round()}% recall and '
          '${rules.goldStabilityDays.round()}-day stability for Gold — $left to go.';
    default:
      return '';
  }
}

/// A one-line description: the grammar note's first sentence of text, or a
/// few of the skill's words.
String? skillDescription(String? note, List<Item> items, String lang) {
  if (note != null) {
    for (final raw in note.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('|') || line.startsWith('```')) continue;
      if (line.startsWith('---')) continue;
      var text = line.replaceFirst(RegExp(r'^([-*+>]|\d+\.)\s+'), '');
      text = text.replaceAll(RegExp(r'[*_`~]'), '');
      if (text.isEmpty) continue;
      if (text.length > 180) text = '${text.substring(0, 177).trimRight()}…';
      return text;
    }
  }
  if (items.isEmpty) return null;
  final sample = [for (final i in items.take(5)) itemLabel(i)];
  return 'Words: ${sample.join(', ')}${items.length > 5 ? ', …' : ''}';
}

String _tierLabel(MapTier t) => switch (t) {
  MapTier.locked => 'Locked',
  MapTier.available => 'New',
  MapTier.started => 'Started',
  MapTier.bronze => 'Bronze',
  MapTier.silver => 'Silver',
  MapTier.gold => 'Gold',
};

/// The skill's map stone in the sheet's header: its tier (bronze matte,
/// silver shiny, gold radiant), the strength ring, the cracks of decay and
/// the skill's icon. Static (no twinkle motion).
class _SkillMedal extends ConsumerWidget {
  const _SkillMedal({required this.skill, required this.stats});
  final Skill skill;
  final SkillStats stats;

  static const double size = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(skinProvider).mapStyle(Theme.of(context).colorScheme);
    final branchStyle = ref.watch(branchStyleProvider);
    final stone = NodePainter.stoneRadius(size, branchStyle.extent) * 2;
    final cracked = NodePainter.crackLevel(stats.tier, stats.decay, branchStyle) > 0;
    return Semantics(
      key: const ValueKey('skill-medal'),
      label: '${_tierLabel(stats.tier)}${cracked ? ', fading' : ''}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: NodePainter(
            tier: stats.tier,
            ink: style.ink,
            strength: stats.strength,
            style: branchStyle,
            decay: stats.decay,
            seed: inkSeed(skill.id),
            monochrome: style.monochrome,
          ),
          child: Center(
            child: Icon(
              skillIcon(skill),
              size: stone * 0.5,
              color: nodeIconColor(style, stats.tier),
            ),
          ),
        ),
      ),
    );
  }
}

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
