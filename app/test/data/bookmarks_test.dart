// Bookmarks: the model's last-writer-wins merge, both repos, the store's
// star / unstar / toggle / merge, and bookmarks in the progress backup.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/bookmarks.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/data/sync/progress_backup.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 10, 20, 9);

Bookmark _word(String id, {int min = 0, bool removed = false, String label = ''}) => Bookmark(
  kind: BookmarkKind.word,
  id: id,
  at: _t0.add(Duration(minutes: min)),
  label: label.isEmpty ? id : label,
  removed: removed,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('BookmarkSet', () {
    test('live entries are newest first; tombstones are not starred', () {
      final s = BookmarkSet([_word('a'), _word('b', min: 2), _word('c', min: 1, removed: true)]);
      expect(s.live.map((b) => b.id), ['b', 'a']);
      expect(s.length, 2);
      expect(s.contains(BookmarkKind.word, 'c'), isFalse);
      expect(s.contains(BookmarkKind.sentence, 'a'), isFalse);
      expect(s.all, hasLength(3));
    });

    test('merge: the later change wins, a tie goes to the removal', () {
      final mine = BookmarkSet([_word('a', min: 5), _word('b', min: 1), _word('c', min: 3)]);
      final theirs = BookmarkSet([
        _word('a', min: 1, removed: true), // older: ignored
        _word('b', min: 4, removed: true), // newer: unstarred
        _word('c', min: 3, removed: true), // tie: removal wins
        _word('d', min: 0), // new
      ]);
      final merged = mine.merge(theirs);
      expect(merged.live.map((b) => b.id).toSet(), {'a', 'd'});
      expect(mine.changesFrom(theirs).map((b) => b.id).toSet(), {'b', 'c', 'd'});
      // Merging is idempotent and commutative on what is starred.
      expect(merged.merge(theirs).live.map((b) => b.id).toSet(), {'a', 'd'});
      expect(theirs.merge(mine).live.map((b) => b.id).toSet(), {'a', 'd'});
      expect(merged.changesFrom(theirs), isEmpty);
    });

    test('JSON round trip, unknown kinds are skipped', () {
      final ex = Bookmark(
        kind: BookmarkKind.exercise,
        id: 'h1',
        at: _t0,
        label: 'Noi ___ il pane.',
        detail: 'Fill the gap',
        facetId: 'it:mangiare#form:presente',
        exercise: const {'type': 'cloze', 'id': 'x'},
      );
      final back = Bookmark.fromJson(ex.toJson())!;
      expect(back, ex);
      expect(back.exercise, {'type': 'cloze', 'id': 'x'});
      expect(Bookmark.fromJson({'k': 'video', 'id': 'v', 'at': 1}), isNull);
      expect(Bookmark.fromJson({'k': 'word', 'at': 1}), isNull);
      final tomb = Bookmark.fromJson(_word('a', removed: true).toJson())!;
      expect(tomb.removed, isTrue);
      expect(tomb.label, '');
    });
  });

  for (final (name, make) in [
    ('in memory', () async => InMemoryBookmarkRepo() as BookmarkRepo),
    ('drift', () async => DriftBookmarkRepo(ProgressDb(NativeDatabase.memory())) as BookmarkRepo),
  ]) {
    group('BookmarkStore on the $name repo', () {
      test('star, unstar, toggle; per course; strictly increasing times on a fixed clock', () async {
        final repo = await make();
        final store = BookmarkStore(repo, clock: () => _t0);
        var s = await store.add('it', _word('it:pane', label: 'il pane'));
        expect(s.contains(BookmarkKind.word, 'it:pane'), isTrue);
        s = await store.toggle('it', _word('it:pane'));
        expect(s.contains(BookmarkKind.word, 'it:pane'), isFalse);
        s = await store.toggle('it', _word('it:pane'));
        expect(s.contains(BookmarkKind.word, 'it:pane'), isTrue);
        final times = [for (final b in (await repo.load('it')).all) b.at];
        expect(times.single.isAfter(_t0), isTrue, reason: 'three changes on a fixed clock got later times');
        expect((await repo.load('nl')).isEmpty, isTrue);
        await store.remove('it', BookmarkKind.word, 'it:pane');
        final reloaded = await repo.load('it');
        expect(reloaded.isEmpty, isTrue);
        expect(reloaded.all.single.removed, isTrue, reason: 'unstarring keeps a tombstone');
        // Removing what isn't starred changes nothing.
        await store.remove('it', BookmarkKind.word, 'it:nope');
        expect((await repo.load('it')).all, hasLength(1));
      });

      test('quick concurrent toggles are serialized', () async {
        final repo = await make();
        final store = BookmarkStore(repo, clock: () => _t0);
        await Future.wait([for (var i = 0; i < 5; i++) store.toggle('it', _word('it:pane'))]);
        expect((await repo.load('it')).contains(BookmarkKind.word, 'it:pane'), isTrue, reason: 'odd count: starred');
        await Future.wait([for (var i = 0; i < 4; i++) store.add('it', _word('w$i'))]);
        expect((await repo.load('it')).length, 5);
      });

      test('mergeIn counts what changed and keeps an unstarred bookmark unstarred', () async {
        final repo = await make();
        final store = BookmarkStore(repo, clock: () => _t0.add(const Duration(hours: 1)));
        await store.add('it', _word('a'));
        await store.remove('it', BookmarkKind.word, 'a'); // unstarred at ~10:00
        final incoming = BookmarkSet([_word('a', min: 5), _word('b', min: 5)]); // starred at 9:05
        expect(await store.mergeIn('it', incoming), 1);
        final s = await repo.load('it');
        expect(s.contains(BookmarkKind.word, 'a'), isFalse);
        expect(s.contains(BookmarkKind.word, 'b'), isTrue);
        expect(await store.mergeIn('it', incoming), 0);
        expect((await repo.all()).keys, ['it']);
      });
    });
  }

  test('exercise snapshots survive the drift repo', () async {
    final repo = DriftBookmarkRepo(ProgressDb(NativeDatabase.memory()));
    await repo.put('it', [
      Bookmark(
        kind: BookmarkKind.exercise,
        id: 'h',
        at: _t0,
        label: 'p',
        facetId: 'it:pane#rec',
        exercise: const {'type': 'multiple_choice', 'options': ['a', 'b']},
      ),
    ]);
    final b = (await repo.load('it')).live.single;
    expect(b.exercise, {
      'type': 'multiple_choice',
      'options': ['a', 'b'],
    });
    expect(b.facetId, 'it:pane#rec');
  });

  group('backup', () {
    test('bookmarks (tombstones included) round-trip and merge; old backups have none', () async {
      final a = InMemoryProgressStore(scheduler: FsrsScheduler());
      final marksA = InMemoryBookmarkRepo();
      final storeA = BookmarkStore(marksA, clock: () => _t0);
      await storeA.add('it', _word('it:pane', label: 'il pane'));
      await storeA.add('it', _word('it:gatto'));
      await storeA.remove('it', BookmarkKind.word, 'it:gatto');
      await storeA.add('nl', Bookmark(kind: BookmarkKind.sentence, id: 's:9', at: _t0, label: 'Ik eet.'));

      final text = encodeBackup(await exportBackup(a, bookmarks: marksA, now: _t0));
      final lines = text.trim().split('\n').where((l) => l.contains('"kind":"bookmark"')).toList();
      expect(lines, hasLength(3));
      expect(text.split('\n').first, contains('"bookmarks":3'));

      final decoded = decodeBackup(text);
      expect(decoded.bookmarks.keys.toSet(), {'it', 'nl'});
      expect(decoded.bookmarks['it']!.all, hasLength(2));

      // Device B starred gatto later than A unstarred it: B's star stays.
      final b = ProgressRepo(ProgressDb(NativeDatabase.memory()), scheduler: FsrsScheduler());
      addTearDown(b.close);
      final marksB = InMemoryBookmarkRepo();
      await BookmarkStore(marksB, clock: () => _t0.add(const Duration(days: 1))).add('it', _word('it:gatto'));
      final report = await importBackup(decoded, store: b, importer: b, bookmarks: marksB);
      expect(report.bookmarksChanged, 2); // pane and the nl sentence
      final it = await marksB.load('it');
      expect(it.contains(BookmarkKind.word, 'it:pane'), isTrue);
      expect(it.contains(BookmarkKind.word, 'it:gatto'), isTrue);
      expect((await marksB.load('nl')).contains(BookmarkKind.sentence, 's:9'), isTrue);
      final again = await importBackup(decodeBackup(text), store: b, importer: b, bookmarks: marksB);
      expect(again.bookmarksChanged, 0);
    });

    test('chat settings are never exported nor imported', () async {
      final a = InMemoryProgressStore(scheduler: FsrsScheduler());
      await a.setSetting('chat.conversations.it', '[]');
      await a.setSetting('course.active', 'it');
      final backup = await exportBackup(a, now: _t0);
      expect(backup.settings.keys, ['course.active']);
      final b = InMemoryProgressStore(scheduler: FsrsScheduler());
      await importBackup(
        ProgressBackup(events: const [], settings: const {'chat.x': 'y', 'course.active': 'nl'}),
        store: b,
        importer: b,
      );
      expect(await b.getSetting('chat.x'), isNull);
      expect(await b.getSetting('course.active'), 'nl');
    });
  });
}
