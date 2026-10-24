/// The reader's data: the recent texts of each course (kept on this device
/// only), the words the learner knows, and a text looked up for reading.
///
/// **Saved texts** live in the progress database's settings under `reading.`
/// keys: `reading.texts.{course}` lists them (newest first, at most
/// [kMaxSavedTexts]) and `reading.text.{course}.{id}` holds each text. They are
/// never synced (not in the synced-settings list) and never in the backup
/// (`reading.` is a local-only prefix, `data/sync/progress_backup.dart`):
/// what a learner pastes may be private, can be long, and they still have it.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../engine/engine.dart' show ReadingText;
import '../../providers.dart';

/// How many recent texts a course keeps.
const int kMaxSavedTexts = 20;

/// The longest text kept (characters); longer ones are cut.
const int kMaxTextChars = 200000;

/// A saved text's entry in the list.
class SavedText {
  const SavedText({required this.id, required this.title, required this.at, required this.chars, this.words = 0});
  final String id;

  /// From the first line.
  final String title;

  /// Last opened or saved.
  final DateTime at;
  final int chars;

  /// Words (runs of non-space characters).
  final int words;

  SavedText touched(DateTime at) => SavedText(id: id, title: title, at: at, chars: chars, words: words);

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'at': at.toUtc().millisecondsSinceEpoch,
    'chars': chars,
    'words': words,
  };

  static SavedText? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], title = j['title'], at = j['at'], chars = j['chars'], words = j['words'];
    if (id is! String || title is! String || at is! num) return null;
    return SavedText(
      id: id,
      title: title,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt(), isUtc: true),
      chars: chars is num ? chars.toInt() : 0,
      words: words is num ? words.toInt() : 0,
    );
  }
}

/// The title of [text]: its first non-empty line, cut at a word near 60 characters.
String savedTextTitle(String text) {
  final line = text.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (line.isEmpty) return 'Untitled text';
  if (line.length <= 60) return line;
  var cut = line.lastIndexOf(' ', 60);
  if (cut < 30) cut = 60;
  return '${line.substring(0, cut).trimRight()}…';
}

/// The recent texts of a course, in [ProgressStore] settings (see the library comment).
class SavedTextStore {
  SavedTextStore(this.store, {DateTime Function()? clock, Random? random})
    : clock = clock ?? DateTime.now,
      _random = random ?? Random();

  final ProgressStore store;
  final DateTime Function() clock;
  final Random _random;

  static String listKey(String course) => 'reading.texts.$course';
  static String textKey(String course, String id) => 'reading.text.$course.$id';

  Future<List<SavedText>> list(String course) async {
    final raw = await store.getSetting(listKey(course));
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [for (final j in jsonDecode(raw) as List) ?SavedText.fromJson(j)];
    } on Object {
      return const [];
    }
  }

  Future<void> _write(String course, List<SavedText> texts) =>
      store.setSetting(listKey(course), jsonEncode([for (final t in texts) t.toJson()]));

  Future<String?> text(String course, String id) => store.getSetting(textKey(course, id));

  /// Saves [text] (cut to [kMaxTextChars]) as the newest; the same text saved
  /// again moves to the top. Returns its entry.
  Future<SavedText> save(String course, String text) async {
    final body = text.length > kMaxTextChars ? text.substring(0, kMaxTextChars) : text;
    final now = clock().toUtc();
    final texts = [...await list(course)];
    for (final t in texts) {
      if (t.chars == body.length && await this.text(course, t.id) == body) {
        final moved = t.touched(now);
        await _write(course, [moved, ...texts.where((x) => x.id != t.id)]);
        return moved;
      }
    }
    final id = '${now.millisecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 20).toRadixString(36)}';
    final entry = SavedText(
      id: id,
      title: savedTextTitle(body),
      at: now,
      chars: body.length,
      words: RegExp(r'\S+').allMatches(body).length,
    );
    await store.setSetting(textKey(course, id), body);
    final kept = [entry, ...texts];
    for (final old in kept.skip(kMaxSavedTexts)) {
      await store.setSetting(textKey(course, old.id), null);
    }
    await _write(course, kept.take(kMaxSavedTexts).toList());
    return entry;
  }

  /// Marks [id] as just opened (it moves to the top).
  Future<void> touch(String course, String id) async {
    final texts = [...await list(course)];
    final i = texts.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final t = texts.removeAt(i).touched(clock().toUtc());
    await _write(course, [t, ...texts]);
  }

  /// Deletes [id]; returns what Undo needs (null when it wasn't there).
  Future<(SavedText, String)?> delete(String course, String id) async {
    final texts = [...await list(course)];
    final i = texts.indexWhere((t) => t.id == id);
    if (i < 0) return null;
    final entry = texts.removeAt(i);
    final body = await text(course, id) ?? '';
    await store.setSetting(textKey(course, id), null);
    await _write(course, texts);
    return (entry, body);
  }

  /// Puts back a deleted text (Undo).
  Future<void> restore(String course, SavedText entry, String body) async {
    await store.setSetting(textKey(course, entry.id), body);
    final texts = [entry, ...(await list(course)).where((t) => t.id != entry.id)]
      ..sort((a, b) => b.at.compareTo(a.at));
    await _write(course, texts.take(kMaxSavedTexts).toList());
  }
}

