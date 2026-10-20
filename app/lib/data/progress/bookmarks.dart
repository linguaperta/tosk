/// Bookmarks ("starred"): words, sentences and exercises the learner starred,
/// per course. Pure Dart; stored as one JSON setting per course through the
/// [ProgressStore] (no schema change), merged last-writer-wins per bookmark so
/// a backup import (or a later sync) never resurrects an unstarred one.
///
/// Setting `bookmarks.{courseId}`:
///
/// ```json
/// {"format":"tosk-bookmarks/1","items":[
///   {"k":"word","id":"it:mangiare","at":1760000000000,"label":"mangiare","detail":"to eat"},
///   {"k":"sentence","id":"s:123","at":…,"label":"Mangio il pane.","detail":"I eat bread."},
///   {"k":"exercise","id":"<hash>","at":…,"label":"<prompt>","detail":"cloze","facet":"it:mangiare#form:presente",
///    "ex":{…exercise snapshot…}},
///   {"k":"word","id":"it:pane","at":…,"del":true}]}
/// ```
///
/// `at` is the time of the last change (UTC epoch ms); `del` marks an
/// unstarred bookmark (a tombstone, kept so merges know it was removed).
/// See docs/ui.md, "Bookmarks".
library;

import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import '../../core/core.dart';

const String kBookmarksFormat = 'tosk-bookmarks/1';

/// Settings key prefix of the per-course bookmark lists.
const String kBookmarksKeyPrefix = 'bookmarks.';

String bookmarksKey(String courseId) => '$kBookmarksKeyPrefix$courseId';

/// Tombstones kept per course (the oldest beyond this are dropped).
const int kMaxBookmarkTombstones = 300;

enum BookmarkKind {
  word,
  sentence,
  exercise;

  static BookmarkKind? tryParse(String? s) {
    for (final k in values) {
      if (k.name == s) return k;
    }
    return null;
  }
}

@immutable
class Bookmark {
  const Bookmark({
    required this.kind,
    required this.id,
    required this.at,
    this.label = '',
    this.detail,
    this.facetId,
    this.exercise,
    this.removed = false,
  });

  final BookmarkKind kind;

  /// Item id (word), sentence id (sentence) or a stable hash of the
  /// exercise's type, facet and prompt (exercise; `ui/bookmarks/`).
  final String id;

  /// Last change (starred or unstarred), UTC.
  final DateTime at;

  /// What the list shows: the word with its article, the sentence, the
  /// exercise's prompt.
  final String label;

  /// A gloss, translation or exercise type label.
  final String? detail;

  /// Exercise bookmarks: the primary facet.
  final String? facetId;

  /// Exercise bookmarks: the full snapshot (`feedback/exercise_snapshot.dart`).
  final Map<String, Object?>? exercise;

  /// Unstarred (a tombstone).
  final bool removed;

  /// Identity across devices: kind and id.
  String get key => '${kind.name}:$id';

  Bookmark copyWith({DateTime? at, bool? removed}) => Bookmark(
    kind: kind,
    id: id,
    at: at ?? this.at,
    label: label,
    detail: detail,
    facetId: facetId,
    exercise: exercise,
    removed: removed ?? this.removed,
  );

  Map<String, Object?> toJson() => {
    'k': kind.name,
    'id': id,
    'at': at.toUtc().millisecondsSinceEpoch,
    if (removed) 'del': true,
    if (!removed && label.isNotEmpty) 'label': label,
    if (!removed && detail != null) 'detail': detail,
    if (!removed && facetId != null) 'facet': facetId,
    if (!removed && exercise != null) 'ex': exercise,
  };

