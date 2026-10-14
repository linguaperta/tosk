/// The course picker: every available course (bundled and installed packs,
/// a local Sarnami pack included) with + / − to add it to or remove it from
/// "my courses", and a preview. The rest of the app only shows added courses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../reference/reference_screen.dart' show wordLabel;
import '../routes.dart';
import '../settings/app_settings.dart';
import '../shell/course_switcher.dart' show DemoBadge, UnverifiedBadge;
import '../theme/bw_skin.dart';

/// Opens the picker as a bottom sheet. On the first run ([firstRun]), closing
/// it without adding anything adds the course shown underneath, so the app
/// always has at least one course.
Future<void> showCoursePicker(BuildContext context, {bool firstRun = false}) async {
  final container = ProviderScope.containerOf(context);
  final router = GoRouter.maybeOf(context);
  final action = await showModalBottomSheet<_PickerAction>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => CoursePickerSheet(firstRun: firstRun),
  );
  final settings = await container.read(settingsProvider.future);
  if (settings.myCourseIds.isEmpty) {
    final active = await container.read(activeCourseIdProvider.future);
    await container.read(settingsProvider.notifier).change((s) => s.copyWith(coursesAdded: [active], courseId: active));
  }
  if (action is _FindLevel) router?.push(Routes.placement);
}

sealed class _PickerAction {
  const _PickerAction();
}

class _FindLevel extends _PickerAction {
  const _FindLevel();
}

class CoursePickerSheet extends ConsumerStatefulWidget {
  const CoursePickerSheet({super.key, this.firstRun = false});
  final bool firstRun;

  @override
  ConsumerState<CoursePickerSheet> createState() => _CoursePickerSheetState();
}

class _CoursePickerSheetState extends ConsumerState<CoursePickerSheet> {
  final Set<String> _expanded = {};