final savedTextStoreProvider = Provider<SavedTextStore>(
  (ref) => SavedTextStore(ref.watch(progressStoreProvider), clock: ref.watch(clockProvider)),
);

/// The active course's recent texts.
final savedTextsProvider = AsyncNotifierProvider<SavedTextsController, List<SavedText>>(SavedTextsController.new);

class SavedTextsController extends AsyncNotifier<List<SavedText>> {
  @override
  Future<List<SavedText>> build() async {
    final course = await ref.watch(activeCourseIdProvider.future);
    return ref.watch(savedTextStoreProvider).list(course);
  }

  Future<String> get _course => ref.read(activeCourseIdProvider.future);

  Future<SavedText> save(String text) async {
    final course = await _course;
    final store = ref.read(savedTextStoreProvider);
    final entry = await store.save(course, text);
    state = AsyncData(await store.list(course));
    return entry;
  }

  Future<void> touch(String id) async {
    final course = await _course;
    final store = ref.read(savedTextStoreProvider);
    await store.touch(course, id);
    state = AsyncData(await store.list(course));
  }

  Future<(SavedText, String)?> delete(String id) async {
    final course = await _course;
    final store = ref.read(savedTextStoreProvider);
    final gone = await store.delete(course, id);
    state = AsyncData(await store.list(course));
    return gone;
  }

  Future<void> restore(SavedText entry, String body) async {
    final course = await _course;
    final store = ref.read(savedTextStoreProvider);
    await store.restore(course, entry, body);
    state = AsyncData(await store.list(course));
  }
}

/// A saved text of the active course, looked up for reading (null when it
/// was deleted).
final readingTextProvider = FutureProvider.autoDispose.family<(SavedText, ReadingText)?, String>((ref, id) async {
  final course = await ref.watch(courseDataProvider.future);
  final store = ref.watch(savedTextStoreProvider);
  final entry = (await store.list(course.meta.id)).where((t) => t.id == id).firstOrNull;
  final body = await store.text(course.meta.id, id);
  if (entry == null || body == null) return null;
  return (entry, ReadingText.analyze(body, course));
});

/// Items of the active course the learner has practised (any facet reviewed):
/// the reader's "known" words, like the topics' "words already known".
final knownItemsProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(progressRevisionProvider);
  final course = await ref.watch(activeCourseIdProvider.future);
  final states = await ref.watch(progressStoreProvider).allStates(courseId: course);
  return {
    for (final s in states)
      if (s.facetId.lastIndexOf('#') case final i when i > 0) s.facetId.substring(0, i),
  };
});

/// Setting (this device only, like every `reading.` key): highlight the
/// words the learner knows in the reader.
const String kReadingHighlightKnownKey = 'reading.highlight_known';

final readingHighlightKnownProvider = AsyncNotifierProvider<ReadingHighlightKnown, bool>(ReadingHighlightKnown.new);

class ReadingHighlightKnown extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async => await ref.watch(progressStoreProvider).getSetting(kReadingHighlightKnownKey) == 'true';

  Future<void> set(bool on) async {
    state = AsyncData(on);
    await ref.read(progressStoreProvider).setSetting(kReadingHighlightKnownKey, on ? 'true' : null);
  }
}
