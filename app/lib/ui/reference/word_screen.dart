/// One word of the reference: gloss, article, part of speech, tags, the skills
/// that teach it, example sentences, and for verbs the full conjugation table.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../engine/reference.dart';
import '../../providers.dart';
import '../common/async_view.dart';
import '../common/word_popover.dart';
import '../routes.dart';
import 'reference_screen.dart';

class WordScreen extends ConsumerWidget {
  const WordScreen({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseDataProvider);
    final lang = ref.watch(sourceLangProvider);
    return AsyncView(
      value: course,
      onRetry: () => ref.invalidate(courseDataProvider),
      builder: (course) {
        final item = course.item(itemId);
        if (item == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This word is not in the course.', key: ValueKey('word-missing'))),
          );
        }
        final reference = CourseReference.of(course);
        final theme = Theme.of(context);
        final glosses = item.glosses(lang);
        final skills = reference.skillsTeaching(item.id);
        final examples = reference.examples(item.id);
        final table = item.isVerb ? reference.verbTable(item.id, lang) : null;
        final verb = course.verb(item.id);
        return Scaffold(
          appBar: AppBar(title: Text(wordLabel(item), key: const ValueKey('word-title'))),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                key: const ValueKey('word-list'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    glosses.isEmpty ? '—' : glosses.join(', '),
                    key: const ValueKey('word-glosses'),
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      posLabel(item.pos),
                      if (item.gender != null) item.gender!,
                      if (item.plural != null) 'plural: ${item.plural}',
                      if (item.variants.isNotEmpty) 'also: ${item.variants.join(', ')}',
                      if (verb?.auxiliary != null) 'auxiliary: ${verb!.auxiliary!.replaceAll('|', ' / ')}',
                      if (verb?.irregular ?? false) 'irregular',
                    ].join(' · '),
                    key: const ValueKey('word-facts'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (item.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final t in item.tags) Chip(label: Text(t), visualDensity: VisualDensity.compact)],
                    ),
                  ],
                  if (skills.isNotEmpty) ...[
                    _Heading('Taught in'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in skills)
                          ActionChip(
                            key: ValueKey('word-skill-${s.id}'),
                            avatar: const Icon(Icons.school_outlined, size: 18),
                            label: Text(pickLang(s.title, lang)),
                            onPressed: () => context.push(Routes.skill(s.id)),
                          ),
                      ],
                    ),
                  ],
                  if (table != null && !table.isEmpty) ...[
                    _Heading('Conjugation'),
                    if (table.tenses.expand((t) => t.cells).any((c) => c.irregular))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text.rich(
                          key: const ValueKey('irregular-legend'),
                          TextSpan(
                            children: [
                              TextSpan(text: 'irregular', style: irregularStyle(theme.textTheme.bodyMedium)),
                              const TextSpan(text: ': forms that break the regular pattern'),
                            ],
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    for (final t in table.tenses) VerbTenseCard(tense: t, course: course, lang: lang),
                    if (table.nonFinite.isNotEmpty)
                      VerbTenseCard(
                        tense: VerbTense(
                          tense: '_',
                          label: 'Other forms',
                          cells: [
                            for (final t in table.nonFinite)
                              for (final c in t.cells)
                                VerbCell(person: t.label, form: c.form, alts: c.alts, irregular: c.irregular),
                          ],
                        ),
                        course: course,
                        lang: lang,
                        personIsLabel: true,
                      ),
                  ],
                  if (examples.isNotEmpty) ...[
                    _Heading('Examples'),
                    for (final s in examples)
                      Padding(
                        key: ValueKey('word-example-${s.id}'),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TappableSentence(
                              tokens: [
                                for (final t in s.tokens)
                                  TokenRef(t.t, pre: t.pre, itemId: t.lex, form: t.form, isWord: t.isWord),
                              ],
                              keyPrefix: '${s.id}-',
                              style: theme.textTheme.bodyLarge,
                            ),
                            if (s.translation(lang) case final tr?)
                              Text(tr, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Irregular forms: bold and underlined (never color alone).
TextStyle? irregularStyle(TextStyle? base) =>
    base?.copyWith(fontWeight: FontWeight.w800, decoration: TextDecoration.underline, decorationThickness: 2);

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// One tense of a verb: persons in course order, irregular forms bold and underlined.
class VerbTenseCard extends StatelessWidget {
  const VerbTenseCard({
    super.key,
    required this.tense,
    required this.course,
    required this.lang,
    this.personIsLabel = false,
  });

  final VerbTense tense;
  final CourseData course;
  final String lang;

  /// [VerbCell.person] already is a label (the "other forms" card).
  final bool personIsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('verb-tense-${tense.tense}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tense.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final c in tense.cells)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        personIsLabel ? c.person : course.meta.personLabel(c.person, lang),
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: c.form,
                              style: c.irregular ? irregularStyle(theme.textTheme.bodyLarge) : null,
                              semanticsLabel: c.irregular ? '${c.form}, irregular' : null,
                            ),
                            if (c.alts.isNotEmpty)
                              TextSpan(text: ' (${c.alts.join(', ')})', style: theme.textTheme.bodySmall),
                          ],
                        ),
                        key: ValueKey('verb-form-${tense.tense}-${c.person}'),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
