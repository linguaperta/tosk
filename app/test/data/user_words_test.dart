// "My words": the model and its last-writer-wins merge, the store (add, edit,
// delete with a tombstone, undo, merge), the drift and in-memory repos, and
// the backup round trip between two on-disk progress databases (with the
// facets' review events and a deleted word that must stay deleted).
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/data/progress/user_words.dart';
import 'package:tosk/data/sync/progress_backup.dart';
import 'package:flutter_test/flutter_test.dart';

final _t = DateTime.utc(2026, 10, 25, 9);

UserWord _w(String id, String word, {int at = 0, bool removed = false, String tr = 'meaning'}) {
  final w = UserWord(
    id: 'user~$id',
    word: word,
    translation: tr,
    at: _t.add(Duration(seconds: at)),
  );
  return removed ? w.tombstone(w.at) : w;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('model', () {
    test('ids are namespaced apart from pack ids', () {
      final w = _w('1', 'commissario');
      expect(w.itemId('it'), 'it:user~1');
      expect(w.recFacet('it'), 'it:user~1#rec');
      expect(w.prodFacet('it'), 'it:user~1#prod');
      expect(FacetId.parse(w.prodFacet('it')).courseId, 'it');
      expect(isUserFacetId(w.recFacet('it')), isTrue);
      expect(isUserFacetId('it:mangiare#rec'), isFalse);
      expect(isUserItemId('it:pane'), isFalse);
    });

    test('JSON round trip; tombstones keep only their identity', () {
      final w = UserWord(
        id: 'user~x',
        word: 'questura',
        translation: 'police headquarters',
        note: 'Montalbano',
        example: 'Andò in questura.',
        lemmaId: 'it:questura',
        pos: 'noun',
        lang: 'en',
        at: _t,
        created: _t.subtract(const Duration(days: 1)),
      );
      expect(UserWord.fromJson(w.toJson()), w);
      final gone = w.tombstone(_t.add(const Duration(minutes: 1)));
      final j = gone.toJson();
      expect(j['del'], true);
      expect(j.containsKey('word'), isFalse);
      expect(UserWord.fromJson(j)!.removed, isTrue);
      expect(UserWord.fromJson({'id': 'it:pane', 'at': 1, 'word': 'a', 'tr': 'b'}), isNull, reason: 'not a user id');
      expect(UserWord.fromJson({'id': 'user~a', 'at': 1}), isNull, reason: 'no word');
    });

    test('meanings split on commas and semicolons', () {
      expect(_w('a', 'x', tr: 'to go, to walk; to leave').meanings, ['to go', 'to walk', 'to leave']);
    });

    test('merge: the later change wins, a tie goes to the deletion, the same both ways', () {
      final mine = UserWordSet([_w('a', 'casa', at: 1), _w('b', 'gatto', at: 5)]);
      final theirs = UserWordSet([
        _w('a', 'casetta', at: 2), // newer edit
        _w('b', 'gatto', at: 5, removed: true), // a deletion at the same time
        _w('c', 'cane', at: 3), // new
      ]);
      final merged = mine.merge(theirs);
      expect(merged['user~a']!.word, 'casetta');
      expect(merged['user~b']!.removed, isTrue);
      expect(merged['user~c']!.word, 'cane');
      expect(merged.live.map((w) => w.word), ['cane', 'casetta']);
      final other = theirs.merge(mine);
      expect({for (final w in other.all) w.id: w}, {for (final w in merged.all) w.id: w});
      expect(mine.changesFrom(theirs).map((w) => w.id).toSet(), {'user~a', 'user~b', 'user~c'});
      expect(merged.changesFrom(theirs), isEmpty);
      // An older edit never wins over a deletion.
      final old = UserWordSet([_w('b', 'gatto', at: 4)]);
      expect(merged.merge(old)['user~b']!.removed, isTrue);
    });
  });

  for (final kind in ['memory', 'drift']) {
    group('store over $kind', () {
      late UserWordRepo repo;
      late UserWordStore store;
      var now = _t;
      setUp(() {
        if (kind == 'memory') {
          repo = InMemoryUserWordRepo();
        } else {
          final db = ProgressDb(NativeDatabase.memory());
          addTearDown(db.close);
          repo = DriftUserWordRepo(db);
        }
        now = _t;
        store = UserWordStore(repo, clock: () => now);
      });

      test('add, edit, delete (a tombstone) and undo', () async {
        final a = await store.add(
          'it',
          word: ' questura ',
          translation: 'police station',
          note: '  ',
          example: 'In questura.',
        );
        expect(a.id, startsWith(kUserWordPrefix));
        expect(a.word, 'questura');
        expect(a.note, isNull, reason: 'blank notes are dropped');
        final b = await store.add('it', word: 'sbirro', translation: 'cop');
        expect(b.at.isAfter(a.at), isTrue, reason: 'a fixed clock still orders changes');
        var set = await store.load('it');
        expect(set.live.map((w) => w.word), ['sbirro', 'questura']);

        set = await store.edit('it', set[a.id]!.copyWith(translation: 'police headquarters'));
        expect(set[a.id]!.translation, 'police headquarters');
        expect(set[a.id]!.created, a.created, reason: 'editing keeps when it was added');

        set = await store.remove('it', b.id);
        expect(set.live.map((w) => w.word), ['questura']);
        expect(set[b.id]!.removed, isTrue);
        expect((await store.remove('it', b.id))[b.id]!.at, set[b.id]!.at, reason: 'deleting twice changes nothing');

        set = await store.restore('it', b);
        expect(set.live.map((w) => w.word), ['sbirro', 'questura']);
        expect((await repo.load('nl')).all, isEmpty, reason: 'per course');
      });

      test('quick changes are serialized; mergeIn counts what changed', () async {
        await Future.wait([for (var i = 0; i < 10; i++) store.add('it', word: 'w$i', translation: 't$i')]);
        final set = await store.load('it');
        expect(set.length, 10);
        final incoming = UserWordSet([
          set.live.first.copyWith(at: set.live.first.at.add(const Duration(hours: 1)), translation: 'new'),
          _w('zzz', 'nuova', at: 100),
        ]);
        expect(await store.mergeIn('it', incoming), 2);
        expect(await store.mergeIn('it', incoming), 0, reason: 'idempotent');
        expect((await store.load('it')).length, 11);
      });

      test('onChanged fires for local changes, not for merges', () async {
        var calls = 0;
        final s = UserWordStore(repo, clock: () => now, onChanged: () => calls++);
        final w = await s.add('it', word: 'a', translation: 'b');
        await s.remove('it', w.id);
        expect(calls, 2);
        await s.mergeIn('it', UserWordSet([_w('m', 'merged', at: 999)]));
        expect(calls, 2);
      });
    });
  }

  group('backup', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('tosk-words-'));
    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    Future<(ProgressRepo, DriftUserWordRepo)> open(String name) async {
      final repo = ProgressRepo(
        ProgressDb(NativeDatabase(File('${dir.path}/$name.sqlite'))),
        scheduler: FsrsScheduler(),
      );
      addTearDown(repo.close);
      return (repo, DriftUserWordRepo(repo.db));
    }

    test('round trip with the review events; a deletion survives; a second import changes nothing', () async {
      final (a, wordsA) = await open('a');
      final storeA = UserWordStore(wordsA, clock: () => _t);
      final w1 = await storeA.add(
        'it',
        word: 'questura',
        translation: 'police headquarters',
        example: 'Andò in questura.',
      );
      final w2 = await storeA.add('it', word: 'sbirro', translation: 'cop');
      await storeA.remove('it', w2.id);
      await storeA.add('es', word: 'comisario', translation: 'inspector');
      await a.record(
        ReviewEvent(
          id: 'ev1',
          facetId: w1.recFacet('it'),
          at: _t,
          rating: Rating.good,
          exerciseType: 'flashcard',
          inputMode: InputMode.self,
          responseMs: 1000,
          correct: true,
        ),
      );
      await a.setSetting('reading.texts.it', '[]');

      final exported = await exportBackup(a, userWords: wordsA, now: _t);
      final text = encodeBackup(exported, now: _t);
      expect(text, contains('"kind":"user_word"'));
      expect(text, isNot(contains('reading.texts')), reason: 'saved texts stay on the device');
      final header = text.split('\n').first;
      expect(header, contains('"user_words":3'));

      // Another device already has the deleted word (older): the deletion wins.
      final (b, wordsB) = await open('b');
      await wordsB.put('it', [w2.copyWith(at: w2.at.subtract(const Duration(hours: 1)))]);
      final decoded = decodeBackup(text);
      expect(decoded.userWords.keys.toSet(), {'it', 'es'});
      final report = await importBackup(decoded, store: b, importer: b, userWords: wordsB);
      expect(report.userWordsChanged, 3);
      expect(report.eventsAdded, 1);
      final it = await wordsB.load('it');
      expect(it.live.single.word, 'questura');
      expect(it.live.single.example, 'Andò in questura.');
      expect(it[w2.id]!.removed, isTrue);
      expect((await wordsB.load('es')).live.single.word, 'comisario');
      expect((await b.state(w1.recFacet('it'))), isNotNull, reason: 'the word keeps its scheduling');

      final again = await importBackup(decodeBackup(text), store: b, importer: b, userWords: wordsB);
      expect(again.userWordsChanged, 0);
      expect(again.eventsAdded, 0);
    });

    test('a file from an older app (no user_word lines) imports; unknown words are skipped', () async {
      final (b, wordsB) = await open('c');
      final old =
          '{"format":"tosk-backup/1","exported_at":"2026-10-01T00:00:00Z","counts":{"events":0}}\n'
          '{"kind":"user_word","course":"it","id":"not-a-user-id","at":1,"word":"a","tr":"b"}\n';
      final report = await importBackup(decodeBackup(old), store: b, importer: b, userWords: wordsB);
      expect(report.userWordsChanged, 0);
      expect(await wordsB.all(), isEmpty);
    });
  });
}
