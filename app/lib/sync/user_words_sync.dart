/// Cloud sync of "my words" (the learner's own words): one small, additive
/// [SyncExtension] that runs after the review log and the settings.
///
/// It travels on the backend's settings channel, so it needs no new Firestore
/// collection, rule or backend call: each word is one settings document,
/// key `myword:{course}:{word id}`, value the word as JSON (a deleted word is
/// its tombstone), change time the word's [UserWord.at]. The settings sync
/// ignores these keys (they are not in its synced-settings list); this
/// extension reads them back with its own cursor and merges them
/// last-writer-wins per word ([UserWordSet.wins], like bookmarks), so a word
/// deleted on one device never comes back from another. A word is pushed
/// when its local version differs from the one this device last exchanged
/// for it with the account (a fingerprint per word, `myword.seen`, in the
/// sync store), so nothing is sent twice and a word that won a tie is sent.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/core.dart';
import '../data/progress/user_words.dart';
import 'sync_engine.dart';
import 'sync_store.dart';

class UserWordsSync implements SyncExtension {
  UserWordsSync(this.repo);

  final UserWordRepo repo;

  /// Settings-document keys of words: `myword:{course}:{id}`.
  static const keyPrefix = 'myword:';

  /// Sync-store keys (scoped to the account: [reset] clears them).
  static const cursorKey = 'myword.cursor';
  static const seenKey = 'myword.seen';

  static String keyOf(String course, String id) => '$keyPrefix$course:$id';

  /// `(course, id)` of a document key, or null for another key.
  static (String, String)? parseKey(String key) {
    if (!key.startsWith(keyPrefix)) return null;
    final rest = key.substring(keyPrefix.length);
    final i = rest.indexOf(':');
    if (i <= 0 || i == rest.length - 1) return null;
    return (rest.substring(0, i), rest.substring(i + 1));
  }

  @override
  Future<int> sync(SyncBackend backend, SyncStore store, {required String device, required DateTime now}) async {
    if (backend.accountId == null) return 0;
    final seen = _decodeSeen(await store.get(seenKey));

    // Pull the words written since the last run (a 2-minute overlap; reading
    // one twice is harmless).
    var cursor = SyncCursor.decode(await store.get(cursorKey));
    var after = cursor == null ? null : SyncCursor(cursor.time.subtract(SyncEngine.pullOverlap).toIso8601String(), '');
    final incoming = <String, List<UserWord>>{};
    // The newest version of each word in the account, as read now.
    final remote = <String, UserWord>{};
    while (true) {
      final page = await backend.pullSettings(after: after);
      for (final r in page.items) {
        final c = r.cursor;
        if (c != null) {
          after = c;
          if (cursor == null || _compare(c, cursor) > 0) cursor = c;
        }
        final key = parseKey(r.key);
        final v = r.value;
        if (key == null || v == null) continue;
        try {
          final w = UserWord.fromJson((jsonDecode(v) as Map).cast<String, Object?>());
          if (w == null || w.id != key.$2) continue;
          // An edit can't have happened after the server received it.
          final serverMs = c?.time.millisecondsSinceEpoch;
          final clamped = serverMs != null && w.at.millisecondsSinceEpoch > serverMs + SyncEngine.clampTolerance.inMilliseconds
              ? w.copyWith(at: DateTime.fromMillisecondsSinceEpoch(serverMs, isUtc: true))
              : w;
          (incoming[key.$1] ??= []).add(clamped);
          final k = keyOf(key.$1, w.id);
          // What the account stores (unclamped): the device that wrote it
          // must not send it again.
          final prev = remote[k];
          if (prev == null || UserWordSet.wins(w, prev)) remote[k] = w;
        } on Object {
          continue; // a value this version can't read
        }
      }
      if (!page.hasMore || page.items.isEmpty) break;
    }

    var changed = 0;
    final merger = UserWordStore(repo);
    for (final e in incoming.entries) {
      changed += await merger.mergeIn(e.key, UserWordSet(e.value));
    }
    for (final e in remote.entries) {
      seen[e.key] = fingerprint(e.value);
    }

    // Push every word whose version here isn't the one last exchanged.
    final push = <SyncedSetting>[];
    for (final e in (await repo.all()).entries) {
      for (final w in e.value.all) {
        final k = keyOf(e.key, w.id);
        final f = fingerprint(w);
        if (seen[k] == f) continue;
        push.add(SyncedSetting(key: k, value: jsonEncode(w.toJson()), changedAtMs: w.at.millisecondsSinceEpoch, device: device));
        seen[k] = f;
      }
    }
    for (var i = 0; i < push.length; i += 200) {
      await backend.pushSettings(push.sublist(i, i + 200 > push.length ? push.length : i + 200));
    }
    if (cursor != null) await store.set(cursorKey, cursor.encode());
    await store.set(seenKey, jsonEncode(seen));
    return changed;
  }

  @override
  Future<void> reset(SyncStore store) async {
    await store.set(cursorKey, null);
    await store.set(seenKey, null);
  }

  /// A short fingerprint of a word's version.
  static String fingerprint(UserWord w) => sha1.convert(utf8.encode(jsonEncode(w.toJson()))).toString().substring(0, 16);

  static int _compare(SyncCursor a, SyncCursor b) {
    final t = a.time.compareTo(b.time);
    return t != 0 ? t : a.id.compareTo(b.id);
  }

  static Map<String, String> _decodeSeen(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      return {for (final e in (jsonDecode(raw) as Map).entries) e.key as String: e.value as String};
    } on Object {
      return {};
    }
  }
}
