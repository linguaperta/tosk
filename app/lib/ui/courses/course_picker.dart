/// The course picker: every available course (bundled and installed packs,
/// a local Sarnami pack included) with + / − to add it to or remove it from
/// "my courses", and a preview. The rest of the app only shows added courses.
///
/// With downloads ([remotePacksProvider]) it also lists the online courses
/// that aren't installed ("Download (12 MB)"), marks installed courses with a
/// newer online version ("Update available"), shows progress with cancel and
/// polite errors, and checks for updates on request (button or pull down).
/// "Add course from file…" installs a pack file (e.g. the local Sarnami
/// pack), or replaces an installed one with a newer file; progress is kept.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/tosk_palette.dart';
import '../brand/tosk.dart';
import '../../core/core.dart';
import '../../providers.dart';
import '../reference/reference_screen.dart' show wordLabel;
import '../routes.dart';
import '../settings/app_settings.dart';
import '../shell/course_switcher.dart' show DemoBadge, UnverifiedBadge;
import '../theme/bw_skin.dart';
import 'course_updates.dart';

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

  /// Result of the last "Add course from file…" (shown at the top of the list).
  String? _notice;
  bool _noticeIsError = false;
  bool _installing = false;

  Future<void> _download(String id, {required bool isNew}) async {
    final info = await ref.read(courseUpdatesProvider.notifier).download(id);
    // A new course the user asked for: add it to my courses right away.
    if (info != null && isNew && mounted) {
      await ref.read(availableCoursesProvider.future);
      if (mounted) await _add(id);
    }
  }

  Future<void> _addFromFile() async {
    final install = ref.read(packInstallerProvider);
    if (install == null || _installing) return;
    final PackData? data;
    try {
      data = await ref.read(packFilePickerProvider)();
    } on Object catch (e) {
      _setNotice("Couldn't open the file picker: $e", error: true);
      return;
    }
    if (data == null) return;
    setState(() => _installing = true);
    String? addId;
    try {
      final before = {for (final c in await ref.read(availableCoursesProvider.future)) c.id: c};
      final info = await install(data);
      ref.read(courseUpdatesProvider.notifier).refreshCourses(info.id);
      await ref.read(availableCoursesProvider.future);
      final title = pickLang(info.title, ref.read(sourceLangProvider));
      final old = before[info.id];
      if (old != null && !ref.read(courseCatalogProvider).isDemo(info.id)) {
        _setNotice('Updated $title from v${old.version} to v${info.version}. Your progress is kept.');
      } else {
        _setNotice('Added $title v${info.version}.');
      }
      final mine = (await ref.read(settingsProvider.future)).myCourseIds;
      if (!mine.contains(info.id)) addId = info.id;
    } on Object catch (e) {
      final msg = '$e'.replaceFirst(RegExp(r'^[A-Za-z]*Exception: '), '');
      _setNotice("This file couldn't be added as a course: $msg", error: true);
    } finally {
      if (mounted) setState(() => _installing = false);
    }
    // A new course: add it to my courses right away.
    if (addId != null && mounted) await _add(addId);
  }

  void _setNotice(String? text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _notice = text;
      _noticeIsError = error;
    });
  }

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
    final online = ref.watch(remotePacksProvider) != null;
    final updates = ref.watch(courseUpdatesProvider);
    final offers = ref.watch(courseOffersProvider);
    final ctl = ref.read(courseUpdatesProvider.notifier);
    final listed = {for (final c in courses) c.id};
    final canAddFile = ref.watch(packInstallerProvider) != null;

    _DownloadControls controls(String id, CourseOffer? offer, {required bool isNew}) => _DownloadControls(
      id: id,
      offer: offer,
      download: updates.downloads[id],
      onDownload: () => _download(id, isNew: isNew),
      onCancel: () => ctl.cancel(id),
      onDismiss: () => ctl.dismissError(id),
    );

    Widget list(ScrollController controller) => ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.firstRun ? 'Choose your course' : 'Courses', style: theme.textTheme.serifTitle),
                  const SizedBox(height: 4),
                  Text('Add the courses you want to learn. Removing one keeps its progress.', style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Tosk greets the learner.
            const ToskImage(pose: ToskPose.standing, height: 80),
          ],
        ),
        if (online) _UpdatesBar(state: updates, onCheck: () => ctl.check()),
        if (_notice case final notice?)
          _Notice(text: notice, error: _noticeIsError, onClose: () => _setNotice(null)),
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
            onPreview: () => setState(() => _expanded.contains(c.id) ? _expanded.remove(c.id) : _expanded.add(c.id)),
            updateAvailable: offers[c.id]?.status == OfferStatus.updateAvailable,
            controls: online
                ? controls(
                    c.id,
                    offers[c.id],
                    // A demo course replaced by the real one counts as new; an update doesn't.
                    isNew: offers[c.id]?.status == OfferStatus.downloadable && !mine.contains(c.id),
                  )
                : null,
          ),
        for (final o in offers.values)
          if (!listed.contains(o.id) && o.remote != null)
            _OnlineCourseCard(pack: o.remote!, lang: lang, controls: controls(o.id, o, isNew: true)),
        if (canAddFile) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('course-add-file'),
              onPressed: _installing ? null : _addFromFile,
              icon: _installing
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_open_outlined),
              label: const Text('Add course from file…'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'A course pack (.sqlite) you built or were given. A newer file replaces the installed '
              'version of that course; your progress is kept.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        key: const ValueKey('course-picker'),
        children: [
          Expanded(
            child: online ? RefreshIndicator(onRefresh: () => ctl.check(), child: list(controller)) : list(controller),
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

/// "Check for updates" with the result of the last check.
class _UpdatesBar extends StatelessWidget {
  const _UpdatesBar({required this.state, required this.onCheck});
  final CourseUpdatesState state;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checked = state.checkedAt;
    final String status;
    if (state.checking) {
      status = 'Checking for course updates…';
    } else if (state.error case final e?) {
      status = e;
    } else if (checked != null) {
      final l = checked.toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      status = 'Last checked ${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
    } else {
      status = 'Pull down or tap to see new courses and updates.';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            key: const ValueKey('course-check-updates'),
            onPressed: state.checking ? null : onCheck,
            icon: state.checking
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: const Text('Check for updates'),
          ),
          Text(
            status,
            key: const ValueKey('course-update-status'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: state.error != null ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// A message in the sheet (file added, or why not); outlined, so it reads in black & white.
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.error, required this.onClose});
  final String text;
  final bool error;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = isBw(context);
    return Container(
      key: const ValueKey('course-notice'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: mono ? kBwBlack : (error ? theme.colorScheme.error : theme.colorScheme.outline),
          width: mono ? kBwBorder : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          IconButton(tooltip: 'Dismiss', onPressed: onClose, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

/// Chip on a course with a newer version online.
class UpdateBadge extends StatelessWidget {
  const UpdateBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('update-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: isMonochrome(scheme) ? Border.all(color: kBwBlack, width: 1.5) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.upgrade, size: 14, color: scheme.onPrimaryContainer),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Update available',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Download / update button, progress with cancel, or the last error with retry.
class _DownloadControls extends StatelessWidget {
  const _DownloadControls({
    required this.id,
    required this.offer,
    required this.download,
    required this.onDownload,
    required this.onCancel,
    required this.onDismiss,
  });

  final String id;
  final CourseOffer? offer;
  final CourseDownload? download;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = download;
    final o = offer;
    if (d != null && d.running) {
      final pct = d.fraction == null ? '' : '${(d.fraction! * 100).floor()}%';
      return Padding(
        key: ValueKey('course-progress-$id'),
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: d.fraction, minHeight: 6),
                  const SizedBox(height: 4),
                  Text(
                    'Downloading… $pct (${formatMegabytes(d.received)} of ${formatMegabytes(d.total)})',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('course-cancel-$id'),
              tooltip: 'Cancel download',
              onPressed: onCancel,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      );
    }
    if (d?.error case final error?) {
      return Padding(
        key: ValueKey('course-error-$id'),
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(error, style: theme.textTheme.bodyMedium)),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(key: ValueKey('course-retry-$id'), onPressed: onDownload, child: const Text('Try again')),
                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
              ],
            ),
          ],
        ),
      );
    }
    if (o == null || o.remote == null) return const SizedBox.shrink();
    final r = o.remote!;
    if (o.status == OfferStatus.needsAppUpdate) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Version ${r.version} needs a newer version of the app.',
          key: ValueKey('course-needs-app-$id'),
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    if (!o.canDownload) return const SizedBox.shrink();
    final update = o.status == OfferStatus.updateAvailable;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          key: ValueKey('course-download-$id'),
          onPressed: onDownload,
          icon: Icon(update ? Icons.upgrade : Icons.download),
          label: Text(
            update ? 'Update to v${r.version} (${formatMegabytes(r.downloadSize(web: kIsWeb))})' : 'Download (${formatMegabytes(r.downloadSize(web: kIsWeb))})',
          ),
        ),
      ),
    );
  }
}

