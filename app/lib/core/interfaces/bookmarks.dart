/// Storage contract for bookmarks ("starred" words, sentences, exercises).
/// Implemented by the data layer (`data/progress/bookmarks.dart`: the drift
/// table `bookmarks` in the progress database, and an in-memory repo for
/// tests and the defaults). Small on purpose, so a sync backend can carry
/// bookmarks later: every entry (tombstones included) has a last-change time
/// and merges last-writer-wins ([BookmarkSet.merge]).
library;

import '../models/bookmark.dart';

abstract interface class BookmarkRepo {
  /// Every bookmark of [courseId], tombstones included.
  Future<BookmarkSet> load(String courseId);

  /// Every course's bookmarks, tombstones included (backup, sync).
  Future<Map<String, BookmarkSet>> all();

  /// Inserts or replaces [entries] of [courseId] (by kind and id) as given;
  /// merging is the caller's job (`BookmarkStore`).
  Future<void> put(String courseId, Iterable<Bookmark> entries);
}
