import 'package:tosk/core/core.dart';
import 'package:collection/collection.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fakes.dart';
import 'fixtures/italian_course.dart';
import 'helpers.dart';

final _now = DateTime.utc(2026, 10, 13, 12);
const _elapsed = Duration(seconds: 10);

void main() {
  final it = italianCourse();
  late InMemoryProgressStore store;
  late DateTime clock;

  EngineSessionFactory factory({int seed = 1}) => EngineSessionFactory(
    course: it,
    store: store,
    scheduler: const FakeScheduler(),
    options: SessionOptions(sourceLang: 'en', seed: seed),
    clock: () => clock,
  );

  Future<List<OpenMistake>> open() =>
      openMistakes(store: store, course: it, scheduler: const FakeScheduler(), now: clock);

  setUp(() {
    store = InMemoryProgressStore();
    clock = _now;
  });

  Future<List<Exercise>> drive(PracticeSession s, {bool Function(int i, Exercise e)? wrong, int max = 100}) async {
    final served = <Exercise>[];
    for (var i = 0; i < max; i++) {
      final e = await s.next();
      if (e == null) break;
      served.add(e);
      await s.submit(e, (wrong?.call(i, e) ?? false) ? wrongAnswer(e) : correctAnswer(e), elapsed: _elapsed);
      clock = clock.add(const Duration(seconds: 15));
    }
    return served;
  }

  /// A mistake on [facetId] in session [session] at [at] (event + record, as the engine writes them).
  Future<void> mistake(String facetId, {required DateTime at, String session = 's1', String type = 'cloze'}) async {
    final id = 'm-$facetId-${at.millisecondsSinceEpoch}';
    await store.record(
      ReviewEvent(
        id: id,
        facetId: facetId,
        at: at,
        rating: Rating.again,
        exerciseType: type,
        inputMode: InputMode.tap,
        responseMs: 1000,
        correct: false,
        sessionId: session,
        mode: 'lesson',
      ),
    );
    await store.saveMistake(
      MistakeRecord(
        id: id,
        facetId: facetId,
        at: at,
        exerciseType: type,
        prompt: 'p',
        expected: 'e',
        given: 'g',
        skillId: it.skillsForFacet(facetId).firstOrNull,
      ),
    );
  }

  Future<void> correct(String facetId, {required DateTime at, String? session}) => store.record(
    ReviewEvent(
      id: 'c-$facetId-${at.millisecondsSinceEpoch}',
      facetId: facetId,
      at: at,
      rating: Rating.good,
      exerciseType: 'cloze',
      inputMode: InputMode.tap,
      responseMs: 1000,
      correct: true,
      sessionId: session,
      mode: 'lesson',
    ),
  );

  group('open mistakes', () {
    test('a lesson\'s mistakes stay open after the same-session re-ask', () async {
      final lesson = await factory().lesson('presente-are');
      final served = await drive(lesson, wrong: (i, e) => i == 0 || i == 2);
      final wrongFacets = {for (final m in store.mistakeList) m.facetId};
      expect(wrongFacets, isNotEmpty);
      // Every wrong facet was answered right again later in the lesson (re-ask).
      for (final f in wrongFacets) {
        expect(store.events.any((e) => e.facetId == f && e.correct && e.sessionId == lesson.id), isTrue, reason: f);
      }
      expect(served, isNotEmpty);
      final o = await open();
      expect(o.map((m) => m.record.facetId).toSet(), wrongFacets);
    });

    test('a correct answer in a later session resolves the mistake; a new mistake reopens it', () async {
      await mistake('it:pane#rec', at: _now.subtract(const Duration(days: 2)));
      await mistake('it:parlare#form:presente', at: _now.subtract(const Duration(days: 1)));
      expect((await open()).length, 2);

      // Correct in the same session: still open.
      await correct('it:pane#rec', at: _now.subtract(const Duration(days: 2, minutes: -1)), session: 's1');
      expect((await open()).map((m) => m.record.facetId), contains('it:pane#rec'));

      // Correct in a later session: resolved.
      await correct('it:pane#rec', at: _now.subtract(const Duration(hours: 5)), session: 's2');
      expect((await open()).map((m) => m.record.facetId), ['it:parlare#form:presente']);

      // Wrong again later: open again, with two records counted.
      await mistake('it:pane#rec', at: _now.subtract(const Duration(hours: 1)), session: 's3');
      final o = await open();
      final pane = o.firstWhere((m) => m.record.facetId == 'it:pane#rec');
      expect(pane.count, 2);
      expect(pane.record.at, _now.subtract(const Duration(hours: 1)));
    });

    test('order: still weak first, then most recent first; unknown facets skipped', () async {
      await mistake('it:pane#rec', at: _now.subtract(const Duration(days: 3)));
      await mistake('it:ragazzo#rec', at: _now.subtract(const Duration(days: 2)));
      await mistake('it:parlare#form:presente', at: _now.subtract(const Duration(days: 1)));
      await mistake('it:nonesiste#rec', at: _now.subtract(const Duration(hours: 1)));
      // ragazzo was strengthened since (in the same session, so the mistake stays open but recall is high).
      store.seed(stateWith('it:ragazzo#rec', stability: 400, now: _now, ago: const Duration(hours: 1)));
      final o = await open();
      expect(o.map((m) => m.record.facetId), ['it:parlare#form:presente', 'it:pane#rec', 'it:ragazzo#rec']);
      expect(o.first.recall, lessThan(kMistakeWeakRecall));
      expect(o.last.recall, greaterThanOrEqualTo(kMistakeWeakRecall));
    });
  });

  group('review session', () {
    test('nothing open: an empty session', () async {
      final s = await factory().review();
      expect(s.mode, SessionMode.review);
      expect(s.plannedLength, 0);
      expect(await s.next(), isNull);
    });

    test('serves the open mistakes in order, with the missed type, and resolves them', () async {
      await mistake('it:parlare#form:presente', at: _now.subtract(const Duration(days: 1)), type: 'conj_grid');
      await mistake('it:mangiare#form:presente', at: _now.subtract(const Duration(days: 2)), type: 'cloze');
      final s = await factory().review();
      expect(s.plannedLength, 2);
      final served = await drive(s);
      expect(served.map((e) => e.facetId), ['it:parlare#form:presente', 'it:mangiare#form:presente']);
      expect(served.map((e) => e.type), [ExerciseType.conjGrid, ExerciseType.cloze]);
      expect(store.events.where((e) => e.sessionId == s.id).every((e) => e.mode == 'review'), isTrue);
      expect(await open(), isEmpty);
      expect((await factory().review()).plannedLength, 0);
    });

    test('wrong again in review: re-asked in the session and still open afterwards', () async {
      await mistake('it:parlare#form:presente', at: _now.subtract(const Duration(days: 1)));
      final s = await factory().review();
      final served = await drive(s, wrong: (i, e) => i == 0);
      expect(served.length, greaterThan(1));
      expect(served.every((e) => e.facetId == 'it:parlare#form:presente'), isTrue);
      final o = await open();
      expect(o.single.record.facetId, 'it:parlare#form:presente');
      expect(o.single.count, 2);
    });

    test('a missed type that cannot serve the facet falls back to the selector', () async {
      // conj_pick never serves a #rec facet; flashcards are not repeated as such either.
      await mistake('it:pane#rec', at: _now.subtract(const Duration(days: 1)), type: 'conj_pick');
      await mistake('it:ragazzo#rec', at: _now.subtract(const Duration(days: 2)), type: 'flashcard');
      final s = await factory().review();
      final served = await drive(s);
      expect(served.map((e) => e.facetId).take(2), ['it:pane#rec', 'it:ragazzo#rec']);
      expect(served.first.type, isNot(ExerciseType.conjPick));
    });

    test('length caps the session', () async {
      for (final (i, f) in ['it:pane#rec', 'it:ragazzo#rec', 'it:parlare#form:presente'].indexed) {
        await mistake(f, at: _now.subtract(Duration(hours: i + 1)));
      }
      final s = await factory().review(length: 2);
      expect(s.plannedLength, 2);
      expect((await drive(s)).length, 2);
      expect((await open()).length, 1);
    });
  });
}