/// A course that is only online (not installed yet).
class _OnlineCourseCard extends StatelessWidget {
  const _OnlineCourseCard({required this.pack, required this.lang, required this.controls});
  final RemotePack pack;
  final String lang;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = isBw(context);
    final description = pickLang(pack.description, lang);
    final title = pickLang(pack.title, lang);
    return Card(
      key: ValueKey('course-online-${pack.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: mono ? kBwBlack : theme.colorScheme.outlineVariant,
          width: mono ? kBwBorder : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(title.isEmpty ? pack.id : title, style: theme.textTheme.titleMedium),
                if (pack.unverified) const UnverifiedBadge(),
              ],
            ),
            Text(
              [
                if (pack.sources.isNotEmpty) 'from ${pack.sources.map(languageName).join(', ')}',
                'v${pack.version}',
                'online',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(description, style: theme.textTheme.bodyMedium),
            ],
            controls,
          ],
        ),
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
    this.updateAvailable = false,
    this.controls,
  });

  final CourseMeta meta;
  final bool added;
  final bool lastAdded;
  final bool expanded;
  final String lang;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onPreview;
  final bool updateAvailable;

  /// Download / update / progress (with downloads on).
  final Widget? controls;

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
                          if (updateAvailable) const UpdateBadge(),
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
            ?controls,
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
