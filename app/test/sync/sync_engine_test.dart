import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/progression/calendar.dart';
import 'package:tosk/progression/streaks.dart';
import 'package:tosk/sync/fake_sync_backend.dart';
import 'package:tosk/sync/sync_engine.dart';
import 'package:tosk/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/sample_log.dart';

const synced = {'ui.theme_mode', 'course.active', 'courses.added', 'lesson.default_length'};

/// One device: a progress store, its sync store and an engine on [server].
class Device {
  Device(
    this.server, {
    String? account = 'alice',
    Duration offset = Duration.zero,
    this.skew = Duration.zero,
    bool listen = true,
  })
      : progress = InMemoryProgressStore(),
        store = InMemorySyncStore() {
    backend = FakeSyncBackend(server, account: account);
    engine = SyncEngine(
      store: store,
      progress: progress,
      importer: progress,
      log: progress,
      backend: backend,
      syncedSettings: synced,
      unionKeys: const {'courses.added'},
      clock: () => server.clock().add(skew),
      offsets: EventOffsets(fallback: (_) => offset),
      batchSize: 100,
    );
    if (listen) {
      progress.listeners.onRecorded(engine.noteRecorded);
      progress.listeners.onSettingChanged(engine.noteSettingChanged);
    }
  }

  final FakeSyncServer server;
  final InMemoryProgressStore progress;
  final SyncStore store;
  final Duration skew;
  late final FakeSyncBackend backend;
  late final SyncEngine engine;

  Future<void> recordAll(Iterable<ReviewEvent> events) async {
    for (final e in events) {
      await progress.record(e);
    }
    await pumpListeners();
  }

  Future<SyncResult> sync() => engine.sync();
}

/// The listeners are fire-and-forget; let their writes land.
Future<void> pumpListeners() => Future<void>.delayed(Duration.zero);

ReviewEvent ev(String id, String facet, DateTime at, {Rating rating = Rating.good}) => ReviewEvent(
      id: id,
      facetId: facet,
      at: at,
      rating: rating,
      exerciseType: 'flashcard',
      inputMode: InputMode.self,
      responseMs: 1000,
      correct: rating != Rating.again,
    );

Future<Map<String, FacetState>> statesOf(ProgressStore s) async => {for (final x in await s.allStates()) x.facetId: x};

/// The states a single store gets from [events] in one replay.
Future<Map<String, FacetState>> reference(Iterable<ReviewEvent> events) async {
  final s = InMemoryProgressStore();
  await s.importEvents(events);
  await s.rebuildStates();
  return statesOf(s);
}

