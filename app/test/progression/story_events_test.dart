import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

/// Story reads (`kStoryReadType`): light fixed XP, no effect on real facets,
/// exact replays, and no answers or new words in challenges.
void main() {
  final scheduler = FsrsScheduler();
  final t0 = DateTime.utc(2026, 10, 6, 9); // Tuesday of ISO week 41
  var n = 0;

  ReviewEvent story(String id, DateTime at, String score) => ReviewEvent(
    id: 'st${n++}',
    facetId: storyFacetId('it', id),
    at: at,
    rating: Rating.good,
    exerciseType: kStoryReadType,
    inputMode: InputMode.tap,
    responseMs: 60000,
    correct: true,
    answer: score,
    sessionId: 'story-session-$n',
    mode: kStoryMode,
  );

  ReviewEvent answer(String facet, DateTime at) => ReviewEvent(
    id: 'ans${n++}',
    facetId: facet,
    at: at,
    rating: Rating.good,
    exerciseType: 'multiple_choice',
    inputMode: InputMode.tap,
    responseMs: 1500,
    correct: true,
    sessionId: 'lesson-1',
    mode: 'lesson',
  );

  test('XP: 5 + 1 per correct answer on the first read, 2 for a reread, capped', () {
    final replay = LogReplay(scheduler: scheduler)
      ..update([
        story('u1-a', t0, '3/4'),
        story('u1-a', t0.add(const Duration(minutes: 5)), '4/4'),
        story('u1-b', t0.add(const Duration(minutes: 10)), '9/9'),
        story('u1-c', t0.add(const Duration(days: 30)), 'garbage'),
      ]);
    expect(replay.steps.map((s) => s.xp), [8, 2, 10, 5]);
  });

  test('a story read leaves every real facet untouched and rebuildStates stays exact', () async {
    final store = InMemoryProgressStore(scheduler: scheduler);
    final plain = InMemoryProgressStore(scheduler: scheduler);
    final answers = [
      answer('it:pane#rec', t0),
      answer('it:pane#rec', t0.add(const Duration(days: 2))),
      answer('it:mangiare#form:presente', t0.add(const Duration(days: 3))),
    ];
    for (final e in answers) {
      await plain.record(e);
      await store.record(e);
    }
    await store.record(story('u1-a', t0.add(const Duration(days: 1)), '2/3')); // out of order, between answers
    await store.record(story('u1-a', t0.add(const Duration(days: 4)), '3/3'));
    for (final f in ['it:pane#rec', 'it:mangiare#form:presente']) {
      expect(await store.state(f), await plain.state(f));
    }
    final before = {for (final s in await store.allStates(courseId: 'it')) s.facetId: s};
    expect(before.keys, contains(storyFacetId('it', 'u1-a')));
    await store.rebuildStates();
    final after = {for (final s in await store.allStates(courseId: 'it')) s.facetId: s};
    expect(after, before);
    expect((await store.log(courseId: 'it')).where((e) => e.isStory), hasLength(2));
  });

  test('challenges count a story read as practice and XP, not as an answer or a new word', () {
    final cal = LocalCalendar.utc;
    final week = Period.weekOf(const LocalDate(2026, 10, 5));
    ChallengeTemplate tpl(ChallengeMetric m) =>
        ChallengeTemplate(id: m.name, metric: m, target: 100, title: m.name, description: '');
    final facts = ChallengeFacts.build(
      (LogReplay(scheduler: scheduler)..update([story('u1-a', t0, '3/4'), answer('it:pane#rec', t0.add(const Duration(days: 1)))]))
          .steps,
      cal,
    );
    expect(facts.evaluate(tpl(ChallengeMetric.reviews), week).progress, 1);
    expect(facts.evaluate(tpl(ChallengeMetric.correctAnswers), week).progress, 1);
    expect(facts.evaluate(tpl(ChallengeMetric.newWords), week).progress, 1);
    expect(facts.evaluate(tpl(ChallengeMetric.practiceDays), week).progress, 2);
    expect(facts.evaluate(tpl(ChallengeMetric.xp), week).progress, 8 + 8); // story 5+3, a new facet 8
  });
}
