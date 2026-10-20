/// `/progress/starred`: the active course's starred words, sentences and
/// exercises, filterable by kind, each with an unstar button (and Undo), and
/// "Practice starred" pinned at the bottom (`/play/starred`). See docs/ui.md,
/// "Bookmarks".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../brand/tosk.dart';
import '../common/async_view.dart';
import '../routes.dart';
import '../theme/tosk_palette.dart';
import 'bookmarks_ui.dart';

/// The longest "Practice starred" session.
const int kStarredSessionLength = 12;

class StarredScreen extends ConsumerStatefulWidget {
  const StarredScreen({super.key});

  @override
  ConsumerState<StarredScreen> createState() => _StarredScreenState();
}

class _StarredScreenState extends ConsumerState<StarredScreen> {
  /// Null: every kind.
  BookmarkKind? _filter;

  void _unstar(Bookmark b) {
    final notifier = ref.read(bookmarksProvider.notifier);
    notifier.remove(b.kind, b.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('starred-unstarred'),
          content: Text('Unstarred "${b.label}"', maxLines: 2, overflow: TextOverflow.ellipsis),
          action: SnackBarAction(key: const ValueKey('starred-undo'), label: 'Undo', onPressed: () => notifier.add(b)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final marks = ref.watch(bookmarksProvider);
    final live = marks.value?.live ?? const <Bookmark>[];
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.progress)),
        title: const Text('Starred'),
      ),
      body: AsyncView(
        value: marks,
        onRetry: () => ref.invalidate(bookmarksProvider),
        builder: (set) => set.isEmpty ? const _Empty() : _list(context, set),
      ),
      bottomNavigationBar: live.isEmpty
          ? null
          : SafeArea(
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton.icon(
                      key: const ValueKey('starred-practice'),
                      onPressed: () => context.push(Routes.starredPlay),
                      icon: const Icon(Icons.play_arrow),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Practice starred (${live.length})'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _list(BuildContext context, BookmarkSet set) {
    final theme = Theme.of(context);
    final shown = _filter == null ? set.live : set.of(_filter!);
    int count(BookmarkKind k) => set.of(k).length;
    String plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          key: const ValueKey('starred-list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              '${plural(count(BookmarkKind.word), 'word')} · ${plural(count(BookmarkKind.sentence), 'sentence')} · '
              '${plural(count(BookmarkKind.exercise), 'exercise')}',
              key: const ValueKey('starred-counts'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (key, label, kind) in [
                  ('all', 'All', null),
                  ('word', 'Words', BookmarkKind.word),
                  ('sentence', 'Sentences', BookmarkKind.sentence),
                  ('exercise', 'Exercises', BookmarkKind.exercise),
                ])
                  ChoiceChip(
                    key: ValueKey('starred-filter-$key'),
                    label: Text(label),
                    selected: _filter == kind,
                    onSelected: (_) => setState(() => _filter = kind),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Nothing starred of this kind.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            for (final b in shown) ...[
              _BookmarkCard(bookmark: b, onUnstar: () => _unstar(b)),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  const _BookmarkCard({required this.bookmark, required this.onUnstar});
  final Bookmark bookmark;
  final VoidCallback onUnstar;

  @override
  Widget build(BuildContext context) {
    final b = bookmark;
    final (icon, kind) = switch (b.kind) {
      BookmarkKind.word => (Icons.translate, 'Word'),
      BookmarkKind.sentence => (Icons.short_text, 'Sentence'),
      BookmarkKind.exercise => (Icons.quiz_outlined, 'Exercise'),
    };
    final detail = b.kind == BookmarkKind.exercise
        ? (b.detail ?? kind)
        : [kind, if (b.detail case final d? when d.isNotEmpty) d].join(' · ');
    return Card(
      key: ValueKey('starred-${b.key}'),
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, semanticLabel: kind),
        title: Text(b.label.isEmpty ? b.id : b.label, maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: b.kind == BookmarkKind.word ? () => context.push(Routes.word(b.id)) : null,
        trailing: IconButton(
          key: ValueKey('unstar-${b.key}'),
          tooltip: 'Unstar',
          icon: const Icon(Icons.star),
          onPressed: onUnstar,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const ValueKey('starred-empty'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const ToskImage(pose: ToskPose.thinking, height: 112),
            const SizedBox(height: 12),
            Text('Nothing starred yet', style: theme.textTheme.serifTitle, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const Text(
                'Tap ☆ on a word, or "Star" after checking an exercise, to keep it here and practice it later.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Progress page's entry: "Starred (N)" with the counts per kind.
class StarredEntry extends ConsumerWidget {
  const StarredEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final set = ref.watch(bookmarksProvider).value;
    final n = set?.length ?? 0;
    String plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        key: const ValueKey('open-starred'),
        leading: Icon(n == 0 ? Icons.star_border : Icons.star),
        title: Text(n == 0 ? 'Starred' : 'Starred ($n)'),
        subtitle: Text(
          set == null || n == 0
              ? 'Star words, sentences and exercises to practice them later'
              : '${plural(set.of(BookmarkKind.word).length, 'word')} · '
                    '${plural(set.of(BookmarkKind.sentence).length, 'sentence')} · '
                    '${plural(set.of(BookmarkKind.exercise).length, 'exercise')}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(Routes.starred),
      ),
    );
  }
}
