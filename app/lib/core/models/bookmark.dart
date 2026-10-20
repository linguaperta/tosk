/// Bookmarks ("starred"): words, sentences and exercises the learner starred,
/// per course. Pure Dart. Stored in the progress database (`bookmarks`,
/// schema v3) behind [BookmarkRepo] (`core/interfaces/bookmarks.dart`),
/// merged last-writer-wins per bookmark, so a backup import (or a later sync)
/// never resurrects an unstarred one: unstarring keeps a tombstone
/// ([Bookmark.removed]). See docs/progression.md, "Bookmarks".
library;

import 'package:meta/meta.dart';

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
  /// exercise's type, facet and prompt (exercise; `exerciseBookmarkId`).
  final String id;

  /// Last change (starred or unstarred), UTC, whole milliseconds.
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

  /// Identity within a course (and across devices): kind and id.
  String get key => bookmarkKey(kind, id);

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

  /// The tombstone of this bookmark at [at].
  Bookmark tombstone(DateTime at) => Bookmark(kind: kind, id: id, at: at, removed: true);

  /// The backup line body (`{"kind":"bookmark","course":…}` adds the rest).
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

  /// Null for an entry this version can't read (an unknown kind, no id).
  static Bookmark? fromJson(Map<String, Object?> j) {
    final kind = BookmarkKind.tryParse(j['k'] as String?);
    final id = j['id'];
    final at = j['at'];
    if (kind == null || id is! String || id.isEmpty || at is! num) return null;
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
      other.facetId == facetId &&
      (other.exercise == null) == (exercise == null);

  @override
  int get hashCode => Object.hash(kind, id, at, removed, label, detail, facetId);

  @override
  String toString() => 'Bookmark($key${removed ? ', removed' : ''}, $at)';
}

String bookmarkKey(BookmarkKind kind, String id) => '${kind.name}:$id';

/// The bookmarks of one course, tombstones included. Immutable.
@immutable
class BookmarkSet {
  BookmarkSet(Iterable<Bookmark> all) : _all = {for (final b in all) b.key: b};

  static final BookmarkSet empty = BookmarkSet(const []);

  final Map<String, Bookmark> _all;

  /// Every entry, tombstones included.
  Iterable<Bookmark> get all => _all.values;

  Bookmark? operator [](String key) => _all[key];

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

  bool contains(BookmarkKind kind, String id) => !(_all[bookmarkKey(kind, id)]?.removed ?? true);

  int get length => _all.values.where((b) => !b.removed).length;
  bool get isEmpty => length == 0;

  /// With [b] (replacing its earlier entry).
  BookmarkSet put(Bookmark b) => BookmarkSet([..._all.values.where((x) => x.key != b.key), b]);

  /// Whether [incoming] wins over [mine] in a merge: the later change wins; on
  /// a tie the removal wins, so a merge never resurrects what one side
  /// unstarred at that moment.
  static bool wins(Bookmark incoming, Bookmark? mine) =>
      mine == null ||
      incoming.at.isAfter(mine.at) ||
      (incoming.at == mine.at && incoming.removed && !mine.removed);

  /// Last writer wins per bookmark ([wins]).
  BookmarkSet merge(BookmarkSet other) {
    final out = Map.of(_all);
    for (final b in other._all.values) {
      if (wins(b, out[b.key])) out[b.key] = b;
    }
    return BookmarkSet(out.values);
  }

  /// The entries of [other] that [merge] would take (new or newer than mine).
  List<Bookmark> changesFrom(BookmarkSet other) => [
    for (final b in other._all.values)
      if (wins(b, _all[b.key]) && _all[b.key] != b) b,
  ];
}