  Future<void> _add(String id) async {
    final ctl = ref.read(settingsProvider.notifier);
    final s = await ref.read(settingsProvider.future);
    final available = {for (final c in await ref.read(availableCoursesProvider.future)) c.id};
    final mine = [
      for (final c in s.myCourseIds)
        if (available.contains(c)) c,
    ];
    if (mine.contains(id)) return;
    await ctl.change(
      (s) => s.copyWith(coursesAdded: [...mine, id], courseId: mine.isEmpty || !mine.contains(s.courseId) ? id : null),
    );
    // A course without any progress: start from scratch or find my level.
    final log = await ref.read(progressStoreProvider).log(courseId: id);
    if (!mounted || log.isNotEmpty) return;
    final level = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Where do you want to start?'),
        content: const Text(
          'Start from scratch, or find your level: a short test, unit by unit, that marks what you '
          'already know as learned.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('placement-scratch'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Start from scratch'),
          ),
          FilledButton(
            key: const ValueKey('placement-find'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Find my level'),
          ),
        ],
      ),
    );
    if (level == true && mounted) {
      await ctl.change((s) => s.copyWith(courseId: id));
      if (mounted) Navigator.of(context).pop(const _FindLevel());
    }
  }

  Future<void> _remove(String id) async {
    final ctl = ref.read(settingsProvider.notifier);
    final s = await ref.read(settingsProvider.future);
    final mine = [
      for (final c in s.myCourseIds)
        if (c != id) c,
    ];
    if (mine.isEmpty) return; // keep at least one course
    await ctl.change((s) => s.copyWith(coursesAdded: mine, courseId: s.courseId == id ? mine.first : null));
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(availableCoursesProvider);
    final mine = ref.watch(settingsProvider).value?.myCourseIds ?? const <String>[];
    final lang = ref.watch(sourceLangProvider);
    final theme = Theme.of(context);
    final courses = available.value ?? const <CourseMeta>[];
    final addedCount = courses.where((c) => mine.contains(c.id)).length;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        key: const ValueKey('course-picker'),
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(widget.firstRun ? 'Choose your course' : 'Courses', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Add the courses you want to learn. Removing one keeps its progress.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (available.isLoading) const Center(child: CircularProgressIndicator()),
                for (final c in courses)
                  _CourseCard(
                    meta: c,
                    added: mine.contains(c.id),
                    lastAdded: mine.contains(c.id) && addedCount <= 1,
                    expanded: _expanded.contains(c.id),
                    lang: lang,
                    onAdd: () => _add(c.id),
                    onRemove: () => _remove(c.id),
                    onPreview: () =>
                        setState(() => _expanded.contains(c.id) ? _expanded.remove(c.id) : _expanded.add(c.id)),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('course-picker-done'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Done')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends ConsumerWidget {
  const _CourseCard({
    required this.meta,
    required this.added,
    required this.lastAdded,
    required this.expanded,
    required this.lang,
    required this.onAdd,
    required this.onRemove,
    required this.onPreview,
  });

  final CourseMeta meta;
  final bool added;
  final bool lastAdded;
  final bool expanded;
  final String lang;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mono = isBw(context);
    final demo = ref.watch(courseCatalogProvider).isDemo(meta.id);
    return Card(
      key: ValueKey('course-card-${meta.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // Added: a heavier border (and the label), not only a tint.
        side: BorderSide(
          color: mono ? kBwBlack : (added ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
          width: added ? 3 : (mono ? kBwBorder : 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(pickLang(meta.title, lang), style: theme.textTheme.titleMedium),
                          if (demo) const DemoBadge(),
                          if (meta.unverified) const UnverifiedBadge(),
                        ],
                      ),
                      Text(
                        [
                          if (meta.translations.isNotEmpty) 'from ${meta.translations.map(languageName).join(', ')}',
                          'v${meta.version}',
                          if (added) 'Added',
                        ].join(' · '),
                        key: ValueKey('course-langs-${meta.id}'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (added)
                  IconButton.outlined(
                    key: ValueKey('course-remove-${meta.id}'),
                    tooltip: lastAdded ? 'Your only course' : 'Remove from my courses',
                    onPressed: lastAdded ? null : onRemove,
                    icon: const Icon(Icons.remove),
                  )
                else
                  IconButton.filled(
                    key: ValueKey('course-add-${meta.id}'),
                    tooltip: 'Add to my courses',
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('course-preview-${meta.id}'),
                onPressed: onPreview,
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(expanded ? 'Hide preview' : 'Preview'),
              ),
            ),
            if (expanded) _Preview(courseId: meta.id, lang: lang),
          ],
        ),
      ),
    );
  }
}

class _Preview extends ConsumerWidget {
  const _Preview({required this.courseId, required this.lang});
  final String courseId;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(coursePreviewProvider(courseId));
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey('course-preview-body-$courseId'),
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 10),
      child: preview.when(
        loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
        error: (e, _) => Text('Could not open this course: $e'),
        data: (p) {
          final description = pickLang(p.meta.description, lang);
          String n(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (description.isNotEmpty) ...[
                Text(description, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 6),
              ],
              Text(
                '${n(p.words)} words · ${n(p.verbs)} verbs · ${n(p.sentences)} sentences · '
                '${p.outline.length} units · ${p.outline.fold<int>(0, (a, u) => a + u.$2.length)} skills',
                key: ValueKey('course-counts-$courseId'),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                [
                  'Learn ${pickLang(p.meta.title, lang)} (${p.meta.target})',
                  if (p.meta.translations.isNotEmpty)
                    'translations in ${p.meta.translations.map(languageName).join(', ')}',
                ].join(' · '),
                key: ValueKey('course-languages-$courseId'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final (unit, skills) in p.outline)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${pickLang(unit.title, lang)}: ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: skills.map((s) => pickLang(s.title, lang)).join(', ')),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              if (p.sampleWords.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Sample words', style: theme.textTheme.labelLarge),
                Text(
                  p.sampleWords.map((i) => '${wordLabel(i)} — ${i.gloss(lang)}').join('; '),
                  key: ValueKey('course-samples-$courseId'),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (p.sampleSentence case final s?) ...[
                const SizedBox(height: 8),
                Text('Sample sentence', style: theme.textTheme.labelLarge),
                Text(s.text, style: theme.textTheme.bodyLarge),
                if (s.translation(lang) case final tr?)
                  Text(tr, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
              ],
            ],
          );
        },
      ),
    );
  }
}
