import 'package:tosk/core/core.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/events.dart';
import 'fakes/fake_course.dart';
import 'fakes/fake_scheduler.dart';
import 'fakes/training.dart';

void main() {
  const sch = FakeScheduler();
  final course = fakeCourse();
  final t0 = utc(2026, 9, 1, 8);

  VerbCollection at(List<ReviewEvent> events, DateTime now) => computeVerbCollection(
      course: course, states: (LogReplay(scheduler: sch)..update(events)).states, scheduler: sch, now: now);

  test('lists trained verbs by frequency with one cell per trained tense', () {
    final c = at(const [], t0);
    // essere has forms but no skill trains it -> excluded.
    expect(c.verbs.map((v) => v.lemma), ['parlare', 'mangiare']);
    expect(c.tenses, ['presente', 'passato_prossimo']);
    expect(c.verbs.first.cells.map((x) => x.tense), ['presente', 'passato_prossimo']);
    expect(c.totalTables, 4);
    expect(c.count(VerbMastery.unseen), 4);
    expect(c.verbs.first.overall, VerbMastery.unseen);
  });

  test('a reviewed table of an untrained verb appears', () {
    final f = EventFactory();
    final c = at([f.ev('it:essere#form:presente', t0)], t0);
    expect(c.verbs.map((v) => v.lemma), contains('essere'));
    expect(c.verbs.firstWhere((v) => v.lemma == 'essere').cells.single.mastery, VerbMastery.learning);
  });

  test('mastery levels: unseen, learning, known, mastered and decay', () {
    final f = EventFactory();
    const m = 'it:mangiare#form:presente';
    const p = 'it:parlare#form:presente';
    const mp = 'it:mangiare#form:passato_prossimo';
    final learning = [f.ev(m, t0)]; // still in learning phase
    final known = trainFacet(f, p, t0, targetStability: 3);
    final mastered = trainFacet(f, mp, t0, targetStability: 21);
    final all = [...learning, ...known, ...mastered];
    final now = [known.last.at, mastered.last.at].reduce((a, b) => a.isAfter(b) ? a : b);
    final c = at(all, now);
    VerbTenseCell cell(String facet) =>
        c.verbs.expand((v) => v.cells).firstWhere((x) => x.facetId == facet);
    expect(cell(m).mastery, VerbMastery.learning);
    expect(cell(p).mastery, anyOf(VerbMastery.known, VerbMastery.learning));
    expect(cell(mp).mastery, VerbMastery.mastered);
    expect(cell('it:parlare#form:passato_prossimo').mastery, VerbMastery.unseen);
    expect(cell(mp).retrievability, greaterThan(0.9));
    expect(cell(mp).stability, greaterThanOrEqualTo(21));

    // Known right after training while recall is high.
    final ck = at(known, known.last.at);
    expect(ck.verbs.expand((v) => v.cells).firstWhere((x) => x.facetId == p).mastery, VerbMastery.known);

    // Long after: mastered decays to learning (recall below 0.85).
    final later = at(all, now.add(const Duration(days: 400)));
    expect(later.verbs.expand((v) => v.cells).firstWhere((x) => x.facetId == mp).mastery, VerbMastery.learning);
  });

  test('verbMasteryOf thresholds', () {
    final s = FacetState(
        facetId: 'x#form:t', stability: 30, difficulty: 5, due: t0, lastReview: t0, reps: 5, lapses: 0,
        phase: CardPhase.review);
    expect(verbMasteryOf(null, 0), VerbMastery.unseen);
    expect(verbMasteryOf(s, 0.95), VerbMastery.mastered);
    expect(verbMasteryOf(s, 0.88), VerbMastery.known);
    expect(verbMasteryOf(s, 0.80), VerbMastery.learning);
    expect(verbMasteryOf(s.copyWith(stability: 10), 0.95), VerbMastery.known);
    expect(verbMasteryOf(s.copyWith(phase: CardPhase.learning), 0.99), VerbMastery.learning);
  });

  test('card helpers', () {
    final f = EventFactory();
    final evs = [
      ...trainFacet(f, 'it:parlare#form:presente', t0, targetStability: 21),
      ...trainFacet(f, 'it:parlare#form:passato_prossimo', t0, targetStability: 21),
    ];
    final c = at(evs, evs.last.at);
    final parlare = c.verbs.firstWhere((v) => v.lemma == 'parlare');
    expect(parlare.isComplete, isTrue);
    expect(parlare.overall, VerbMastery.mastered);
    expect(parlare.count(VerbMastery.mastered), 2);
    expect(c.counts[VerbMastery.mastered], 2);
    expect(c.counts[VerbMastery.unseen], 2);
  });
}
