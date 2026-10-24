/// "My words" in the UI: the store and the active course's words. Storage
/// and merging: `data/progress/user_words.dart` over the progress DB
/// (`userWordRepoProvider`); the engine side is `engine/session/my_words.dart`.
/// See docs/ui.md, "My words".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../data/progress/user_words.dart';
import '../../engine/engine.dart' show readingKey;
import '../../providers.dart';
import '../../sync/sync_providers.dart';

/// Adds, edits and deletes through the progress DB; a change schedules a
/// cloud sync soon (signed in).
final userWordStoreProvider = Provider<UserWordStore>(
  (ref) => UserWordStore(
    ref.watch(userWordRepoProvider),
    clock: ref.watch(clockProvider),
    onChanged: () {
      try {
        ref.read(syncServiceProvider)?.localDataChanged();
      } catch (_) {} // the store outlived its scope
    },
  ),
);

/// What the add sheet starts with (the reader prefills it).
class MyWordDraft {
  const MyWordDraft({this.word = '', this.translation = '', this.note, this.example, this.lemmaId, this.pos});
  final String word;
  final String translation;
  final String? note;
  final String? example;
  final String? lemmaId;
  final String? pos;
}

/// The active course's words, tombstones included (reloaded after every
/// progress refresh, so a sync or an imported backup shows up).
final userWordsProvider = AsyncNotifierProvider<UserWordsController, UserWordSet>(UserWordsController.new);

class UserWordsController extends AsyncNotifier<UserWordSet> {
  String? _course;

  @override
  Future<UserWordSet> build() async {
    ref.watch(progressRevisionProvider);
    final course = await ref.watch(activeCourseIdProvider.future);
    _course = course;
    return ref.watch(userWordStoreProvider).load(course);
  }

  Future<String> _courseId() async {
    await future;
    return _course ?? await ref.read(activeCourseIdProvider.future);
  }

  /// Adds a word in the source language the learner uses now.
  Future<UserWord> add(MyWordDraft d) async {
    final course = await _courseId();
    final store = ref.read(userWordStoreProvider);
    final w = await store.add(
      course,
      word: d.word,
      translation: d.translation,
      note: d.note,
      example: d.example,
      lemmaId: d.lemmaId,
      pos: d.pos,
      lang: ref.read(sourceLangProvider),
    );
    state = AsyncData(await store.load(course));
    return w;
  }

  Future<void> edit(UserWord w) async {
    final course = await _courseId();
    state = AsyncData(await ref.read(userWordStoreProvider).edit(course, w));
  }

  Future<void> remove(String id) async {
    final course = await _courseId();
    state = AsyncData(await ref.read(userWordStoreProvider).remove(course, id));
  }

  /// Undo of a delete.
  Future<void> restore(UserWord w) async {
    final course = await _courseId();
    state = AsyncData(await ref.read(userWordStoreProvider).restore(course, w));
  }
}

/// The number of words in the active course.
final myWordsCountProvider = Provider<int>((ref) => ref.watch(userWordsProvider).value?.length ?? 0);

/// The active course's words by written form ([readingKey]): the reader marks
/// them and shows the learner's own meaning.
final myWordsByFormProvider = Provider<Map<String, UserWord>>((ref) {
  final set = ref.watch(userWordsProvider).value;
  if (set == null) return const {};
  return {for (final w in set.live.reversed) readingKey(w.word): w};
});

/// How far along a word is.
enum MyWordStatus {
  /// Never practised.
  fresh,

  /// A facet is due now.
  due,

  /// Practised, still in the learning steps.
  learning,

  /// Both facets past the learning steps.
  learned,
}

String myWordStatusLabel(MyWordStatus s) => switch (s) {
  MyWordStatus.fresh => 'New',
  MyWordStatus.due => 'Due',
  MyWordStatus.learning => 'Learning',
  MyWordStatus.learned => 'Learned',
};

/// Every live word's status, by word id.
final myWordStatusProvider = FutureProvider<Map<String, MyWordStatus>>((ref) async {
  ref.watch(progressRevisionProvider);
  final set = await ref.watch(userWordsProvider.future);
  final course = await ref.watch(activeCourseIdProvider.future);
  final words = set.live;
  if (words.isEmpty) return const {};
  final states = await ref.watch(progressStoreProvider).states([
    for (final w in words) ...[w.recFacet(course), w.prodFacet(course)],
  ]);
  final now = ref.watch(clockProvider)().toUtc();
  return {
    for (final w in words)
      w.id: () {
        final s = [states[w.recFacet(course)], states[w.prodFacet(course)]];
        if (s.every((x) => x == null)) return MyWordStatus.fresh;
        if (s.any((x) => x != null && x.isDue(now))) return MyWordStatus.due;
        if (s.every((x) => x != null && x.phase == CardPhase.review)) return MyWordStatus.learned;
        return MyWordStatus.learning;
      }(),
  };
});

/// Ids of the words the learner has practised (counted as known in the reader).
final myWordsPractisedProvider = Provider<Set<String>>((ref) {
  final st = ref.watch(myWordStatusProvider).value ?? const {};
  return {
    for (final e in st.entries)
      if (e.value != MyWordStatus.fresh) e.key,
  };
});
