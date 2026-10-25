/// "My words": words the learner adds themselves (from the reader or by
/// hand), practised like pack items. Pure Dart.
///
/// * **Ids** are namespaced so they never clash with pack ids: a word's id is
///   `user~<uuid>`, its item id in a course `{course}:user~<uuid>` (pack item
///   ids are `{course}:{lemma}`, and no lemma starts with `user~`), and its
///   facets `{course}:user~<uuid>#rec` / `#prod`, so the review log, FSRS,
///   per-course filters and cloud sync of the log treat them like any facet.
/// * **Storage**: the progress database (`user_words`, schema v4) behind
///   [UserWordRepo] (`core/interfaces/user_words.dart`), in the backup, and
///   synced. Every entry, deleted ones included ([UserWord.removed], a
///   tombstone), has a last-change time and merges last-writer-wins
///   ([UserWordSet.merge]), like bookmarks, so a merge never brings back a
///   word deleted on another device.
library;

import 'package:meta/meta.dart';

/// Prefix of a user word's id (`user~<uuid>`).
const String kUserWordPrefix = 'user~';

/// The pseudo skill user-word facets are planned under (no pack has it).
const String kMyWordsSkillId = 'user~my-words';

/// Whether [itemId] (`{course}:user~…`) is a user word's item.
bool isUserItemId(String itemId) => itemId.contains(':$kUserWordPrefix');

/// Whether [facetId] belongs to a user word.
bool isUserFacetId(String facetId) => facetId.contains(':$kUserWordPrefix');

@immutable
class UserWord {
  const UserWord({
    required this.id,
    required this.word,
    required this.translation,
    required this.at,
    DateTime? created,
    this.note,
    this.example,
    this.lemmaId,
    this.pos,
    this.lang,
    this.removed = false,
  }) : created = created ?? at;

  /// `user~<uuid>`.
  final String id;

  /// The target-language word or phrase, as the learner wants to practise it.
  final String word;

  /// Its meaning in the learner's language; several separated by `,` or `;`.
  final String translation;

  /// A note (grammar, usage), free text.
  final String? note;

  /// An example sentence (the reader fills in the sentence the word was found in).
  final String? example;

  /// The pack item the word was looked up as, when it was found in the course.
  final String? lemmaId;

  /// Part of speech (from the pack item), for wrong options of the same kind.
  final String? pos;

  /// The language of [translation] (the source language when it was added).
  final String? lang;

  /// When it was added.
  final DateTime created;

  /// Last change (added, edited, deleted), UTC, whole milliseconds.
  final DateTime at;

  /// Deleted (a tombstone).
  final bool removed;

  /// The item id in course [courseId].
  String itemId(String courseId) => '$courseId:$id';

  String recFacet(String courseId) => '${itemId(courseId)}#rec';
  String prodFacet(String courseId) => '${itemId(courseId)}#prod';

  /// The meanings, split on `,` and `;`.
  List<String> get meanings => [
    for (final m in translation.split(RegExp('[,;]')))
      if (m.trim().isNotEmpty) m.trim(),
  ];

  UserWord copyWith({
    String? word,
    String? translation,
    String? note,
    String? example,
    DateTime? at,
    bool? removed,
    bool clearNote = false,
    bool clearExample = false,
  }) => UserWord(
    id: id,
    word: word ?? this.word,
    translation: translation ?? this.translation,
    note: clearNote ? null : (note ?? this.note),
    example: clearExample ? null : (example ?? this.example),
    lemmaId: lemmaId,
    pos: pos,
    lang: lang,
    created: created,
    at: at ?? this.at,
    removed: removed ?? this.removed,
  );

  /// The tombstone of this word at [at] (keeps only what identifies it).
  UserWord tombstone(DateTime at) =>
      UserWord(id: id, word: '', translation: '', at: at, created: created, removed: true);

