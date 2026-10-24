/// "My words" storage: the core [UserWordRepo] over the progress database's
/// `user_words` table (schema v4; [DriftUserWordRepo]) or in memory
/// ([InMemoryUserWordRepo], tests and the defaults), and [UserWordStore],
/// which adds, edits, deletes (a tombstone), restores and merges with
/// last-writer-wins semantics. Pure Dart. See docs/data-layer.md, "My words".
library;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/core.dart';
import 'progress_db.dart';

/// [UserWordRepo] over the progress database's `user_words` table.
class DriftUserWordRepo implements UserWordRepo {
  DriftUserWordRepo(this.db);
  final ProgressDb db;

  @override
  Future<UserWordSet> load(String courseId) async {
    final rows = await (db.select(db.userWords)..where((r) => r.courseId.equals(courseId))).get();
    return UserWordSet([for (final r in rows) _fromRow(r)]);
  }

  @override
  Future<Map<String, UserWordSet>> all() async {
    final rows = await db.select(db.userWords).get();
    final out = <String, List<UserWord>>{};
    for (final r in rows) {
      (out[r.courseId] ??= []).add(_fromRow(r));
    }
    return {for (final e in out.entries) e.key: UserWordSet(e.value)};
  }

  @override
  Future<void> put(String courseId, Iterable<UserWord> entries) => db.batch((batch) {
    for (final w in entries) {
      final gone = w.removed;
      batch.insert(
        db.userWords,
        UserWordsCompanion.insert(
          courseId: courseId,
          id: w.id,
          word: Value(gone ? '' : w.word),
          translation: Value(gone ? '' : w.translation),
          note: Value(gone ? null : w.note),
          example: Value(gone ? null : w.example),
          lemmaId: Value(gone ? null : w.lemmaId),
          pos: Value(gone ? null : w.pos),
          lang: Value(gone ? null : w.lang),
          createdAt: w.created.toUtc().millisecondsSinceEpoch,
          at: w.at.toUtc().millisecondsSinceEpoch,
          removed: Value(gone),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  });

  static UserWord _fromRow(UserWordRow r) => UserWord(
    id: r.id,
    word: r.word,
    translation: r.translation,
    note: r.note,
    example: r.example,
    lemmaId: r.lemmaId,
    pos: r.pos,
    lang: r.lang,
    created: DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true),
    at: DateTime.fromMillisecondsSinceEpoch(r.at, isUtc: true),
    removed: r.removed,
  );
}

/// [UserWordRepo] in memory (same semantics as [DriftUserWordRepo]).
class InMemoryUserWordRepo implements UserWordRepo {
  final Map<String, Map<String, UserWord>> _courses = {};

  @override
  Future<UserWordSet> load(String courseId) async => UserWordSet((_courses[courseId] ?? const {}).values);

  @override
  Future<Map<String, UserWordSet>> all() async => {
    for (final e in _courses.entries)
      if (e.value.isNotEmpty) e.key: UserWordSet(e.value.values),
  };

  @override
  Future<void> put(String courseId, Iterable<UserWord> entries) async {
    final m = _courses[courseId] ??= {};
    for (final w in entries) {
      m[w.id] = w.removed ? w.tombstone(w.at) : w;
    }
  }
}

/// A new word's id: `user~<uuid v4>`.
String newUserWordId() => '$kUserWordPrefix${const Uuid().v4()}';

/// Adds, edits, deletes and merges the words of a [UserWordRepo]. Changes per
/// course are serialized (read, change, write), so quick taps never lose one,
/// and every change gets a strictly later time than the previous one.
class UserWordStore {
  UserWordStore(this.repo, {DateTime Function()? clock, this.onChanged}) : clock = clock ?? DateTime.now;

  final UserWordRepo repo;
  final DateTime Function() clock;

  /// Called after a local change (add, edit, delete, restore): cloud sync
  /// uses it to schedule an upload. Not called for merges.
  final void Function()? onChanged;

  static final Map<(UserWordRepo, String), Future<void>> _writing = {};

  Future<UserWordSet> load(String courseId) => repo.load(courseId);

  Future<UserWordSet> _update(String courseId, List<UserWord> Function(UserWordSet s) edit, {bool local = true}) {
    final key = (repo, courseId);
    final done = Completer<UserWordSet>();
    final previous = _writing[key] ?? Future<void>.value();
    final next = previous.then((_) async {
      var current = await repo.load(courseId);
      final changes = edit(current);
      if (changes.isNotEmpty) {
        await repo.put(courseId, changes);
        for (final w in changes) {
          current = current.put(w);
        }
      }
      done.complete(current);
      if (changes.isNotEmpty && local) onChanged?.call();
    }).catchError((Object e, StackTrace st) {
      if (!done.isCompleted) done.completeError(e, st);
    });
    _writing[key] = next;
    unawaited(next.whenComplete(() {
      if (identical(_writing[key], next)) _writing.remove(key);
    }));
    return done.future;
  }

  /// Adds a word (a new id unless [id] is given). Returns the stored word.
  Future<UserWord> add(
    String courseId, {
    required String word,
    required String translation,
    String? note,
    String? example,
    String? lemmaId,
    String? pos,
    String? lang,
    String? id,
  }) async {
    late UserWord added;
    await _update(courseId, (s) {
      final t = _now(s);
      added = UserWord(
        id: id ?? newUserWordId(),
        word: word.trim(),
        translation: translation.trim(),
        note: _blank(note),
        example: _blank(example),
        lemmaId: lemmaId,
        pos: pos,
        lang: lang,
        created: t,
        at: t,
      );
      return [added];
    });
    return added;
  }

  /// Saves [word]'s new text (its time is set to now).
  Future<UserWordSet> edit(String courseId, UserWord word) => _update(courseId, (s) {
    final t = _now(s);
    return [
      UserWord(
        id: word.id,
        word: word.word.trim(),
        translation: word.translation.trim(),
        note: _blank(word.note),
        example: _blank(word.example),
        lemmaId: word.lemmaId,
        pos: word.pos,
        lang: word.lang,
        created: s[word.id]?.created ?? word.created,
        at: t,
      ),
    ];
  });

  /// Deletes word [id] (keeps a tombstone). Nothing happens when it isn't there.
  Future<UserWordSet> remove(String courseId, String id) => _update(courseId, (s) {
    final old = s[id];
    if (old == null || old.removed) return const [];
    return [old.tombstone(_now(s))];
  });

  /// Brings a deleted word back as it was (Undo), with a new change time.
  Future<UserWordSet> restore(String courseId, UserWord word) =>
      _update(courseId, (s) => [word.copyWith(at: _now(s), removed: false)]);

  /// Merges [incoming] (a backup's or another device's) in, last writer wins
  /// per word. Returns how many entries changed here.
  Future<int> mergeIn(String courseId, UserWordSet incoming) async {
    var changed = 0;
    await _update(courseId, (s) {
      final c = s.changesFrom(incoming);
      changed = c.length;
      return c;
    }, local: false);
    return changed;
  }

  static String? _blank(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  /// Now (UTC, whole ms), strictly after every change in [s] and after this
  /// store's previous change.
  DateTime _now(UserWordSet s) {
    var t = clock().toUtc();
    t = DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true);
    for (final b in [?_last, ...s.all.map((w) => w.at)]) {
      if (!t.isAfter(b)) t = b.add(const Duration(milliseconds: 1));
    }
    _last = t;
    return t;
  }

  DateTime? _last;
}