  /// Null for an entry this version can't read (an unknown kind).
  static Bookmark? fromJson(Map<String, Object?> j) {
    final kind = BookmarkKind.tryParse(j['k'] as String?);
    final id = j['id'];
    final at = j['at'];
    if (kind == null || id is! String || at is! num) return null;
    final ex = j['ex'];
    return Bookmark(
      kind: kind,
      id: id,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt(), isUtc: true),
      label: j['label'] as String? ?? '',
      detail: j['detail'] as String?,
      facetId: j['facet'] as String?,
      exercise: ex is Map ? ex.cast<String, Object?>() : null,
      removed: j['del'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Bookmark &&
      other.kind == kind &&
      other.id == id &&
      other.at == at &&
      other.removed == removed &&
      other.label == label &&
      other.detail == detail &&
      other.facetId == facetId;

  @override
  int get hashCode => Object.hash(kind, id, at, removed, label, detail, facetId);
}

/// The bookmarks of one course, tombstones included.
@immutable
class BookmarkSet {
  BookmarkSet(Iterable<Bookmark> all) : _all = {for (final b in all) b.key: b};

  static final BookmarkSet empty = BookmarkSet(const []);

  final Map<String, Bookmark> _all;

  /// Every entry, tombstones included.
  Iterable<Bookmark> get all => _all.values;

  /// Starred bookmarks, most recently starred first.
  List<Bookmark> get live =>
      [
        for (final b in _all.values)
          if (!b.removed) b,
      ]..sort((a, b) {
        final c = b.at.compareTo(a.at);
        return c != 0 ? c : a.key.compareTo(b.key);
      });

  List<Bookmark> of(BookmarkKind kind) => [
    for (final b in live)
      if (b.kind == kind) b,
  ];

  bool contains(BookmarkKind kind, String id) => !(_all['${kind.name}:$id']?.removed ?? true);

  int get length => _all.values.where((b) => !b.removed).length;
  bool get isEmpty => length == 0;

  /// With [b] (replacing its earlier entry).
  BookmarkSet put(Bookmark b) => BookmarkSet([..._all.values.where((x) => x.key != b.key), b]);

  /// Last writer wins per bookmark ([Bookmark.at]; on a tie the removal
  /// wins, so a merge never resurrects what one side unstarred at that moment).
  BookmarkSet merge(BookmarkSet other) {
    final out = Map.of(_all);
    for (final b in other._all.values) {
      final mine = out[b.key];
      if (mine == null || b.at.isAfter(mine.at) || (b.at == mine.at && b.removed && !mine.removed)) {
        out[b.key] = b;
      }
    }
    return BookmarkSet(out.values);
  }

  String encode() {
    final tombs = [
      for (final b in _all.values)
        if (b.removed) b,
    ]..sort((a, b) => b.at.compareTo(a.at));
    final keepTombs = tombs.take(kMaxBookmarkTombstones).toSet();
    final items = [
      for (final b in _all.values)
        if (!b.removed || keepTombs.contains(b)) b,
    ]..sort((a, b) {
      final c = a.at.compareTo(b.at);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
    return jsonEncode({'format': kBookmarksFormat, 'items': [for (final b in items) b.toJson()]});
  }

  /// Decodes a stored value; anything unreadable is an empty set (bookmarks
  /// are a convenience, never a reason to fail).
  static BookmarkSet decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final j = jsonDecode(raw);
      final items = j is Map ? j['items'] : null;
      if (items is! List) return empty;
      return BookmarkSet([
        for (final e in items)
          if (e is Map) ?Bookmark.fromJson(e.cast<String, Object?>()),
      ]);
    } on Object {
      return empty;
    }
  }
}

/// Reads and writes the bookmark settings. Writes per course are serialized
/// (read, change, write), so quick taps never lose a change.
class BookmarkStore {
  BookmarkStore(this.store, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  final ProgressStore store;
  final DateTime Function() clock;

  static final Map<(ProgressStore, String), Future<void>> _writing = {};

  Future<BookmarkSet> load(String courseId) async => BookmarkSet.decode(await store.getSetting(bookmarksKey(courseId)));

  Future<BookmarkSet> _update(String courseId, BookmarkSet Function(BookmarkSet s) edit) {
    final key = (store, courseId);
    final done = Completer<BookmarkSet>();
    final previous = _writing[key] ?? Future<void>.value();
    final next = previous.then((_) async {
      final current = await load(courseId);
      final updated = edit(current);
      await store.setSetting(bookmarksKey(courseId), updated.encode());
      done.complete(updated);
    }).catchError((Object e, StackTrace st) {
      if (!done.isCompleted) done.completeError(e, st);
    });
    _writing[key] = next;
    unawaited(next.whenComplete(() {
      if (identical(_writing[key], next)) _writing.remove(key);
    }));
    return done.future;
  }

  /// Stars [b] (its `at` is set to now).
  Future<BookmarkSet> add(String courseId, Bookmark b) =>
      _update(courseId, (s) => s.put(b.copyWith(at: _now(), removed: false)));

  /// Unstars the bookmark [kind]/[id] (a tombstone).
  Future<BookmarkSet> remove(String courseId, BookmarkKind kind, String id) => _update(courseId, (s) {
    final key = '${kind.name}:$id';
    final old = s.all.where((b) => b.key == key).firstOrNull;
    if (old == null || old.removed) return s;
    return s.put(Bookmark(kind: kind, id: id, at: _now(), removed: true));
  });

  /// Stars [b] when it isn't starred, else unstars it. Returns the new set.
  Future<BookmarkSet> toggle(String courseId, Bookmark b) => _update(courseId, (s) {
    if (s.contains(b.kind, b.id)) return s.put(Bookmark(kind: b.kind, id: b.id, at: _now(), removed: true));
    return s.put(b.copyWith(at: _now(), removed: false));
  });

  /// Merges [incoming] into the stored set (backup import). Returns whether anything changed.
  Future<bool> mergeIn(String courseId, BookmarkSet incoming) async {
    var changed = false;
    await _update(courseId, (s) {
      final merged = s.merge(incoming);
      changed = merged.encode() != s.encode();
      return merged;
    });
    return changed;
  }

  /// Strictly increasing per store, so two quick changes (or a fixed test
  /// clock) keep their order.
  DateTime _now() {
    var t = clock().toUtc();
    t = DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true);
    final last = _last;
    if (last != null && !t.isAfter(last)) t = last.add(const Duration(milliseconds: 1));
    _last = t;
    return t;
  }

  DateTime? _last;
}
