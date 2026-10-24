/// `/my-words`: the learner's own words of the active course: add (+), edit
/// (tap a word), delete (with Undo), each word's status in words, and
/// "Practice my words" pinned at the bottom (`/play/my-words`). The add/edit
/// sheet ([showMyWordSheet]) is shared with the reader's "Add to my words".
/// See docs/ui.md, "My words".
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../brand/tosk.dart';
import '../common/async_view.dart';
import '../routes.dart';
import '../settings/app_settings.dart' show languageName;
import '../theme/bw_skin.dart';
import '../theme/tosk_palette.dart';
import 'my_words_providers.dart';

class MyWordsScreen extends ConsumerWidget {
  const MyWordsScreen({super.key});

  void _delete(BuildContext context, WidgetRef ref, UserWord w) {
    final notifier = ref.read(userWordsProvider.notifier);
    unawaited(notifier.remove(w.id));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('my-word-deleted'),
          content: Text('Deleted "${w.word}"', maxLines: 2, overflow: TextOverflow.ellipsis),
          action: SnackBarAction(
            key: const ValueKey('my-word-undo'),
            label: 'Undo',
            onPressed: () => unawaited(notifier.restore(w)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(userWordsProvider);
    final live = words.value?.live ?? const <UserWord>[];
    final status = ref.watch(myWordStatusProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.practice)),
        title: const Text('My words'),
        actions: [
          IconButton(
            key: const ValueKey('my-words-add'),
            tooltip: 'Add a word',
            icon: const Icon(Icons.add),
            onPressed: () => unawaited(showMyWordSheet(context, ref)),
          ),
        ],
      ),
      body: AsyncView(
        value: words,
        onRetry: () => ref.invalidate(userWordsProvider),
        builder: (set) => set.isEmpty
            ? _Empty(onAdd: () => unawaited(showMyWordSheet(context, ref)))
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    key: const ValueKey('my-words-list'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Text(
                        _counts(live, status),
                        key: const ValueKey('my-words-counts'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      for (final w in live) ...[
                        _WordCard(
                          word: w,
                          status: status[w.id],
                          onEdit: () => unawaited(showMyWordSheet(context, ref, existing: w)),
                          onDelete: () => _delete(context, ref, w),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
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
                      key: const ValueKey('my-words-practice'),
                      onPressed: () => context.push(Routes.myWordsPlay),
                      icon: const Icon(Icons.play_arrow),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Practice my words (${live.length})'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  static String _counts(List<UserWord> live, Map<String, MyWordStatus> status) {
    final n = live.length;
    final due = status.values.where((s) => s == MyWordStatus.due).length;
    final fresh = status.values.where((s) => s == MyWordStatus.fresh).length;
    return [
      '$n word${n == 1 ? '' : 's'}',
      if (fresh > 0) '$fresh new',
      if (due > 0) '$due due',
    ].join(' · ');
  }
}

class _WordCard extends StatelessWidget {
  const _WordCard({required this.word, required this.status, required this.onEdit, required this.onDelete});
  final UserWord word;
  final MyWordStatus? status;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extra = [?word.note, ?word.example];
    return Card(
      key: ValueKey('my-word-${word.id}'),
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onEdit,
        title: Text(word.word, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(word.translation),
            if (extra.isNotEmpty)
              Text(extra.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
            if (status case final s?)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  myWordStatusLabel(s),
                  key: ValueKey('my-word-status-${word.id}'),
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        trailing: IconButton(
          key: ValueKey('my-word-delete-${word.id}'),
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const ValueKey('my-words-empty'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const ToskImage(pose: ToskPose.thinking, height: 112),
            const SizedBox(height: 12),
            Text('No words of your own yet', style: theme.textTheme.serifTitle, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const Text(
                'Add words you meet while reading (tap a word, then "Add to my words") or type them here. '
                'They get their own practice, and once you know them they come back in lessons now and then.',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const ValueKey('my-words-add-empty'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add a word'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings → Practice and the reader: "My words (N)", opening `/my-words`.
class MyWordsTile extends ConsumerWidget {
  const MyWordsTile({super.key, this.card = false});

  /// A card (the Read tab) instead of a plain list tile (Settings).
  final bool card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(myWordsCountProvider);
    final tile = ListTile(
      key: const ValueKey('open-my-words'),
      leading: const Icon(Icons.bookmark_add_outlined),
      title: Text(n == 0 ? 'My words' : 'My words ($n)'),
      subtitle: Text(n == 0 ? 'Add your own words and practise them' : 'Your own words: edit, add, practise'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.myWords),
    );
    return card ? Card(margin: EdgeInsets.zero, child: tile) : tile;
  }
}

/// The add / edit sheet. Returns the saved word (null when cancelled).
Future<UserWord?> showMyWordSheet(BuildContext context, WidgetRef ref, {UserWord? existing, MyWordDraft? draft}) async {
  final course = ref.read(courseDataProvider).value;
  final lang = ref.read(sourceLangProvider);
  return showModalBottomSheet<UserWord>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => _MyWordSheet(
      existing: existing,
      draft: draft,
      targetName: course == null ? 'the language' : pickLang(course.meta.title, 'en'),
      sourceName: languageName(lang),
    ),
  );
}


class _MyWordSheet extends ConsumerStatefulWidget {
  const _MyWordSheet({this.existing, this.draft, required this.targetName, required this.sourceName});
  final UserWord? existing;
  final MyWordDraft? draft;
  final String targetName;
  final String sourceName;

  @override
  ConsumerState<_MyWordSheet> createState() => _MyWordSheetState();
}

class _MyWordSheetState extends ConsumerState<_MyWordSheet> {
  late final _word = TextEditingController(text: widget.existing?.word ?? widget.draft?.word ?? '');
  late final _tr = TextEditingController(text: widget.existing?.translation ?? widget.draft?.translation ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? widget.draft?.note ?? '');
  late final _example = TextEditingController(text: widget.existing?.example ?? widget.draft?.example ?? '');
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_word, _tr, _note, _example]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid => _word.text.trim().isNotEmpty && _tr.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final notifier = ref.read(userWordsProvider.notifier);
    UserWord saved;
    final old = widget.existing;
    if (old != null) {
      saved = UserWord(
        id: old.id,
        word: _word.text.trim(),
        translation: _tr.text.trim(),
        note: _note.text.trim(),
        example: _example.text.trim(),
        lemmaId: old.lemmaId,
        pos: old.pos,
        lang: old.lang,
        created: old.created,
        at: old.at,
      );
      await notifier.edit(saved);
    } else {
      final d = widget.draft;
      saved = await notifier.add(MyWordDraft(
        word: _word.text,
        translation: _tr.text,
        note: _note.text,
        example: _example.text,
        lemmaId: d?.lemmaId,
        pos: d?.pos,
      ));
    }
    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.existing != null;
    InputDecoration deco(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): () => unawaited(_save())},
              child: Column(
                key: const ValueKey('my-word-sheet'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(editing ? 'Edit word' : 'Add to my words', style: theme.textTheme.serifTitle),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('my-word-word'),
                    controller: _word,
                    autofocus: !editing && (widget.draft?.word.isEmpty ?? true),
                    textInputAction: TextInputAction.next,
                    decoration: deco('Word or phrase (${widget.targetName})'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('my-word-translation'),
                    controller: _tr,
                    autofocus: !editing && (widget.draft?.word.isNotEmpty ?? false) && (widget.draft?.translation.isEmpty ?? false),
                    textInputAction: TextInputAction.next,
                    decoration: deco('Meaning (${widget.sourceName})', hint: 'Several? Separate them with commas'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('my-word-note'),
                    controller: _note,
                    textInputAction: TextInputAction.next,
                    decoration: deco('Note (optional)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('my-word-example'),
                    controller: _example,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => unawaited(_save()),
                    decoration: deco('Example (optional)'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey('my-word-cancel'),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('my-word-save'),
                          onPressed: _valid && !_saving ? () => unawaited(_save()) : null,
                          child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Save')),
                        ),
                      ),
                    ],
                  ),
                  if (!_valid)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'A word and its meaning are needed.',
                        key: const ValueKey('my-word-needs'),
                        style: theme.textTheme.bodySmall?.copyWith(color: isBw(context) ? kBwBlack : null),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
