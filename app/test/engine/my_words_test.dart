// "My words" in the engine (engine/session/my_words.dart): the learner's own
// words get rec/prod facets scheduled by FSRS like pack items, their own
// exercises (flashcard, multiple choice with wrong options from the other own
// words and the course lexicon of the same part of speech, "write the word"),
// a "My words" session, and they mix into lessons only as due reviews.
import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart' as data;
import 'package:tosk/engine/engine.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/italian_course.dart';
import 'helpers.dart';

final _now = DateTime.utc(2026, 10, 25, 12);

UserWord _word(String id, String word, String tr, {String? pos, int day = 0}) => UserWord(
  id: 'user~$id',
  word: word,
  translation: tr,
  pos: pos,
  at: _now.add(Duration(minutes: day)),
);

void main() {
  final it = italianCourse();
  final scheduler = FsrsScheduler();
  late data.InMemoryProgressStore store;
  late DateTime clock;
  late List<UserWord> words;

  EngineSessionFactory factory({int seed = 1, InputMode input = InputMode.tap}) => EngineSessionFactory(
    course: it,
    store: store,
    scheduler: scheduler,
    options: SessionOptions(sourceLang: 'en', seed: seed, preferredInput: input),
    clock: () => clock,
    userWords: () async => words,
  );

  setUp(() {
    store = data.InMemoryProgressStore(scheduler: scheduler);
    clock = _now;
    words = [
      _word('1', 'questura', 'police headquarters', pos: 'noun'),
      _word('2', 'commissario', 'inspector', pos: 'noun', day: 1),
      _word('3', 'sbirro', 'cop', pos: 'noun', day: 2),
      _word('4', 'indagare', 'to investigate', pos: 'verb', day: 3),
    ];
  });

  Future<List<(Exercise, Result)>> drive(PracticeSession s, {int max = 100, bool Function(Exercise e)? wrong}) async {
    final out = <(Exercise, Result)>[];
    for (var i = 0; i < max; i++) {
      final e = await s.next();
      if (e == null) break;
      final r = await s.submit(
        e,
        (wrong?.call(e) ?? false) ? wrongAnswer(e) : correctAnswer(e),
        elapsed: const Duration(seconds: 4),
      );
      out.add((e, r));
      clock = clock.add(const Duration(seconds: 10));
    }
    return out;
  }

  /// Every facet of [w] reviewed long ago, so it is due now.
  Future<void> makeDue(UserWord w) async {
    for (final f in [w.recFacet('it'), w.prodFacet('it')]) {
      for (final (i, r) in [Rating.good, Rating.good, Rating.good].indexed) {
        await store.record(
          ReviewEvent(
            id: '$f-$i',
            facetId: f,
            at: _now.subtract(Duration(days: 60 - i * 3)),
            rating: r,
            exerciseType: 'flashcard',
            inputMode: InputMode.self,
            responseMs: 1000,
            correct: true,
          ),
        );
      }
    }
  }

  group('pool and exercises', () {
    test('two facets per word, under the pseudo skill, deleted and empty words left out', () {
      final pool = UserWordPool('it', [...words, _word('x', 'gone', 'gone').tombstone(_now), _word('y', '', 'empty')]);
      expect(pool.words.map((w) => w.word), ['questura', 'commissario', 'sbirro', 'indagare']);
      expect(pool.facets.map((f) => f.facetId).take(2), ['it:user~1#rec', 'it:user~1#prod']);
      expect(pool.facets.every((f) => f.skillId == kMyWordsSkillId), isTrue);
      expect(pool.facet('it:user~3#prod')!.kind, FacetKind.prod);
      expect(pool.wordOfFacet('it:user~4#rec')!.word, 'indagare');
      expect(it.skill(kMyWordsSkillId), isNull, reason: 'no pack has the pseudo skill');
    });

    test('a fresh word is introduced with a flashcard; later ones get choices and writing', () {
      final pool = UserWordPool('it', words);
      final f = pool.facetsOf(words.first);
      var n = 0;
      String id() => 'e${n++}';
      for (var seed = 0; seed < 20; seed++) {
        final e = pool.generate(
          f[0],
          course: it,
          options: const SessionOptions(sourceLang: 'en'),
          random: Random(seed),
          state: null,
          nextId: id,
        );
        // Fresh: mostly flashcards (a choice now and then).
        expect(e, isA<Exercise>());
      }
      final fresh = [
        for (var seed = 0; seed < 40; seed++)
          pool
              .generate(
                f[0],
                course: it,
                options: const SessionOptions(sourceLang: 'en'),
                random: Random(seed),
                state: null,
                nextId: id,
              )!
              .type,
      ];
      expect(fresh.where((t) => t == ExerciseType.flashcard).length, greaterThan(25));
      final learning = FacetState(
        facetId: f[1].facetId,
        stability: 3,
        difficulty: 5,
        due: _now,
        lastReview: _now,
        reps: 2,
        lapses: 0,
        phase: CardPhase.review,
      );
      final types = {
        for (var seed = 0; seed < 60; seed++)
          pool
              .generate(
                f[1],
                course: it,
                options: const SessionOptions(sourceLang: 'en'),
                random: Random(seed),
                state: learning,
                nextId: id,
              )!
              .type,
      };
      expect(types, containsAll([ExerciseType.flashcard, ExerciseType.multipleChoice, ExerciseType.cloze]));
    });

    test(
      'multiple choice: the word once, wrong options from my other words, then the lexicon of the same part of speech',
      () {
        final pool = UserWordPool('it', words);
        final rec = pool.facetsOf(words.first)[0];
        final prod = pool.facetsOf(words.first)[1];
        final nouns = {
          for (final i in it.allItems)
            if (i.pos == 'noun') i.gloss('en'),
        };
        final nounLemmas = {
          for (final i in it.allItems)
            if (i.pos == 'noun') i.lemma,
        };
        for (var seed = 0; seed < 30; seed++) {
          final r = pool.generate(
            rec,
            course: it,
            options: const SessionOptions(sourceLang: 'en'),
            random: Random(seed),
            state: null,
            nextId: () => 'r',
            only: {ExerciseType.multipleChoice},
          ) as MultipleChoiceExercise;
          expect(r.prompt, 'questura');
          expect(r.options[r.correctIndex], 'police headquarters');
          expect(r.options.where((o) => o == 'police headquarters'), hasLength(1));
          expect(r.options.toSet(), hasLength(r.options.length));
          for (final o in r.options) {
            if (o == 'police headquarters') continue;
            expect(['inspector', 'cop', 'to investigate', ...nouns].contains(o), isTrue, reason: o);
          }
          expect(
            r.options.any((o) => ['inspector', 'cop', 'to investigate'].contains(o)),
            isTrue,
            reason: 'my other words first',
          );
          final p = pool.generate(
            prod,
            course: it,
            options: const SessionOptions(sourceLang: 'en'),
            random: Random(seed),
            state: null,
            nextId: () => 'p',
            only: {ExerciseType.multipleChoice},
          ) as MultipleChoiceExercise;
          expect(p.prompt, 'police headquarters');
          expect(p.options[p.correctIndex], 'questura');
          for (final o in p.options) {
            expect(['questura', 'commissario', 'sbirro', 'indagare', ...nounLemmas].contains(o), isTrue, reason: o);
          }
        }
      },
    );

    test('a lone word still gets wrong options from the course lexicon', () {
      final pool = UserWordPool('it', [_word('solo', 'questura', 'police headquarters', pos: 'noun')]);
      final rec = pool.facetsOf(pool.words.single)[0];
      final e = pool.generate(
        rec,
        course: it,
        options: const SessionOptions(sourceLang: 'en'),
        random: Random(1),
        state: null,
        nextId: () => 'x',
        only: {ExerciseType.multipleChoice},
      );
      expect(e, isA<MultipleChoiceExercise>());
      expect((e! as MultipleChoiceExercise).options.length, greaterThanOrEqualTo(3));
    });

    test(
      '"write the word": typed for keyboard and ink learners, a choice for tap learners; graded by the cloze template',
      () {
        final pool = UserWordPool('it', words);
        final prod = pool.facetsOf(words[1])[1];
        final typed = pool.generate(
          prod,
          course: it,
          options: const SessionOptions(sourceLang: 'en', preferredInput: InputMode.keyboard),
          random: Random(2),
          state: null,
          nextId: () => 'c',
          only: {ExerciseType.cloze},
        ) as ClozeExercise;
        expect(typed.options, isNull);
        expect(typed.expected, 'commissario');
        expect(typed.hint, 'inspector');
        expect(typed.before + typed.expected + typed.after, 'commissario');
        final tap = pool.generate(
          prod,
          course: it,
          options: const SessionOptions(sourceLang: 'en'),
          random: Random(2),
          state: null,
          nextId: () => 'c',
          only: {ExerciseType.cloze},
        ) as ClozeExercise;
        expect(tap.options![tap.correctIndex!], 'commissario');
        final template = ExerciseSelector().template(ExerciseType.cloze)!;
        expect(
          template.grade(typed, const TextAnswer('Commissario'), elapsed: const Duration(seconds: 3)).correct,
          isTrue,
        );
        expect(
          template.grade(typed, const TextAnswer('commisario'), elapsed: const Duration(seconds: 3)).correct,
          isFalse,
        );
        // Recognition never writes.
        final rec = pool.facetsOf(words[1])[0];
        expect(
          pool.generate(
            rec,
            course: it,
            options: const SessionOptions(sourceLang: 'en'),
            random: Random(2),
            state: null,
            nextId: () => 'c',
            only: {ExerciseType.cloze},
          ),
          isNull,
        );
      },
    );
  });

  group('the "My words" session', () {
    test('no words: an empty session', () async {
      words = [];
      final s = await factory().myWords();
      expect(s.mode, SessionMode.myWords);
      expect(s.plannedLength, 0);
      expect(await s.next(), isNull);
    });

    test('new words in the order added, recognise before produce; answers go to the log and FSRS', () async {
      final s = await factory().myWords(length: 12);
      expect(s.plannedLength, 6, reason: 'at most six new facets');
      final served = await drive(s);
      expect(served.map((x) => x.$1.facetId).toList(), [
        'it:user~1#rec',
        'it:user~1#prod',
        'it:user~2#rec',
        'it:user~2#prod',
        'it:user~3#rec',
        'it:user~3#prod',
      ]);
      final log = await store.log();
      expect(log.map((e) => e.mode).toSet(), {'myWords'});
      expect(log.map((e) => e.facetId).toSet(), hasLength(6));
      final state = await store.state('it:user~1#rec');
      expect(state, isNotNull);
      expect(state!.due.isAfter(clock), isTrue, reason: 'scheduled ahead');
      expect((await store.allStates(courseId: 'it')).map((s) => s.facetId), contains('it:user~2#prod'));
    });

    test('due words come first, most overdue first; mistakes come back as retries', () async {
      await makeDue(words[3]);
      await makeDue(words[2]);
      final s = await factory().myWords(length: 6);
      final served = await drive(
        s,
        wrong: (e) => e.facetId == 'it:user~4#prod' && !s.isRetry(e.id),
      );
      final facets = served.map((x) => x.$1.facetId).toList();
      expect(facets.take(4).toSet(), {'it:user~3#rec', 'it:user~3#prod', 'it:user~4#rec', 'it:user~4#prod'});
      expect(facets.last, 'it:user~4#prod', reason: 'the missed one comes back at the end');
      expect(served.last.$2.correct, isTrue);
      final mistakes = await store.mistakes(courseId: 'it');
      expect(mistakes.single.facetId, 'it:user~4#prod');
    });

    test('a word deleted meanwhile is no longer asked', () async {
      final f = factory();
      words = [words.first];
      final s = await f.myWords();
      expect(s.plannedLength, 2);
    });
  });

  group('lessons', () {
    test('new own words never enter a lesson uninvited', () async {
      final s = await factory().lesson('saluti');
      final served = await drive(s);
      expect(served.where((x) => isUserFacetId(x.$1.facetId)), isEmpty);
    });

    test('due own words mix in as reviews: about one in six, spread out, the lesson length unchanged', () async {
      for (final w in words) {
        await makeDue(w);
      }
      final s = await factory().lesson('saluti', length: 12);
      expect(s.lessonPlan.myWords, hasLength(2));
      expect(s.lessonPlan.all, hasLength(12));
      expect(s.currentSkillIds, isNot(contains(kMyWordsSkillId)));
      final all = s.lessonPlan.all;
      final positions = [
        for (var i = 0; i < all.length; i++)
          if (isUserFacetId(all[i].facetId)) i,
      ];
      expect(positions.first, greaterThan(0));
      expect(positions.last, lessThan(all.length - 1));
      final served = await drive(s);
      final mine = served.where((x) => isUserFacetId(x.$1.facetId)).toList();
      expect(mine, hasLength(2));
      for (final (e, r) in mine) {
        expect(kUserWordTypes, contains(e.type));
        expect(r.correct, isTrue);
      }
      final quick = await factory().lesson('saluti', length: 5);
      expect(quick.lessonPlan.myWords, hasLength(1));
      final long = await factory().lesson('saluti', length: 20);
      expect(long.lessonPlan.myWords, hasLength(3));
    });

    test('progression: own words earn XP, show in stats and summaries, and never touch skill tiers', () async {
      final p = ProgressionService(store: store, scheduler: scheduler, course: it, clock: () => clock);
      final tiersBefore = await p.skillTiers();
      final xpBefore = (await p.profile()).totalXp;
      final s = await factory().myWords();
      await drive(s);
      final after = await p.profile();
      expect(after.totalXp, greaterThan(xpBefore));
      expect((await p.skillTiers()).keys, tiersBefore.keys);
      expect(await p.sessionSummary(s.id), isNotNull);
      await p.stats(lang: 'en');
      expect(it.skillsForFacet('it:user~1#rec'), isEmpty);
    });
  });

  test('real packs: own words mixed into a lesson give valid exercises (it, nl, es)', () async {
    for (final id in ['it', 'nl', 'es']) {
      final course = loadCourseFile('assets/courses/$id.sqlite');
      final s2 = data.InMemoryProgressStore(scheduler: scheduler);
      final own = [
        for (final (i, l) in course.allItems.where((i) => i.pos == 'noun').take(3).indexed)
          UserWord(id: 'user~r$i', word: '${l.lemma}x', translation: 'mine $i', pos: 'noun', at: _now),
      ];
      for (final w in own) {
        for (final f in [w.recFacet(id), w.prodFacet(id)]) {
          await s2.record(
            ReviewEvent(
              id: f,
              facetId: f,
              at: _now.subtract(const Duration(days: 30)),
              rating: Rating.good,
              exerciseType: 'flashcard',
              inputMode: InputMode.self,
              responseMs: 1,
              correct: true,
            ),
          );
        }
      }
      final f = EngineSessionFactory(
        course: course,
        store: s2,
        scheduler: scheduler,
        options: const SessionOptions(sourceLang: 'en', seed: 3),
        clock: () => _now,
        userWords: () async => own,
      );
      final lesson = await f.lesson(course.skills.first.id);
      expect(lesson.lessonPlan.myWords, hasLength(2), reason: id);
      var mine = 0;
      for (var i = 0; i < 30; i++) {
        final e = await lesson.next();
        if (e == null) break;
        if (isUserFacetId(e.facetId)) {
          mine++;
          if (e case MultipleChoiceExercise(:final options)) {
            expect(options.toSet(), hasLength(options.length), reason: id);
          }
        }
        await lesson.submit(e, correctAnswer(e), elapsed: const Duration(seconds: 3));
      }
      expect(mine, 2, reason: id);
    }
  });
}
