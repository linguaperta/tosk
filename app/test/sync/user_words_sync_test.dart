// Cloud sync of "my words" (`sync/user_words_sync.dart`): two devices on the
// fake server converge, last writer wins per word, deletions stay deleted,
// nothing is pushed twice, the settings sync ignores the word documents, an
// account switch or "Delete my cloud data" starts the exchange over, and the
// words' review events travel with the log like any facet.
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/data/progress/user_words.dart';
import 'package:tosk/sync/fake_sync_backend.dart';
import 'package:tosk/sync/sync_engine.dart';
import 'package:tosk/sync/sync_store.dart';
import 'package:tosk/sync/user_words_sync.dart';
import 'package:flutter_test/flutter_test.dart';

class Device {
  Device(this.server, {String? account = 'alice'})
    : progress = InMemoryProgressStore(),
      store = InMemorySyncStore(),
      words = InMemoryUserWordRepo() {
    backend = FakeSyncBackend(server, account: account);
    engine = SyncEngine(
      store: store,
      progress: progress,
      importer: progress,
      log: progress,
      backend: backend,
      syncedSettings: const {'ui.theme_mode'},
      clock: server.clock,
      extensions: [UserWordsSync(words)],
    );
    progress.listeners.onRecorded(engine.noteRecorded);
    progress.listeners.onSettingChanged(engine.noteSettingChanged);
    edits = UserWordStore(words, clock: server.clock);
  }

  final FakeSyncServer server;
  final InMemoryProgressStore progress;
  final SyncStore store;
  final InMemoryUserWordRepo words;
  late final FakeSyncBackend backend;
  late final SyncEngine engine;
  late final UserWordStore edits;

  Future<SyncResult> sync() => engine.sync();
  Future<UserWordSet> it() => words.load('it');
}

void main() {
  late DateTime now;
  late FakeSyncServer server;

  setUp(() {
    now = DateTime.utc(2026, 10, 25, 12);
    server = FakeSyncServer(clock: () => now);
  });

  void tick([Duration d = const Duration(minutes: 1)]) => now = now.add(d);

  test('a word added on one device arrives on the other; edits and deletions follow', () async {
    final a = Device(server), b = Device(server);
    final w = await a.edits.add(
      'it',
      word: 'questura',
      translation: 'police headquarters',
      example: 'Andò in questura.',
    );
    await a.edits.add('es', word: 'comisario', translation: 'inspector');
    tick();
    final r1 = await a.sync();
    expect(r1.extrasChanged, 0);
    tick();
    final r2 = await b.sync();
    expect(r2.extrasChanged, 2);
    expect(r2.changedLocal, isTrue, reason: 'the app refreshes after it');
    expect((await b.it()).live.single.example, 'Andò in questura.');
    expect((await b.words.load('es')).live.single.word, 'comisario');

    // b edits, a deletes another word; both sync.
    tick();
    await b.edits.edit('it', (await b.it())[w.id]!.copyWith(translation: 'police station'));
    final x = await a.edits.add('it', word: 'sbirro', translation: 'cop');
    tick();
    await a.sync();
    tick();
    await b.sync();
    tick();
    await a.edits.remove('it', x.id);
    tick();
    await a.sync();
    tick();
    await b.sync();
    tick();
    await a.sync();
    final sa = await a.it(), sb = await b.it();
    expect(sa[w.id]!.translation, 'police station');
    expect(sb[x.id]!.removed, isTrue);
    expect({for (final v in sa.all) v.id: v}, {for (final v in sb.all) v.id: v});
  });

  test('concurrent edits: the later one wins on both; a deletion is never undone by an older edit', () async {
    final a = Device(server), b = Device(server);
    final w = await a.edits.add('it', word: 'casa', translation: 'house');
    await a.sync();
    await b.sync();
    tick();
    await a.edits.edit('it', w.copyWith(translation: 'home')); // earlier
    tick();
    await b.edits.remove('it', w.id); // later
    await a.sync();
    await b.sync();
    await a.sync();
    expect((await a.it())[w.id]!.removed, isTrue);
    expect((await b.it())[w.id]!.removed, isTrue);
  });

  test('a tie between an edit and a deletion goes to the deletion on both devices', () async {
    final a = Device(server), b = Device(server);
    final w = await a.edits.add('it', word: 'casa', translation: 'house');
    await a.sync();
    await b.sync();
    tick();
    // Both at the same instant (the same server clock).
    await a.edits.edit('it', w.copyWith(translation: 'home'));
    await b.edits.remove('it', w.id);
    await a.sync();
    await b.sync();
    await a.sync();
    expect((await a.it())[w.id]!.removed, isTrue);
    expect((await b.it())[w.id]!.removed, isTrue);
  });

  test('nothing is pushed twice; the settings sync ignores word documents', () async {
    final a = Device(server);
    await a.edits.add('it', word: 'a', translation: 'b');
    await a.progress.setSetting('ui.theme_mode', 'dark');
    await Future<void>.delayed(Duration.zero);
    await a.sync();
    final writes = server.writes;
    tick();
    final r = await a.sync();
    expect(server.writes, writes, reason: 'no changes, no writes');
    expect(r.settingsApplied, isEmpty, reason: 'myword: keys are not settings');
    expect(await a.progress.getSetting('${UserWordsSync.keyPrefix}it:x'), isNull);
    // A fresh device joins: it gets the theme and the word, and pushes nothing back.
    final b = Device(server);
    final w0 = server.writes;
    await b.sync();
    expect(await b.progress.getSetting('ui.theme_mode'), 'dark');
    expect((await b.it()).length, 1);
    expect(server.writes, w0, reason: 'what came down is not sent back up');
  });

  test('the words travel with their review events', () async {
    final a = Device(server), b = Device(server);
    final w = await a.edits.add('it', word: 'questura', translation: 'police headquarters');
    await a.progress.record(
      ReviewEvent(
        id: 'e1',
        facetId: w.recFacet('it'),
        at: now,
        rating: Rating.good,
        exerciseType: 'flashcard',
        inputMode: InputMode.self,
        responseMs: 900,
        correct: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await a.sync();
    await b.sync();
    expect(await b.progress.state(w.recFacet('it')), isNotNull);
    expect((await b.it()).live.single.id, w.id);
  });

  test('another account or deleted cloud data: everything is exchanged again', () async {
    final a = Device(server);
    await a.edits.add('it', word: 'uno', translation: 'one');
    await a.sync();
    // Delete my cloud data, then sign in again: the words go up again.
    await a.engine.deleteRemote();
    tick();
    await a.sync();
    final b = Device(server);
    await b.sync();
    expect((await b.it()).length, 1);
    // Switch account: the words go up to the new account too.
    a.backend.account = 'bob';
    tick();
    await a.sync();
    final c = Device(server, account: 'bob');
    await c.sync();
    expect((await c.it()).live.single.word, 'uno');
  });

  test('a word dated in the future is clamped to the server time', () async {
    final a = Device(server), b = Device(server);
    final future = now.add(const Duration(days: 2));
    await a.words.put('it', [UserWord(id: 'user~f', word: 'futuro', translation: 'future', at: future)]);
    await a.sync();
    await b.sync();
    expect((await b.it())['user~f']!.at, now);
    final writes = server.writes;
    await a.sync();
    expect(server.writes, writes, reason: 'the writer does not send it again');
  });
}
