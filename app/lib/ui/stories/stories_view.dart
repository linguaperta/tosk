/// The stories list (Practice → Stories) and a unit's stories (the book
/// button in a map unit band opens [UnitStoriesSheet]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../common/async_view.dart';
import '../routes.dart';
import '../theme/bw_skin.dart';
import 'story_providers.dart';

/// Every story of the active course, grouped by unit.
class StoriesView extends ConsumerWidget {
  const StoriesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseDataProvider);
    final lang = ref.watch(sourceLangProvider);
    return AsyncView(
      value: course,
      builder: (c) {
        if (c.stories.isEmpty) {
          return const _Empty(text: 'This course has no stories yet.');
        }
        final children = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              'Short stories with the words and grammar of each unit. '
              'Tap a word for its translation, then answer a few questions.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ];
        for (final u in c.units) {
          final stories = [for (final s in c.stories) if (s.unitId == u.id) s];
          if (stories.isEmpty) continue;
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text(pickLang(u.title, lang), style: Theme.of(context).textTheme.titleSmall),
            ),
          );
          for (final s in stories) {
            children.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: StoryTile(story: s)));
          }
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              key: const ValueKey('stories-list'),
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.paddingOf(context).bottom),
              children: children,
            ),
          ),
        );
      },
    );
  }
}

/// A unit's stories, as a bottom sheet over the map.
class UnitStoriesSheet extends ConsumerWidget {
  const UnitStoriesSheet({super.key, required this.unitId});
  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseDataProvider).value;
    final lang = ref.watch(sourceLangProvider);
    final unlocked = ref.watch(storyUnitsUnlockedProvider).value?.contains(unitId) ?? false;
    final unit = course?.units.where((u) => u.id == unitId).firstOrNull;
    final stories = [for (final s in course?.stories ?? const <Story>[]) if (s.unitId == unitId) s];
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ListView(
        key: const ValueKey('unit-stories-sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text('Stories', style: theme.textTheme.titleLarge),
          if (unit != null) Text(pickLang(unit.title, lang), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          if (!unlocked)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'These open once you have started every skill of this unit. You can read them anyway.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          for (final s in stories) Padding(padding: const EdgeInsets.only(bottom: 8), child: StoryTile(story: s)),
          if (stories.isEmpty) const _Empty(text: 'No stories in this unit.'),
        ],
      ),
    );
  }
}

/// One story: title, translated title, and its state (new, read with the best
/// score, or locked), told by icon and words, never by color alone.
class StoryTile extends ConsumerWidget {
  const StoryTile({super.key, required this.story});
  final Story story;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = isMonochrome(scheme);
    final lang = ref.watch(sourceLangProvider);
    final record = ref.watch(storyRecordsProvider).value?[story.id];
    final unlocked = ref.watch(storyUnitsUnlockedProvider).value?.contains(story.unitId) ?? false;
    final (IconData icon, String status) = switch ((record, unlocked)) {
      (final r?, _) => (Icons.check_circle_outline, r.total > 0 ? 'Read · best ${r.bestCorrect}/${r.total}' : 'Read'),
      (null, true) => (Icons.menu_book, 'New'),
      (null, false) => (Icons.lock_outline, 'Locked · preview'),
    };
    final muted = !unlocked && record == null;
    final fg = muted ? (mono ? kBwGray : scheme.onSurfaceVariant) : scheme.onSurface;
    return Semantics(
      button: true,
      label: '${story.title}, ${pickLang(story.titleTr, lang)}, $status',
      excludeSemantics: true,
      child: Card(
        key: ValueKey('story-tile-${story.id}'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(Routes.story(story.id)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, color: fg, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(story.title, style: theme.textTheme.titleMedium?.copyWith(color: fg)),
                        Text(pickLang(story.titleTr, lang), style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
                        Text(status, style: theme.textTheme.labelMedium?.copyWith(color: fg)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
    ),
  );
}
