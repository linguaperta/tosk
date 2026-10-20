// "Practice starred" (engine/session/starred.dart): starred exercises are
// replayed, starred words train their facets, starred sentences the facets of
// their words (the sentence preferred).
import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart' as data;
import 'package:tosk/engine/engine.dart';
import 'package:tosk/feedback/exercise_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/italian_course.dart';
import 'helpers.dart';

final _now = DateTime.utc(2026, 10, 20, 12);

void main() {
  final it = italianCourse();
  final scheduler = FsrsScheduler();
  late data.InMemoryProgressStore store;
  late DateTime clock;

  EngineSessionFactory factory({int seed = 1}) => EngineSessionFactory(
    course: it,
    store: store,
    scheduler: scheduler,
    options: SessionOptions(sourceLang: 'en', seed: seed),
    clock: () => clock,
  );

  setUp(() {
    store = data.InMemoryProgressStore(scheduler: scheduler);
    clock = _now;
  });

  Future<List<Exercise>> drive(PracticeSession s, {int max = 100}) async {
    final served = <Exercise>[];
    for (var i = 0; i < max; i++) {
      final e = await s.next();
      if (e == null) break;
      served.add(e);
      await s.submit(e, correctAnswer(e), elapsed: const Duration(seconds: 5));
      clock = clock.add(const Duration(seconds: 10));
    }
    return served;
  }

  test('nothing starred: an empty session', () async {
    final s = await factory().starred(const StarredPractice());
    expect(s.plannedLength, 0);
    expect(await s.next(), isNull);
  });

  test('a starred exercise is served again as it was, in mode starred', () async {
    final lesson = await factory().lesson('saluti');
    final original = (await lesson.next())!;
    final snapshot = exerciseFromJson({...exerciseToJson(original), 'id': 'starred:abc'});
    final s = await factory().starred(StarredPractice(exercises: [snapshot]));
    expect(s.mode, SessionMode.starred);
    expect(s.plannedLength, 1);
    final served = await drive(s);
    expect(served.single.id, 'starred:abc');
    expect(served.single.type, original.type);
    expect(exercisePrompt(served.single), exercisePrompt(original));
    final logged = (await store.log()).where((e) => e.sessionId != null && e.mode == 'starred');
    expect(logged.map((e) => e.facetId), contains(original.facetId));
  });

  test('an exercise on a facet the course no longer trains is skipped', () async {
    final lesson = await factory().lesson('saluti');
    final original = (await lesson.next())!;
    final json = {...exerciseToJson(original), 'id': 'starred:gone', 'facet_id': 'it:nope#rec', 'facet_ids': ['it:nope#rec']};
    final s = await factory().starred(StarredPractice(exercises: [exerciseFromJson(json)]));
    expect(s.plannedLength, 0);
  });

  test('a starred word trains only its own facets, each once', () async {
    final s = await factory().starred(const StarredPractice(itemIds: ['it:ragazzo']));
    final facets = StarredBuilder.facetsByItem(it)['it:ragazzo']!.map((f) => f.facetId).toSet();
    expect(s.plannedLength, facets.length);
    final served = await drive(s);
    expect(served.map((e) => e.facetId).toSet(), facets);
  });

  test('a starred sentence trains the facets of its words and prefers the sentence', () async {
    final s = await factory().starred(const StarredPractice(sentenceIds: ['s:it4']));
    expect(s.plannedLength, greaterThan(0));
    final served = await drive(s);
    final items = {for (final e in served) FacetId.parse(e.facetId).itemId};
    final words = {for (final t in it.sentence('s:it4')!.tokens) ?t.lex};
    expect(words.containsAll(items), isTrue, reason: 'only the sentence\'s words: $items');
    expect(served.map(sentenceIdOf), contains('s:it4'), reason: 'the starred sentence itself is shown');
    // The verb form asks its tense.
    expect(served.map((e) => e.facetId), contains('it:mangiare#form:presente'));
  });

  test('the length caps a large mix, interleaving the three kinds', () async {
    final lesson = await factory().lesson('saluti');
    final ex = (await lesson.next())!;
    final s = await factory().starred(
      StarredPractice(
        itemIds: const ['it:ragazzo', 'it:ragazza', 'it:pane'],
        sentenceIds: const ['s:it2', 's:it4'],
        exercises: [exerciseFromJson({...exerciseToJson(ex), 'id': 'starred:1'})],
      ),
      length: 5,
    );
    expect(s.plannedLength, 5);
    final served = await drive(s);
    expect(served.first.id, 'starred:1');
    expect(served.length, 5);
  });
}
