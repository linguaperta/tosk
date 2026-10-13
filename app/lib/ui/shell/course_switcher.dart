import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../theme/bw_skin.dart';

/// Small chip warning that a course hasn't been checked by a speaker.
class UnverifiedBadge extends StatelessWidget {
  const UnverifiedBadge({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'This course has not been checked by a native speaker yet.',
      child: Container(
        key: const ValueKey('unverified-badge'),
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 2),
        // Black & white: outlined text (errorContainer is white there).
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
          border: isMonochrome(scheme) ? Border.all(color: kBwBlack, width: 1.5) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: scheme.onErrorContainer),
            if (!compact) ...[
              const SizedBox(width: 4),
              Text(
                'Unverified',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chip marking built-in sample content, shown while no course pack is installed.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Sample content: no course packs are installed yet.',
      child: Container(
        key: const ValueKey('demo-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
          border: isMonochrome(scheme) ? Border.all(color: kBwBlack, width: 1.5) : null,
        ),
        child: Text('Demo', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onTertiaryContainer)),
      ),
    );
  }
}

/// Course title with a menu to switch between installed courses.
class CourseSwitcher extends ConsumerWidget {
  const CourseSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(availableCoursesProvider).value ?? const <CourseMeta>[];
    final activeId = ref.watch(activeCourseIdProvider).value;
    final lang = ref.watch(sourceLangProvider);
    final active = courses.where((c) => c.id == activeId).firstOrNull;
    final title = active == null ? 'tosk' : pickLang(active.title, lang);
    final demo = ref.watch(activeCourseIsDemoProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: PopupMenuButton<String>(
            key: const ValueKey('course-switcher'),
            tooltip: 'Switch course',
            enabled: courses.length > 1,
            onSelected: (id) => ref.read(settingsProvider.notifier).change((s) => s.copyWith(courseId: id)),
            itemBuilder: (context) => [
              for (final c in courses)
                CheckedPopupMenuItem<String>(
                  value: c.id,
                  checked: c.id == activeId,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(pickLang(c.title, lang), overflow: TextOverflow.ellipsis)),
                      if (c.unverified) ...[const SizedBox(width: 8), const UnverifiedBadge(compact: true)],
                    ],
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
                  if (courses.length > 1) const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ),
        if (demo) ...[const SizedBox(width: 8), const DemoBadge()],
        // Icon-only next to the demo chip, so both fit on phones.
        if (active?.unverified ?? false) ...[const SizedBox(width: 8), UnverifiedBadge(compact: demo)],
      ],
    );
  }
}