void main() {
  late DateTime now;
  late FakeSyncServer server;

  setUp(() {
    now = DateTime.utc(2026, 10, 1, 12);
    server = FakeSyncServer(clock: () => now);
  });

  group('review log', () {
    test('two devices converge; duplicates are merged by id', () async {
      final log = sampleLog(seed: 5, count: 300);
      final a = Device(server), b = Device(server);
      await a.recordAll(log.sublist(0, 180));
      await b.recordAll(log.sublist(120)); // 60 events on both (e.g. a backup import)
      final r1 = await a.sync();
      expect(r1.pushed, 180);
      expect(r1.imported, 0);
      final r2 = await b.sync();
      expect(r2.imported, 120);
      expect(r2.pushed, 120); // the 60 shared ones came down from a's batches

      await a.sync();
      expect((await a.progress.log()).length, 300);
      expect((await b.progress.log()).length, 300);
      expect(await statesOf(a.progress), await reference(log));
      expect(await statesOf(b.progress), await statesOf(a.progress));
      expect(server.eventIds('alice').length, 300);
    });

    test('a second run is idempotent: nothing is re-sent', () async {
      final a = Device(server);
      await a.recordAll(sampleLog(count: 250));
      expect((await a.sync()).pushed, 250);
      final writes = server.writes;
      final again = await a.sync();
      expect(again.pushed, 0);
      expect(again.imported, 0);
      expect(server.writes, writes);
      expect(await a.engine.pending(), 0);
    });

    test('pulled events are not uploaded again', () async {
      final a = Device(server), b = Device(server);
      await a.recordAll(sampleLog(count: 120));
      await a.sync();
      final r = await b.sync();
      expect(r.imported, 120);
      expect(r.pushed, 0);
      expect(server.batchCount('alice'), 2); // 100 + 20 from a
    });

    test('offline: answers queue up and go out when the network is back', () async {
      final a = Device(server), b = Device(server);
      final log = sampleLog(seed: 9, count: 200);
      await a.recordAll(log.sublist(0, 50));
      server.offline = true;
      await expectLater(a.sync(), throwsA(isA<FakeOfflineException>()));
      await a.recordAll(log.sublist(50));
      expect(await a.engine.pending(), 200);
      server.offline = false;
      final r = await a.sync();
      expect(r.pushed, 200);
      expect(await a.engine.pending(), 0);
      await b.sync();
      expect(await statesOf(b.progress), await reference(log));
    });

    test('a batch stored but not acknowledged is not duplicated by the retry', () async {
      final a = Device(server);
      final flaky = _AckLosingBackend(FakeSyncBackend(server, account: 'alice'));
      a.engine.backend = flaky;
      await a.recordAll(sampleLog(count: 100));
      await expectLater(a.sync(), throwsA(isA<StateError>()));
      expect(server.batchCount('alice'), 1);
      expect(await a.engine.pending(), 100); // the position did not move
      flaky.loseNext = false;
      final r = await a.sync();
      expect(r.pushed, 0); // the pull found them in the account
      expect(await a.engine.pending(), 0);
      expect(server.batchCount('alice'), 1);
      expect(server.eventIds('alice').length, 100);
    });

    test('a resent batch has the same id, so it overwrites itself', () async {
      final ids = [for (var i = 0; i < 5; i++) 'e$i'];
      expect(SyncEngine.batchIdFor(ids), SyncEngine.batchIdFor(List.of(ids)));
      expect(SyncEngine.batchIdFor(ids), isNot(SyncEngine.batchIdFor(ids.reversed)));
      final backend = FakeSyncBackend(server, account: 'alice');
      final events = [for (final id in ids) SyncedEvent(ev(id, 'it:w1#rec', now), 120)];
      await backend.pushEvents(SyncEngine.batchIdFor(ids), 'd', events);
      await backend.pushEvents(SyncEngine.batchIdFor(ids), 'd', events);
      expect(server.batchCount('alice'), 1);
    });

    test('out-of-order events from another device replay to the same states', () async {
      // b's answers are older than a's latest on the same facets.
      final base = DateTime.utc(2026, 9, 1);
      final aEvents = [for (var i = 0; i < 20; i++) ev('a$i', 'it:w${i % 3}#rec', base.add(Duration(hours: 10 * i + 5)))];
      final bEvents = [
        for (var i = 0; i < 20; i++)
          ev('b$i', 'it:w${i % 3}#rec', base.add(Duration(hours: 10 * i)), rating: i.isEven ? Rating.again : Rating.easy),
      ];
      final a = Device(server), b = Device(server);
      await a.recordAll(aEvents);
      await b.recordAll(bEvents);
      await a.sync();
      await b.sync();
      await a.sync();
      final want = await reference([...aEvents, ...bEvents]);
      expect(await statesOf(a.progress), want);
      expect(await statesOf(b.progress), want);
    });

    test('an override arriving before its target applies once the target arrives', () async {
      final t = DateTime.utc(2026, 9, 2, 8);
      final wrong = ev('w1', 'it:w1#prod', t, rating: Rating.again);
      final override = ReviewEvent(
        id: 'o1',
        facetId: 'it:w1#prod',
        at: t.add(const Duration(minutes: 1)),
        rating: Rating.good,
        exerciseType: kOverrideType,
        inputMode: InputMode.self,
        responseMs: 0,
        correct: true,
        answer: 'w1',
      );
      final a = Device(server), b = Device(server);
      await b.progress.importEvents([override]); // e.g. from a backup
      await b.sync();
      await a.recordAll([wrong]);
      await a.sync();
      await b.sync();
      final want = await reference([wrong, override]);
      expect(await statesOf(b.progress), want);
      await a.sync();
      expect(await statesOf(a.progress), want);
    });

    test('clock skew: future timestamps are clamped to the server time, the same on every device', () async {
      final fast = Device(server, skew: const Duration(days: 2)); // clock two days ahead
      final slightlyFast = Device(server, skew: const Duration(minutes: 3));
      final c = Device(server), d = Device(server);
      await fast.recordAll([ev('f1', 'it:w1#rec', now.add(const Duration(days: 2)))]);
      await slightlyFast.recordAll([ev('s1', 'it:w2#rec', now.add(const Duration(minutes: 3)))]);
      await fast.sync();
      await slightlyFast.sync();
      now = now.add(const Duration(hours: 1));
      await c.sync();
      await d.sync();
      final logC = {for (final e in await c.progress.log()) e.id: e.at};
      final logD = {for (final e in await d.progress.log()) e.id: e.at};
      expect(logC, logD);
      expect(logC['f1']!.isAfter(DateTime.utc(2026, 10, 1, 12, 1)), isFalse); // clamped to ~upload time
      expect(logC['f1']!.difference(DateTime.utc(2026, 10, 1, 12)).inSeconds.abs(), lessThan(1));
      expect(logC['s1'], DateTime.utc(2026, 10, 1, 12, 3)); // within tolerance: kept
      expect(await statesOf(c.progress), await statesOf(d.progress));
    });

    test('works on the drift progress database and the SQLite sync store (rowid queue)', () async {
      final repo = ProgressRepo(ProgressDb(NativeDatabase.memory()));
      final syncDb = SyncDb(NativeDatabase.memory());
      final store = DriftSyncStore(syncDb);
      addTearDown(() async {
        await repo.close();
        await store.close();
      });
      final engine = SyncEngine(
        store: store,
        progress: repo,
        importer: repo,
        log: repo,
        backend: FakeSyncBackend(server, account: 'alice'),
        syncedSettings: synced,
        clock: () => now,
        offsets: EventOffsets(fallback: (_) => const Duration(hours: 2)),
        batchSize: 64,
      );
      repo.listeners.onRecorded(engine.noteRecorded);
      final log = sampleLog(seed: 3, count: 400);
      for (final e in log.sublist(0, 200)) {
        await repo.record(e);
      }
      await pumpListeners();
      final other = Device(server);
      await other.recordAll(log.sublist(200));
      await other.sync();
      final r = await engine.sync();
      expect(r.pushed, 200);
      expect(r.imported, 200);
      expect(await engine.pending(), 0);
      expect((await engine.sync()).pushed, 0);
      final mine = await store.meta([log.first.id]);
      expect(mine[log.first.id]!.offsetMinutes, 120);
      expect(mine[log.first.id]!.uploaded, isTrue);
      expect(await statesOf(repo), await reference(log));
      // Offsets of pulled events are kept with their event times.
      final offs = await store.offsets();
      expect(offs.length, {for (final e in log) e.at}.length); // keyed by time (the log has ties)
    });

    test('another account starts over; deleting the cloud data keeps local progress', () async {
      final a = Device(server);
      await a.recordAll(sampleLog(count: 80));
      await a.sync();
      a.backend.account = 'bob';
      expect((await a.sync()).pushed, 80); // everything goes to the new account too
      expect(server.eventIds('bob').length, 80);
      await a.engine.deleteRemote();
      expect(server.eventIds('bob'), isEmpty);
      expect((await a.progress.log()).length, 80);
      expect(server.eventIds('alice').length, 80);
    });

    test('free-tier budget: a 200-answer day costs a handful of writes', () async {
      // Ten lessons of 20 answers on one phone, syncing after each lesson
      // and on two more app pauses/resumes per lesson; a tablet syncs hourly.
      final phone = Device(server), tablet = Device(server);
      final log = sampleLog(seed: 11, count: 200);
      now = DateTime.utc(2026, 10, 2, 7);
      for (var lesson = 0; lesson < 10; lesson++) {
        await phone.recordAll(log.sublist(lesson * 20, lesson * 20 + 20));
        for (var i = 0; i < 3; i++) {
          await phone.sync();
          now = now.add(const Duration(minutes: 10));
        }
        if (lesson.isEven) await tablet.sync();
        now = now.add(const Duration(minutes: 30));
      }
      await tablet.sync();
      expect(server.eventIds('alice').length, 200);
      expect((await tablet.progress.log()).length, 200);
      expect(server.writes, lessThanOrEqualTo(10)); // one batch per lesson, nothing for empty runs
      expect(server.reads, lessThan(150)); // incremental pulls (plus the short overlap)
    });

    test('signed out: nothing happens', () async {
      final a = Device(server, account: null);
      await a.recordAll(sampleLog(count: 10));
      expect((await a.sync()).skipped, isTrue);
      expect(server.writes, 0);
    });
  });

  group('time zones', () {
    test('streaks use the offset each answer was recorded with', () async {
      // Practice once a day: three late evenings in Amsterdam (UTC+2, 23:30)
      // on the phone, then three early mornings in Tokyo (UTC+9, 07:00) on a
      // tablet. Viewed on a laptop in New York (UTC-4).
      now = DateTime.utc(2026, 10, 7);
      final amsterdam = Device(server, offset: const Duration(hours: 2));
      final tokyo = Device(server, offset: const Duration(hours: 9));
      final laptop = Device(server, offset: const Duration(hours: -4));
      for (var d = 0; d < 3; d++) {
        // 23:30 in Amsterdam on Oct 1+d = 21:30 UTC.
        await amsterdam.recordAll([ev('ams$d', 'it:w1#rec', DateTime.utc(2026, 10, 1 + d, 21, 30))]);
      }
      for (var d = 3; d < 6; d++) {
        // 07:00 in Tokyo on Oct 1+d = 22:00 UTC the day before.
        await tokyo.recordAll([ev('tyo$d', 'it:w2#rec', DateTime.utc(2026, 10, d, 22))]);
      }
      await amsterdam.sync();
      await tokyo.sync();
      await laptop.sync();
      final events = await laptop.progress.log();
      expect(events.length, 6);

      final recorded = LocalCalendar(laptop.engine.offsets.offsetAt);
      final days = dayCountsOf(events, recorded);
      expect(days.keys.toSet(), {for (var d = 1; d <= 6; d++) LocalDate(2026, 10, d)});
      final streak = computeStreak(days, today: LocalDate(2026, 10, 6));
      expect(streak.current, 6);
      expect(streak.practicedToday, isTrue);

      // In the laptop's own zone, Oct 3 in Amsterdam (17:30) and Oct 4 in
      // Tokyo (18:00 on Oct 3) fall on one day, and Oct 6 looks unpracticed.
      final naive = dayCountsOf(events, LocalCalendar.fixed(const Duration(hours: -4)));
      expect(naive.length, lessThan(6));
      expect(computeStreak(naive, today: LocalDate(2026, 10, 6)).current, lessThan(6));
    });

    test('a device that travels keeps the day each answer was given', () async {
      now = DateTime.utc(2026, 10, 3);
      var zone = const Duration(hours: 2);
      final phone = Device(server, listen: false);
      final travelling = SyncEngine(
        store: phone.store,
        progress: phone.progress,
        importer: phone.progress,
        log: phone.progress,
        backend: phone.backend,
        syncedSettings: synced,
        clock: () => now,
        offsets: EventOffsets(fallback: (_) => zone),
      );
      // 00:30 on Oct 2 in Amsterdam (22:30 UTC Oct 1) ...
      final e1 = ev('t1', 'it:w1#rec', DateTime.utc(2026, 10, 1, 22, 30));
      await phone.progress.record(e1);
      await travelling.noteRecorded(e1);
      // ... then flies to New York (UTC-4).
      zone = const Duration(hours: -4);
      final cal = LocalCalendar(travelling.offsets.offsetAt);
      expect(cal.dateOf(e1.at), LocalDate(2026, 10, 2)); // as recorded
      expect(cal.dateOf(DateTime.utc(2026, 10, 1, 22, 30, 1)), LocalDate(2026, 10, 1)); // other instants: local rules
      await travelling.sync();
      expect(server.eventIds('alice'), {'t1'});
      // A fresh device learns the recorded offset from the account.
      final other = Device(server, offset: const Duration(hours: -7));
      await other.sync();
      expect(LocalCalendar(other.engine.offsets.offsetAt).dateOf(e1.at), LocalDate(2026, 10, 2));
    });
  });

  group('settings (last writer wins)', () {
    test('the later change wins, whichever device syncs last', () async {
      final a = Device(server), b = Device(server);
      await a.sync();
      await b.sync();
      await a.progress.setSetting('ui.theme_mode', 'dark');
      await pumpListeners();
      now = now.add(const Duration(minutes: 1));
      await b.progress.setSetting('ui.theme_mode', 'light');
      await pumpListeners();
      now = now.add(const Duration(minutes: 1));
      await b.sync(); // the newer change first
      await a.sync(); // a's older change loses
      await b.sync();
      expect(await a.progress.getSetting('ui.theme_mode'), 'light');
      expect(await b.progress.getSetting('ui.theme_mode'), 'light');
      expect(server.settings('alice')['ui.theme_mode'], 'light');
    });

    test('the later change wins when the older one reaches the server first', () async {
      final a = Device(server), b = Device(server);
      await a.sync();
      await b.sync();
      await a.progress.setSetting('lesson.default_length', 'quick');
      await pumpListeners();
      await a.sync();
      now = now.add(const Duration(minutes: 5));
      await b.progress.setSetting('lesson.default_length', 'long');
      await pumpListeners();
      final r = await b.sync();
      expect(r.settingsApplied, isEmpty); // b's own change is newer
      await a.sync();
      expect(await a.progress.getSetting('lesson.default_length'), 'long');
    });

    test('clearing a setting syncs; device-only keys never leave the device', () async {
      final a = Device(server), b = Device(server);
      await a.progress.setSetting('ui.theme_mode', 'dark');
      await a.progress.setSetting('reminder.time', '08:00');
      await pumpListeners();
      await a.sync();
      await b.sync();
      expect(await b.progress.getSetting('ui.theme_mode'), 'dark');
      expect(await b.progress.getSetting('reminder.time'), isNull);
      expect(server.settings('alice').containsKey('reminder.time'), isFalse);
      now = now.add(const Duration(minutes: 1));
      await b.progress.setSetting('ui.theme_mode', null);
      await pumpListeners();
      await b.sync();
      await a.sync();
      expect(await a.progress.getSetting('ui.theme_mode'), isNull);
    });

    test('a device joining an account adopts its settings; "my courses" become the union', () async {
      final a = Device(server);
      await a.progress.setSetting('course.active', 'it');
      await a.progress.setSetting('courses.added', 'it,nl');
      await a.progress.setSetting('ui.theme_mode', 'dark');
      await pumpListeners();
      await a.sync();
      now = now.add(const Duration(hours: 1));
      // A fresh install: picked Spanish, light theme, before signing in.
      final b = Device(server);
      await b.progress.setSetting('course.active', 'es');
      await b.progress.setSetting('courses.added', 'es');
      await b.progress.setSetting('ui.theme_mode', 'light');
      await b.progress.setSetting('lesson.default_length', 'long'); // not in the account yet
      await pumpListeners();
      final r = await b.sync();
      expect(r.settingsApplied, containsAll(['course.active', 'ui.theme_mode', 'courses.added']));
      expect(await b.progress.getSetting('course.active'), 'it');
      expect(await b.progress.getSetting('ui.theme_mode'), 'dark');
      expect(await b.progress.getSetting('courses.added'), 'it,nl,es');
      await a.sync();
      expect(await a.progress.getSetting('courses.added'), 'it,nl,es');
      expect(await a.progress.getSetting('lesson.default_length'), 'long');
      // After joining, it's plain LWW again (removing a course syncs).
      now = now.add(const Duration(minutes: 1));
      await a.progress.setSetting('courses.added', 'it');
      await pumpListeners();
      await a.sync();
      await b.sync();
      expect(await b.progress.getSetting('courses.added'), 'it');
    });

    test('a device whose clock is far ahead does not win forever', () async {
      final fast = Device(server, skew: const Duration(days: 365));
      final normal = Device(server);
      await fast.sync();
      await normal.sync();
      await fast.progress.setSetting('ui.theme_mode', 'dark'); // stamped a year ahead
      await pumpListeners();
      await fast.sync(); // the server receives it now
      now = now.add(const Duration(minutes: 10));
      await normal.progress.setSetting('ui.theme_mode', 'light'); // really later
      await pumpListeners();
      await normal.sync();
      expect(await normal.progress.getSetting('ui.theme_mode'), 'light');
    });

    test('changes made without the listener are still detected', () async {
      final a = Device(server, listen: false), b = Device(server);
      await a.sync();
      await b.sync();
      now = now.add(const Duration(minutes: 1));
      await a.progress.setSetting('ui.theme_mode', 'dark'); // e.g. written before sync was set up
      await a.sync();
      await b.sync();
      expect(await b.progress.getSetting('ui.theme_mode'), 'dark');
    });
  });
}

/// Stores the batch, then fails as if the acknowledgement was lost.
class _AckLosingBackend implements SyncBackend {
  _AckLosingBackend(this.inner);
  final FakeSyncBackend inner;
  bool loseNext = true;

  @override
  String get id => inner.id;
  @override
  bool get isConfigured => inner.isConfigured;
  @override
  String? get accountId => inner.accountId;
  @override
  Future<void> pushEvents(String batchId, String device, List<SyncedEvent> events) async {
    await inner.pushEvents(batchId, device, events);
    if (loseNext) throw StateError('connection lost after the write');
  }

  @override
  Future<SyncPage<EventBatch>> pullEvents({SyncCursor? after, int limit = 50}) =>
      inner.pullEvents(after: after, limit: limit);
  @override
  Future<void> pushSettings(List<SyncedSetting> settings) => inner.pushSettings(settings);
  @override
  Future<SyncPage<SyncedSetting>> pullSettings({SyncCursor? after, int limit = 200}) =>
      inner.pullSettings(after: after, limit: limit);
  @override
  Future<void> deleteAll() => inner.deleteAll();
}
