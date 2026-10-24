/// Practice → **Read**: paste a text (or open a `.txt` file) and read it with
/// every word looked up in the course; the recent texts of the course (this
/// device only, deletable with Undo) and the way to "My words". "Read" is
/// pinned at the bottom (thumb zone). See docs/ui.md, "Reading".
library;

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../my_words/my_words_screen.dart' show MyWordsTile;
import '../routes.dart';
import '../theme/tosk_palette.dart';
import 'reading_providers.dart';

/// Picks a `.txt` file and returns its text (null when cancelled). Tests
/// override it.
final readingFilePickerProvider = Provider<Future<String?> Function()>((ref) => () async {
  final f = await FilePicker.pickFile(
    dialogTitle: 'Choose a text file (.txt)',
    type: FileType.custom,
    allowedExtensions: const ['txt'],
  );
  if (f == null) return null;
  return utf8.decode(await f.readAsBytes(), allowMalformed: true);
});

class ReadingHomeView extends ConsumerStatefulWidget {
  const ReadingHomeView({super.key});

  @override
  ConsumerState<ReadingHomeView> createState() => _ReadingHomeViewState();
}

class _ReadingHomeViewState extends ConsumerState<ReadingHomeView> {
  final _input = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _snack(String text, {Key? key, SnackBarAction? action}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(key: key, content: Text(text), action: action));

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.trim().isEmpty) {
      if (mounted) _snack('Nothing to paste', key: const ValueKey('reading-paste-empty'));
      return;
    }
    _input.text = t;
  }

  Future<void> _openFile() async {
    try {
      final t = await ref.read(readingFilePickerProvider)();
      if (t != null) _input.text = t;
    } catch (e) {
      if (mounted) _snack('Could not open the file: $e', key: const ValueKey('reading-file-error'));
    }
  }

  Future<void> _read() async {
    final text = _input.text;
    if (text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final entry = await ref.read(savedTextsProvider.notifier).save(text);
      if (!mounted) return;
      if (text.length > kMaxTextChars) {
        _snack('Long text: only the first ${kMaxTextChars ~/ 1000}k characters are kept', key: const ValueKey('reading-cut'));
      }
      _input.clear();
      unawaited(context.push(Routes.reader(entry.id)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(SavedText t) async {
    unawaited(ref.read(savedTextsProvider.notifier).touch(t.id));
    unawaited(context.push(Routes.reader(t.id)));
  }

  Future<void> _delete(SavedText t) async {
    final notifier = ref.read(savedTextsProvider.notifier);
    final gone = await notifier.delete(t.id);
    if (gone == null || !mounted) return;
    _snack(
      'Deleted "${t.title}"',
      key: const ValueKey('reading-deleted'),
      action: SnackBarAction(
        key: const ValueKey('reading-undo'),
        label: 'Undo',
        onPressed: () => unawaited(notifier.restore(gone.$1, gone.$2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final course = ref.watch(courseDataProvider).value;
    final language = course == null ? 'the language you learn' : pickLang(course.meta.title, 'en');
    final texts = ref.watch(savedTextsProvider).value ?? const <SavedText>[];
    final hasText = _input.text.trim().isNotEmpty;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                key: const ValueKey('reading-home'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  Text('Read any text', style: theme.textTheme.serifTitle),
                  const SizedBox(height: 4),
                  Text(
                    'Paste a text in $language: a news article, a song, a chapter. Tap any word for its meaning; '
                    'words you haven\'t learned yet are underlined.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('reading-input'),
                    controller: _input,
                    minLines: 5,
                    maxLines: 10,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: 'Paste or type a text in $language',
                      border: const OutlineInputBorder(),
                      suffixIcon: hasText
                          ? IconButton(
                              key: const ValueKey('reading-clear'),
                              tooltip: 'Clear',
                              icon: const Icon(Icons.clear),
                              onPressed: _input.clear,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('reading-paste'),
                        onPressed: () => unawaited(_paste()),
                        icon: const Icon(Icons.content_paste),
                        label: const Text('Paste'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('reading-open-file'),
                        onPressed: () => unawaited(_openFile()),
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('Open a .txt file'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (texts.isNotEmpty) ...[
                    Text('Recent texts', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('Kept on this device only.', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    for (final t in texts) ...[
                      Card(
                        key: ValueKey('reading-saved-${t.id}'),
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.article_outlined),
                          title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${t.words} word${t.words == 1 ? '' : 's'} · ${_date(t.at)}'),
                          onTap: () => unawaited(_open(t)),
                          trailing: IconButton(
                            key: ValueKey('reading-delete-${t.id}'),
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => unawaited(_delete(t)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                  ],
                  const MyWordsTile(card: true),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('reading-read'),
                    onPressed: hasText && !_busy ? () => unawaited(_read()) : null,
                    icon: const Icon(Icons.menu_book),
                    label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Read')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _date(DateTime at) {
    final l = at.toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${l.day} ${months[l.month - 1]}';
  }
}
