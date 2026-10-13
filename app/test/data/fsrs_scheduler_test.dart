import 'dart:convert';
import 'dart:io';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference vectors from py-fsrs (see tool/fsrs_reference/gen_fsrs_vectors.py).
void main() {
  final data = jsonDecode(File('test/fixtures/fsrs_vectors.json').readAsStringSync())
      as Map<String, dynamic>;
  final scheduler = FsrsScheduler();
  final sequences = (data['sequences'] as List).cast<Map<String, dynamic>>();

  test('scheduler config matches the generator', () {
    final cfg = data['scheduler'] as Map<String, dynamic>;
    expect((cfg['parameters'] as List).cast<num>().map((e) => e.toDouble()).toList(),
        kFsrsDefaultParameters);
    expect(cfg['desired_retention'], 0.9);
    expect(cfg['learning_steps'], [60, 600]);
    expect(cfg['relearning_steps'], [600]);
    expect(cfg['maximum_interval'], 36500);
    expect(cfg['enable_fuzzing'], false);
    expect(sequences.length, greaterThan(40));
  });

  const phases = {1: CardPhase.learning, 2: CardPhase.review, 3: CardPhase.relearning};
  DateTime ms(Object? v) => DateTime.fromMillisecondsSinceEpoch(v as int, isUtc: true);

  for (final seq in sequences) {
    test('matches py-fsrs: ${seq['name']}', () {
      FacetState? state;
      var i = 0;
      for (final rev in (seq['reviews'] as List).cast<Map<String, dynamic>>()) {
        final at = ms(rev['at_ms']);
        final where = '${seq['name']} review #$i';
        expect(scheduler.retrievability(state, at),
            closeTo((rev['r_before'] as num).toDouble(), 1e-9), reason: '$where r_before');
        state = scheduler.review('x:y#rec', state, Rating.fromValue(rev['rating'] as int), at);
        final after = rev['after'] as Map<String, dynamic>;
        expect(state.phase, phases[after['state']], reason: '$where phase');
        expect(state.step, after['step'], reason: '$where step');
        expect(state.stability, closeTo((after['stability'] as num).toDouble(), 1e-6),
            reason: '$where stability');
        expect(state.difficulty, closeTo((after['difficulty'] as num).toDouble(), 1e-6),
            reason: '$where difficulty');
        expect(state.due, ms(after['due_ms']), reason: '$where due');
        expect(state.lastReview, ms(after['last_review_ms']), reason: '$where lastReview');
        expect(state.reps, i + 1);
        for (final p in (rev['probes'] as List).cast<Map<String, dynamic>>()) {
          expect(scheduler.retrievability(state, ms(p['at_ms'])),
              closeTo((p['r'] as num).toDouble(), 1e-6),
              reason: '$where probe ${p['at_ms']}');
        }
        i++;
      }
    });
  }

  test('lapses count Again in review phase only', () {
    final t0 = DateTime.utc(2026, 1, 1);
    var s = scheduler.review('f', null, Rating.again, t0); // learning again: no lapse
    expect(s.lapses, 0);
    s = scheduler.review('f', s, Rating.easy, s.due); // -> review
    expect(s.phase, CardPhase.review);
    s = scheduler.review('f', s, Rating.again, s.due); // lapse -> relearning
    expect(s.lapses, 1);
    expect(s.phase, CardPhase.relearning);
    s = scheduler.review('f', s, Rating.again, s.due); // again in relearning: no lapse
    expect(s.lapses, 1);
  });

  test('unreviewed retrievability is 0; output times are UTC', () {
    expect(scheduler.retrievability(null, DateTime.utc(2026)), 0);
    final s = scheduler.review('f', null, Rating.good, DateTime(2026, 3, 1, 12));
    expect(s.due.isUtc, isTrue);
    expect(s.lastReview.isUtc, isTrue);
  });

  test('roundHalfEven matches Python round()', () {
    expect(roundHalfEven(0.5), 0);
    expect(roundHalfEven(1.5), 2);
    expect(roundHalfEven(2.5), 2);
    expect(roundHalfEven(2.4999), 2);
    expect(roundHalfEven(2.5001), 3);
    expect(roundHalfEven(-0.5), 0);
    expect(roundHalfEven(-1.5), -2);
  });
}
