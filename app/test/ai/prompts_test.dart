import 'package:tosk/ai/prompts.dart';
import 'package:tosk/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ai_fixtures.dart';

void main() {
  group('explainPrompt', () {
    test('wrong answer: the exercise, both answers, the note, the reply language', () {
      final p = explainPrompt(wrongCtx);
      expect(p.system, contains('English'));
      expect(p.system, contains('150 words'));
      expect(p.system, contains('no tables'));
      expect(p.user, contains('learning Italian (it)'));
      expect(p.user, contains('Instruction: Pick the right ending'));
      expect(p.user, contains('Choices shown: iamo / iate / ano'));
      expect(p.user, contains('Expected answer: mangiamo'));
      expect(p.user, contains("Learner's answer: mangiate (marked wrong)"));
      expect(p.user, contains('Present of -are verbs'));
      expect(p.user, contains('what exactly is wrong'));
    });

    test('right answer, explained in another language than the source', () {
      final p = explainPrompt(rightCtx.copyWith(explainLang: 'en'));
      expect(p.system, contains('Write in English'));
      expect(p.user, contains('accepted as correct'));
      expect(p.user, contains('answered correctly'));
      expect(p.user, isNot(contains('Grammar note')));
    });

    test('long notes are clipped', () {
      final ctx = rightCtx.copyWith(note: 'x' * (kMaxNoteChars * 2));
      expect(explainPrompt(ctx).user.length, lessThan(kMaxNoteChars + 1000));
    });
  });

  group('flag review', () {
    test('prompt carries reasons, comment and the snapshot, and asks for a verdict line', () {
      final p = flagReviewPrompt(
        context: wrongCtx,
        reasons: [FlagReason.multipleAnswers],
        comment: 'mangiate is also fine',
        snapshot: {
          'type': 'conj_pick',
          'endings': ['iamo', 'iate', 'ano'],
        },
      );
      expect(p.system, contains('VERDICT: exercise_wrong'));
      expect(p.system, contains('Do not simply agree'));
      expect(p.user, contains('Multiple answers are possible'));
      expect(p.user, contains('mangiate is also fine'));
      expect(p.user, contains('"endings":["iamo","iate","ano"]'));
    });

    test('parseVerdict reads the verdict line and keeps the reasoning', () {
      final v = parseVerdict('VERDICT: exercise_correct\nFor *noi* the ending is **-iamo**.');
      expect(v.verdict, FlagVerdict.exerciseCorrect);
      expect(v.reasoning, 'For *noi* the ending is **-iamo**.');
      expect(parseVerdict('**Verdict: Ambiguous**\nBoth work.').verdict, FlagVerdict.ambiguous);
      expect(parseVerdict('Some text\nverdict - exercise wrong\nmore').verdict, FlagVerdict.exerciseWrong);
      final none = parseVerdict('I am not sure.');
      expect(none.verdict, isNull);
      expect(none.reasoning, 'I am not sure.');
    });
  });
}
