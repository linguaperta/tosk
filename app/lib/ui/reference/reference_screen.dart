/// The Reference tab: word and conjugation lookup over the active course,
/// and the grammar library (every grammar note, by unit).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../engine/reference.dart';
import '../../providers.dart';
import '../common/async_view.dart';
import '../common/markdown.dart';
import '../routes.dart';
import '../theme/bw_skin.dart';

/// Lookup and Grammar as two tabs. [query] prefills the search; [tab] is
/// `lookup` (default) or `grammar`.
class ReferenceScreen extends ConsumerStatefulWidget {
  const ReferenceScreen({super.key, this.query, this.tab});
  final String? query;
  final String? tab;

  @override
  ConsumerState<ReferenceScreen> createState() => _ReferenceScreenState();
}

class _ReferenceScreenState extends ConsumerState<ReferenceScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.tab == 'grammar' ? 1 : 0,
    animationDuration: ref.read(reduceMotionProvider) ? Duration.zero : null,
  );

  @override
  void didUpdateWidget(ReferenceScreen old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab && widget.tab != null) _tabs.index = widget.tab == 'grammar' ? 1 : 0;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reference'),
        bottom: TabBar(
          key: const ValueKey('reference-tabs'),
          controller: _tabs,
          tabs: const [
            Tab(key: ValueKey('reference-tab-lookup'), text: 'Lookup'),
            Tab(key: ValueKey('reference-tab-grammar'), text: 'Grammar'),
          ],
        ),
      ),
      // Tabs switch without a swipeable page view (no sideways animation on
      // e-ink, no accidental swipes); both pages keep their state.
      body: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => IndexedStack(
          index: _tabs.index,
          children: [
            LookupView(key: ValueKey('lookup-${widget.query ?? ''}'), initialQuery: widget.query ?? ''),
            const GrammarLibraryView(),
          ],
        ),
      ),
    );
  }
}

// ====================================================================== lookup

/// Search field at the bottom (thumb zone), results above.
class LookupView extends ConsumerStatefulWidget {
  const LookupView({super.key, this.initialQuery = ''});
  final String initialQuery;

  @override
  ConsumerState<LookupView> createState() => _LookupViewState();
}