  Map<String, Object?> toJson() => {
    'id': id,
    'at': at.toUtc().millisecondsSinceEpoch,
    'created': created.toUtc().millisecondsSinceEpoch,
    if (removed) 'del': true,
    if (!removed) 'word': word,
    if (!removed) 'tr': translation,
    if (!removed && note != null) 'note': note,
    if (!removed && example != null) 'ex': example,
    if (!removed && lemmaId != null) 'lemma': lemmaId,
    if (!removed && pos != null) 'pos': pos,
    if (!removed && lang != null) 'lang': lang,
  };

  /// Null for an entry this version can't read (no id, no time, a foreign id).
  static UserWord? fromJson(Map<String, Object?> j) {
    final id = j['id'];
    final at = j['at'];
    if (id is! String || !id.startsWith(kUserWordPrefix) || at is! num) return null;
    final created = j['created'];
    DateTime ms(num v) => DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    final removed = j['del'] == true;
    final word = j['word'];
    final tr = j['tr'];
    if (!removed && (word is! String || tr is! String)) return null;
    return UserWord(
      id: id,
      word: removed ? '' : word as String,
      translation: removed ? '' : tr as String,
      note: j['note'] as String?,
      example: j['ex'] as String?,
      lemmaId: j['lemma'] as String?,
      pos: j['pos'] as String?,
      lang: j['lang'] as String?,
      at: ms(at),
      created: created is num ? ms(created) : ms(at),
      removed: removed,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UserWord &&
      other.id == id &&
      other.word == word &&
      other.translation == translation &&
      other.note == note &&
      other.example == example &&
      other.lemmaId == lemmaId &&
      other.pos == pos &&
      other.lang == lang &&
      other.created == created &&
      other.at == at &&
      other.removed == removed;

  @override
  int get hashCode => Object.hash(id, word, translation, note, example, lemmaId, pos, lang, created, at, removed);

  @override
  String toString() => 'UserWord($id, $word = $translation${removed ? ', removed' : ''}, $at)';
}

/// The user words of one course, tombstones included. Immutable.
@immutable
class UserWordSet {
  UserWordSet(Iterable<UserWord> all) : _all = {for (final w in all) w.id: w};

  static final UserWordSet empty = UserWordSet(const []);

  final Map<String, UserWord> _all;

  /// Every entry, tombstones included.
  Iterable<UserWord> get all => _all.values;

  UserWord? operator [](String id) => _all[id];

  /// The words (not deleted), most recently added first.
  List<UserWord> get live =>
      [
        for (final w in _all.values)
          if (!w.removed) w,
      ]..sort((a, b) {
        final c = b.created.compareTo(a.created);
        return c != 0 ? c : a.id.compareTo(b.id);
      });

  int get length => _all.values.where((w) => !w.removed).length;
  bool get isEmpty => length == 0;

  /// With [w] (replacing its earlier entry).
  UserWordSet put(UserWord w) => UserWordSet([..._all.values.where((x) => x.id != w.id), w]);

  /// Whether [incoming] wins over [mine]: the later change wins; on a tie a
  /// deletion wins (a merge never resurrects what one side deleted at that
  /// moment), then the larger encoding (so both sides agree).
  static bool wins(UserWord incoming, UserWord? mine) {
    if (mine == null) return true;
    final c = incoming.at.compareTo(mine.at);
    if (c != 0) return c > 0;
    if (incoming.removed != mine.removed) return incoming.removed;
    return incoming.toJson().toString().compareTo(mine.toJson().toString()) > 0;
  }

  /// Last writer wins per word ([wins]).
  UserWordSet merge(UserWordSet other) {
    final out = Map.of(_all);
    for (final w in other._all.values) {
      if (wins(w, out[w.id])) out[w.id] = w;
    }
    return UserWordSet(out.values);
  }

  /// The entries of [other] that [merge] would take (new, or newer than mine).
  List<UserWord> changesFrom(UserWordSet other) => [
    for (final w in other._all.values)
      if (wins(w, _all[w.id]) && _all[w.id] != w) w,
  ];
}
