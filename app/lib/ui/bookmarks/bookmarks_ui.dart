/// Bookmarks in the UI: the providers, the star button (word popover, word
/// page, flashcard, story sentences) and the "Star" action of the feedback
/// panel, which stars the exercise, its word or its sentence. Storage and
/// merging: `data/progress/bookmarks.dart`. See docs/ui.md, "Bookmarks".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../data/progress/bookmarks.dart';
import '../../engine/engine.dart' show CourseIndex, exercisePrompt, sentenceIdOf;
import '../../feedback/exercise_snapshot.dart';
import '../../progression/stats.dart' show exerciseTypeLabel;
import '../../providers.dart';

/// Reads and writes the bookmark settings of the progress store.
final bookmarkStoreProvider = Provider<BookmarkStore>(
  (ref) => BookmarkStore(ref.watch(progressStoreProvider), clock: ref.watch(clockProvider)),
);

/// The active course's bookmarks (reloaded after every progress refresh, so
/// an imported backup shows up).
final bookmarksProvider = AsyncNotifierProvider<BookmarksController, BookmarkSet>(BookmarksController.new);

class BookmarksController extends AsyncNotifier<BookmarkSet> {
  late String _course;

  @override
  Future<BookmarkSet> build() async {
    ref.watch(progressRevisionProvider);
    _course = await ref.watch(activeCourseIdProvider.future);
    return ref.watch(bookmarkStoreProvider).load(_course);
  }

  /// Stars [b], or unstars it when it is starred.
  Future<void> toggle(Bookmark b) async {
    await future;
    state = AsyncData(await ref.read(bookmarkStoreProvider).toggle(_course, b));
  }

  Future<void> remove(BookmarkKind kind, String id) async {
    await future;
    state = AsyncData(await ref.read(bookmarkStoreProvider).remove(_course, kind, id));
  }
}

/// Whether [kind]/[id] is starred in the active course (false while loading).
final isStarredProvider = Provider.family<bool, (BookmarkKind, String)>(
  (ref, key) => ref.watch(bookmarksProvider).value?.contains(key.$1, key.$2) ?? false,
);

/// The stable id of a starred exercise: the same exercise (type, facet,
/// prompt) starred twice is one bookmark.
String exerciseBookmarkId(Exercise e) => stableHash('${e.type.id}|${e.facetId}|${exercisePrompt(e)}');

String _clip(String s, [int max = 280]) => s.length <= max ? s : '${s.substring(0, max)}…';

/// The bookmark of word [itemId] (its label with the article, its glosses).
Bookmark wordBookmark(CourseData? course, String itemId, String lang) {
  final item = course?.item(itemId);
  return Bookmark(
    kind: BookmarkKind.word,
    id: itemId,
    at: DateTime.utc(1970),
    label: item == null ? itemId : CourseIndex.of(course!).withArticle(item),
    detail: item?.glosses(lang).join(', '),
  );
}

Bookmark sentenceBookmark(Sentence s, String lang) => Bookmark(
  kind: BookmarkKind.sentence,
  id: s.id,
  at: DateTime.utc(1970),
  label: s.text,
  detail: s.translation(lang),
);

/// The bookmark of exercise [e], with its full snapshot (replayed by
/// "Practice starred").
Bookmark exerciseBookmark(Exercise e) => Bookmark(
  kind: BookmarkKind.exercise,
  id: exerciseBookmarkId(e),
  at: DateTime.utc(1970),
  label: _clip(exercisePrompt(e)),
  detail: exerciseTypeLabel(e.type),
  facetId: e.facetId,
  exercise: exerciseToJson(e),
);

/// The item an exercise's main facet belongs to.
String? itemOfFacet(String facetId) {
  final hash = facetId.lastIndexOf('#');
  return hash <= 0 ? null : facetId.substring(0, hash);
}