class _LookupViewState extends ConsumerState<LookupView> {
  late final TextEditingController _query = TextEditingController(text: widget.initialQuery);
  bool _verbsOnly = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseDataProvider);
    final lang = ref.watch(sourceLangProvider);
    final theme = Theme.of(context);
    return AsyncView(
      value: course,
      onRetry: () => ref.invalidate(courseDataProvider),
      builder: (course) {
        final reference = CourseReference.of(course);
        final hits = reference.search(_query.text, lang, verbsOnly: _verbsOnly);
        return Column(
          children: [
            Expanded(
              child: hits.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No word matches "${_query.text}".',
                          key: const ValueKey('lookup-empty'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ListView.builder(
                          key: const ValueKey('lookup-list'),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: hits.length,
                          itemBuilder: (context, i) => _HitTile(hit: hits[i], course: course, lang: lang),
                        ),
                      ),
                    ),
            ),
            Material(
              color: theme.colorScheme.surface,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isBw(context) ? kBwBlack : theme.colorScheme.outlineVariant,
                      width: isBw(context) ? kBwBorder : 1,
                    ),
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ChoiceChip(
                                key: const ValueKey('lookup-all'),
                                label: const Text('All words'),
                                selected: !_verbsOnly,
                                onSelected: (_) => setState(() => _verbsOnly = false),
                              ),
                              ChoiceChip(
                                key: const ValueKey('lookup-verbs'),
                                label: const Text('Verbs'),
                                selected: _verbsOnly,
                                onSelected: (_) => setState(() => _verbsOnly = true),
                              ),
                              Text(
                                '${hits.length}${hits.length >= 300 ? '+' : ''} found',
                                key: const ValueKey('lookup-count'),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            key: const ValueKey('lookup-field'),
                            controller: _query,
                            onChanged: (_) => setState(() {}),
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: 'Search a word, a form or a translation',
                              isDense: true,
                              border: const OutlineInputBorder(),
                              suffixIcon: _query.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear',
                                      icon: const Icon(Icons.clear),
                                      onPressed: () => setState(_query.clear),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.course, required this.lang});
  final ReferenceHit hit;
  final CourseData course;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final item = hit.item;
    final glosses = item.glosses(lang).join(', ');
    final matched = hit.matched;
    final via = matched == null
        ? null
        : switch (hit.match) {
            ReferenceMatch.form => 'form: $matched',
            ReferenceMatch.lemma || ReferenceMatch.lemmaPrefix => matched,
            _ => null,
          };
    return ListTile(
      key: ValueKey('lookup-hit-${item.id}'),
      title: Text(wordLabel(item)),
      subtitle: Text([if (glosses.isNotEmpty) glosses, ?via].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(posLabel(item.pos), style: Theme.of(context).textTheme.labelSmall),
      onTap: () => context.push(Routes.word(item.id)),
    );
  }
}

/// `il pane`, `l'acqua`, `mangiare`.
String wordLabel(Item item) {
  final a = item.article;
  if (a == null || a.trim().isEmpty) return item.lemma;
  final first = a.split(RegExp(r'[|/]')).first.trim();
  return first.endsWith("'") || first.endsWith('’') ? '$first${item.lemma}' : '$first ${item.lemma}';
}

/// Readable part of speech.
String posLabel(String pos) => switch (pos) {
  'noun' => 'noun',
  'verb' => 'verb',
  'adj' => 'adjective',
  'adv' => 'adverb',
  'pron' => 'pronoun',
  'prep' => 'preposition',
  'conj' => 'conjunction',
  'intj' => 'interjection',
  'det' => 'determiner',
  'num' => 'number',
  _ => pos,
};

// ====================================================================== grammar

/// Every grammar note of the active course, grouped by unit, in the source
/// language, each with "Practice this skill".
class GrammarLibraryView extends ConsumerWidget {
  const GrammarLibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseDataProvider);
    final lang = ref.watch(sourceLangProvider);
    final theme = Theme.of(context);
    return AsyncView(
      value: course,
      onRetry: () => ref.invalidate(courseDataProvider),
      builder: (course) {
        final sections = <Widget>[];
        for (final u in course.units) {
          final notes = [
            for (final s in course.skills)
              if (s.unitId == u.id)
                if (course.note(s.id, lang) case final note?) (s, note),
          ];
          if (notes.isEmpty) continue;
          sections.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
              child: Text(pickLang(u.title, lang), style: theme.textTheme.titleMedium),
            ),
          );
          for (final (skill, note) in notes) {
            sections.add(_NoteCard(skill: skill, note: note, lang: lang, course: course));
          }
        }
        if (sections.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('This course has no grammar notes yet.', key: ValueKey('grammar-empty')),
            ),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              key: const ValueKey('grammar-list'),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: sections,
            ),
          ),
        );
      },
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.skill, required this.note, required this.lang, required this.course});
  final Skill skill;
  final String note;
  final String lang;
  final CourseData course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('grammar-note-${skill.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(pickLang(skill.title, lang)),
        subtitle: Text(
          [
            skill.kind == SkillKind.grammar ? 'Grammar' : 'Vocabulary',
            if (skill.tense != null) course.meta.tenseLabel(skill.tense!, lang),
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MarkdownView(note),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: ValueKey('grammar-practice-${skill.id}'),
              onPressed: () => context.push(
                Routes.lesson(skill.id, focus: skill.kind == SkillKind.grammar ? LessonFocus.grammar : null),
              ),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Practice this skill'),
            ),
          ),
        ],
      ),
    );
  }
}
