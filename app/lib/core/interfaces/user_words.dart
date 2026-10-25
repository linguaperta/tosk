/// Storage contract for "my words" (the learner's own words, see
/// `core/models/user_word.dart`). Implemented by the data layer
/// (`data/progress/user_words.dart`: the drift table `user_words` in the
/// progress database, and an in-memory repo for tests and the defaults).
/// Like bookmarks: every entry, tombstones included, carries a last-change
/// time, and merges are last-writer-wins ([UserWordSet.merge]); backup and
/// cloud sync exchange [all] and merge it in.
library;

import '../models/user_word.dart';

abstract interface class UserWordRepo {
  /// Every word of [courseId], tombstones included.
  Future<UserWordSet> load(String courseId);

  /// Every course's words, tombstones included (backup, sync).
  Future<Map<String, UserWordSet>> all();

  /// Inserts or replaces [entries] of [courseId] (by id) as given; merging is
  /// the caller's job (`UserWordStore`).
  Future<void> put(String courseId, Iterable<UserWord> entries);
}