/// What "Practice starred" gets: the starred words, sentences and the
/// decoded exercise snapshots (ids `starred:{bookmark id}`; snapshots this
/// version can't read are skipped).
StarredPractice starredPracticeOf(BookmarkSet set) => StarredPractice(
  itemIds: [for (final b in set.of(BookmarkKind.word)) b.id],
  sentenceIds: [for (final b in set.of(BookmarkKind.sentence)) b.id],
  exercises: [
    for (final b in set.of(BookmarkKind.exercise))
      if (b.exercise != null) ?_decode(b),
  ],
);

Exercise? _decode(Bookmark b) {
  try {
    return exerciseFromJson({...b.exercise!, 'id': 'starred:${b.id}'});
  } on Object {
    return null;
  }
}

/// A star toggle for one bookmark. [make] makes the bookmark when it is starred.
class StarButton extends ConsumerWidget {
  const StarButton({super.key, required this.kind, required this.id, required this.make, this.size});

  final BookmarkKind kind;
  final String id;
  final Bookmark Function() make;
  final double? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(isStarredProvider((kind, id)));
    final what = switch (kind) {
      BookmarkKind.word => 'word',
      BookmarkKind.sentence => 'sentence',
      BookmarkKind.exercise => 'exercise',
    };
    return IconButton(
      tooltip: on ? 'Unstar this $what' : 'Star this $what',
      isSelected: on,
      iconSize: size,
      onPressed: () => ref.read(bookmarksProvider.notifier).toggle(make()),
      icon: const Icon(Icons.star_border),
      selectedIcon: const Icon(Icons.star),
    );
  }
}

/// The word star (word popover, word page, flashcard).
class WordStarButton extends ConsumerWidget {
  const WordStarButton({super.key, required this.itemId, this.size});
  final String itemId;
  final double? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) => StarButton(
    kind: BookmarkKind.word,
    id: itemId,
    size: size,
    make: () => wordBookmark(ref.read(courseDataProvider).value, itemId, ref.read(sourceLangProvider)),
  );
}

/// Whether anything [exerciseStarTargets] lists for [e] is starred.
final exerciseStarredProvider = Provider.family<bool, Exercise>((ref, e) {
  final set = ref.watch(bookmarksProvider).value;
  if (set == null) return false;
  final item = itemOfFacet(e.facetId);
  final sentence = sentenceIdOf(e);
  return set.contains(BookmarkKind.exercise, exerciseBookmarkId(e)) ||
      (item != null && set.contains(BookmarkKind.word, item)) ||
      (sentence != null && set.contains(BookmarkKind.sentence, sentence));
});

/// The feedback panel's "Star": a sheet to star the exercise, its word and its sentence.
Future<void> showStarSheet(BuildContext context, Exercise exercise) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => StarSheet(exercise: exercise),
);

class StarSheet extends ConsumerWidget {
  const StarSheet({super.key, required this.exercise});
  final Exercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final course = ref.watch(courseDataProvider).value;
    final lang = ref.watch(sourceLangProvider);
    final item = itemOfFacet(exercise.facetId);
    final word = item == null ? null : wordBookmark(course, item, lang);
    final sentenceId = sentenceIdOf(exercise);
    final sentence = sentenceId == null ? null : course?.sentence(sentenceId);
    final ex = exerciseBookmark(exercise);

    Widget row(String key, Bookmark b, IconData icon, String title, String? subtitle) {
      final on = ref.watch(isStarredProvider((b.kind, b.id)));
      return ListTile(
        key: ValueKey(key),
        leading: Icon(icon),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null ? null : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Icon(on ? Icons.star : Icons.star_border, semanticLabel: on ? 'starred' : 'not starred'),
        selected: false,
        onTap: () => ref.read(bookmarksProvider.notifier).toggle(b),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('star-sheet'),
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text('Star for later', style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Starred items are in Progress → Starred, with "Practice starred".',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                row('star-toggle-exercise', ex, Icons.quiz_outlined, 'This exercise', ex.detail),
                if (word != null)
                  row('star-toggle-word', word, Icons.translate, 'Word: ${word.label}', word.detail),
                if (sentence != null)
                  row(
                    'star-toggle-sentence',
                    sentenceBookmark(sentence, lang),
                    Icons.short_text,
                    'Sentence: ${sentence.text}',
                    sentence.translation(lang),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
