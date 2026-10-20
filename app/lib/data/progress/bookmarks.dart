/// Bookmark storage: the core [BookmarkRepo] over the progress database's
/// `bookmarks` table (schema v3; [DriftBookmarkRepo]) or in memory
/// ([InMemoryBookmarkRepo], tests and the defaults), and [BookmarkStore],
/// which stars, unstars and merges with last-writer-wins semantics. Pure Dart.
/// See docs/progression.md, "Bookmarks".
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/core.dart';
import 'progress_db.dart';

/// [BookmarkRepo] over the progress database's `bookmarks` table.
class DriftBookmarkRepo implements BookmarkRepo {
  DriftBookmarkRepo(this.db);
  final ProgressDb db;

  @override
  Future<BookmarkSet> load(String courseId) async {
    final rows = await (db.select(db.bookmarks)..where((r) => r.courseId.equals(courseId))).get();
    return BookmarkSet([for (final r in rows) ?_fromRow(r)]);
  }

  @override
  Future<Map<String, BookmarkSet>> all() async {
    final rows = await db.select(db.bookmarks).get();
    final out = <String, List<Bookmark>>{};
    for (final r in rows) {
      final b = _fromRow(r);
      if (b != null) (out[r.courseId] ??= []).add(b);
    }
    return {for (final e in out.entries) e.key: BookmarkSet(e.value)};
  }

  @override
  Future<void> put(String courseId, Iterable<Bookmark> entries) => db.batch((batch) {
    for (final b in entries) {
      batch.insert(
        db.bookmarks,
        BookmarksCompanion.insert(
          courseId: courseId,
          kind: b.kind.name,
          refId: b.id,
          at: b.at.toUtc().millisecondsSinceEpoch,
          removed: Value(b.removed),
          label: Value(b.removed ? '' : b.label),
          detail: Value(b.removed ? null : b.detail),
          facetId: Value(b.removed ? null : b.facetId),
          exerciseJson: Value(b.removed || b.exercise == null ? null : jsonEncode(b.exercise)),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  });

  static Bookmark? _fromRow(BookmarkRow r) {
    final kind = BookmarkKind.tryParse(r.kind);
    if (kind == null) return null; // a kind from a newer app
    Map<String, Object?>? ex;
    final raw = r.exerciseJson;
    if (raw != null) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) ex = j.cast<String, Object?>();
      } on Object {
        ex = null;
      }
    }
    return Bookmark(
      kind: kind,
      id: r.refId,
      at: DateTime.fromMillisecondsSinceEpoch(r.at, isUtc: true),
      label: r.label,
      detail: r.detail,
      facetId: r.facetId,
      exercise: ex,
      removed: r.removed,
    );
  }
}

/// [BookmarkRepo] in memory (same semantics as [DriftBookmarkRepo]).
class InMemoryBookmarkRepo implements BookmarkRepo {
  final Map<String, Map<String, Bookmark>> _courses = {};

  @override
  Future<BookmarkSet> load(String courseId) async => BookmarkSet((_courses[courseId] ?? const {}).values);

  @override
  Future<Map<String, BookmarkSet>> all() async => {
    for (final e in _courses.entries)
      if (e.value.isNotEmpty) e.key: BookmarkSet(e.value.values),
  };

  @override
  Future<void> put(String courseId, Iterable<Bookmark> entries) async {
    final m = _courses[courseId] ??= {};
    for (final b in entries) {
      m[b.key] = b.removed ? b.tombstone(b.at) : b;
    }
  }
}

/// Stars, unstars and merges bookmarks of a [BookmarkRepo]. Changes per
/// course are serialized (read, change, write), so quick taps never lose one,
/// and every change gets a strictly later time than the previous one.
class BookmarkStore {
  BookmarkStore(this.repo, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  final BookmarkRepo repo;
  final DateTime Function() clock;

  static final Map<(BookmarkRepo, String), Future<void>> _writing = {};

  Future<BookmarkSet> load(String courseId) => repo.load(courseId);

  /// Runs [edit] on the current set and writes the entries it changed.
  Future<BookmarkSet> _update(String courseId, List<Bookmark> Function(BookmarkSet s) edit) {
    final key = (repo, courseId);
    final done = Completer<BookmarkSet>();
    final previous = _writing[key] ?? Future<void>.value();
    final next = previous.then((_) async {
      var current = await repo.load(courseId);
      final changes = edit(current);
      if (changes.isNotEmpty) {
        await repo.put(courseId, changes);
        for (final b in changes) {
          current = current.put(b);
        }
      }
      done.complete(current);
    }).catchError((Object e, StackTrace st) {
      if (!done.isCompleted) done.completeError(e, st);
    });
    _writing[key] = next;
    unawaited(next.whenComplete(() {
      if (identical(_writing[key], next)) _writing.remove(key);
    }));
    return done.future;
  }

  /// Stars [b] (its time is set to now).
  Future<BookmarkSet> add(String courseId, Bookmark b) =>
      _update(courseId, (s) => [b.copyWith(at: _now(s), removed: false)]);

  /// Unstars [kind]/[id] (keeps a tombstone). Nothing happens when it isn't starred.
  Future<BookmarkSet> remove(String courseId, BookmarkKind kind, String id) => _update(courseId, (s) {
    final old = s[bookmarkKey(kind, id)];
    if (old == null || old.removed) return const [];
    return [old.tombstone(_now(s))];
  });

  /// Stars [b] when it isn't starred, else unstars it. Returns the new set.
  Future<BookmarkSet> toggle(String courseId, Bookmark b) => _update(courseId, (s) {
    if (s.contains(b.kind, b.id)) return [b.tombstone(_now(s))];
    return [b.copyWith(at: _now(s), removed: false)];
  });

  /// Merges [incoming] (a backup's or another device's) in, last writer wins
  /// per bookmark. Returns how many entries changed here.
  Future<int> mergeIn(String courseId, BookmarkSet incoming) async {
    var changed = 0;
    await _update(courseId, (s) {
      final c = s.changesFrom(incoming);
      changed = c.length;
      return c;
    });
    return changed;
  }

  /// Now (UTC, whole ms), but strictly after every change in [s] and after
  /// this store's previous change, so a fixed test clock or two quick taps
  /// keep their order.
  DateTime _now(BookmarkSet s) {
    var t = clock().toUtc();
    t = DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true);
    for (final b in [?_last, ...s.all.map((b) => b.at)]) {
      if (!t.isAfter(b)) t = b.add(const Duration(milliseconds: 1));
    }
    _last = t;
    return t;
  }

  DateTime? _last;
}
