import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../theme/bw_skin.dart';

/// What "Unverified" means (the badge's tap and tooltip).
const kUnverifiedExplanation =
    'No native speaker has checked this course yet. It is built from open dictionaries and example '
    'sentences, partly written with AI, so a sentence may sometimes sound unnatural or even be wrong.';

/// Shows [kUnverifiedExplanation] with what to do about a doubtful exercise.
Future<void> showUnverifiedInfo(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    key: const ValueKey('unverified-info'),
    icon: const Icon(Icons.warning_amber_rounded),
    title: const Text('Unverified course'),
    content: const Text(
      '$kUnverifiedExplanation\n\nMost exercises are fine. If one looks wrong, tap the flag button '
      'after checking your answer: flagged exercises are how the course gets corrected.',
    ),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it'))],
  ),
);

/// Small chip warning that a course hasn't been checked by a speaker; a tap
/// explains what that means.
class UnverifiedBadge extends StatelessWidget {
  const UnverifiedBadge({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: kUnverifiedExplanation,
      child: Semantics(
        button: true,
        label: 'Unverified course. What does this mean?',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showUnverifiedInfo(context),
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

/// Small dot: a course (or one of my courses) has an update. Shown in
/// Settings (the course rows and "Add or remove courses"). A shape (filled
/// black in black & white), with a tooltip and semantics.
class UpdateDot extends StatelessWidget {
  const UpdateDot({super.key, this.dotKey = const ValueKey('course-update-dot')});

  /// Key of the dot itself (one per course row in Settings).
  final Key dotKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Course updates available',
      child: Semantics(
        label: 'Course updates available',
        child: Container(
          key: dotKey,
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isMonochrome(scheme) ? kBwBlack : scheme.primary,
          ),
        ),
      ),
    );
  }
}

/// The active course's title on the map (with the Demo / Unverified
/// badges). Not interactive: courses are switched, added and removed in
/// Settings (the course section and "Add or remove courses").
class CourseTitle extends ConsumerWidget {
  const CourseTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(myCoursesProvider).value ?? const <CourseMeta>[];
    final activeId = ref.watch(activeCourseIdProvider).value;
    final lang = ref.watch(sourceLangProvider);
    final active = courses.where((c) => c.id == activeId).firstOrNull;
    final title = active == null ? 'tosk' : pickLang(active.title, lang);
    final demo = ref.watch(activeCourseIsDemoProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(title, key: const ValueKey('course-title'), overflow: TextOverflow.ellipsis),
        ),
        if (demo) ...[const SizedBox(width: 8), const DemoBadge()],
        // Icon-only next to the demo chip, so both fit on phones.
        if (active?.unverified ?? false) ...[const SizedBox(width: 8), UnverifiedBadge(compact: demo)],
      ],
    );
  }
}
