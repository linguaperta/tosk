/// The word check after a placement test ("Check the words you already
/// know", docs/engine.md "Placement"): the words of the units whose grammar
/// the test credited, grouped by unit and skill. Placement credits grammar
/// per unit and vocabulary per word: only the words the learner confirms
/// here are credited, the rest stay new.
library;

import 'package:meta/meta.dart';

/// One word to check: its meaning in the learner's language and the target
/// word. The UI shows [prompt], then [answer] (reveal and self-grade), or
/// takes a typed answer graded against [accepted].
@immutable
class WordCheckWord {
  const WordCheckWord({required this.itemId, required this.prompt, required this.answer, this.accepted = const []});

  final String itemId;

  /// The meaning, in the source language (`boy`, `to eat`).
  final String prompt;

  /// The target word as shown after revealing it (`il ragazzo`, `mangiare`).
  final String answer;

  /// Every accepted spelling of a typed answer (with and without the
  /// article, variants, words that mean the same).
  final List<String> accepted;
}

/// The words of one skill, in the order to check them: a random sample of
/// [WordCheckPlan.sample] first, then the rest.
@immutable
class WordCheckSkill {
  const WordCheckSkill({required this.skillId, required this.words});
  final String skillId;
  final List<WordCheckWord> words;
}

@immutable
class WordCheckUnit {
  const WordCheckUnit({required this.unitId, required this.skills});
  final String unitId;
  final List<WordCheckSkill> skills;

  int get wordCount => skills.fold(0, (n, s) => n + s.words.length);
}

/// What the word check asks, unit by unit (course order). Per skill the
/// learner first checks [sample] words; when they knew at least [passShare]
/// of them, the UI offers to mark the rest of the skill as known, otherwise
/// every word of the skill is checked. A skill of at most [sample] + 2 words
/// is checked whole.
@immutable
class WordCheckPlan {
  const WordCheckPlan({required this.units, this.sample = 6, this.passShare = 0.9, this.knownFromTest = 0});

  final List<WordCheckUnit> units;
  final int sample;
  final double passShare;

  /// Words of these units the test itself asked and the learner produced
  /// right: already credited, not asked again (they count as known).
  final int knownFromTest;

  int get wordCount => units.fold(0, (n, u) => n + u.wordCount);
  bool get isEmpty => wordCount == 0;

  /// Words of [skill] asked before the offer to mark the rest: all of them
  /// for a small skill.
  int sampleSizeOf(WordCheckSkill skill) => skill.words.length <= sample + 2 ? skill.words.length : sample;

  /// Whether [known] of [asked] sample words is enough to offer "mark the rest as known".
  bool samplePassed(int known, int asked) => asked > 0 && known >= (passShare * asked).ceil();
}

/// Where a [WordCheckRun] is.
enum WordCheckStep {
  /// A word is shown ([WordCheckRun.word]); the learner says whether they knew it.
  word,

  /// A skill's sample went well: "Mark the other N words as known?"
  /// ([WordCheckRun.markRest] or [WordCheckRun.checkRest]).
  offer,

  /// Every unit is through (or the learner stopped).
  done,
}

/// The word check as the learner goes through it, unit by unit and skill by
/// skill: the sample of each skill first, then either the offer to mark the
/// rest as known (the sample went well) or the rest one by one; any unit can
/// be skipped ("I'll learn these as new"). [known] is what to credit.
class WordCheckRun {
  WordCheckRun(this.plan) {
    _settle();
  }

  final WordCheckPlan plan;
  int _unit = 0;
  int _skill = 0;
  int _word = 0;
  int _sampleKnown = 0;

  /// The sample went below the pass share: every word of the skill is checked.
  bool _checkAll = false;
  bool _offer = false;
  bool _stopped = false;
  final Set<String> _known = {};
  int _answered = 0;

  /// Words the learner knew (or marked as known), to credit.
  Set<String> get known => Set.unmodifiable(_known);

  /// Words answered one by one so far (not those marked in bulk).
  int get answered => _answered;

  WordCheckStep get step => _stopped || _unit >= plan.units.length
      ? WordCheckStep.done
      : _offer
          ? WordCheckStep.offer
          : WordCheckStep.word;

  bool get isDone => step == WordCheckStep.done;
  WordCheckUnit? get unit => isDone ? null : plan.units[_unit];
  WordCheckSkill? get skill => isDone ? null : plan.units[_unit].skills[_skill];
  WordCheckWord? get word => step == WordCheckStep.word ? skill!.words[_word] : null;

  /// 0-based number of the current unit among the plan's.
  int get unitIndex => _unit;

  /// The current word's 1-based position in its skill and how many of the
  /// skill's words this round asks (the sample, or all of them).
  int get position => _word + 1;
  int get roundSize {
    final s = skill;
    if (s == null) return 0;
    return _checkAll ? s.words.length : plan.sampleSizeOf(s);
  }

  /// Whether the current skill is past its sample (checking every word).
  bool get checkingAll => _checkAll;

  /// Sample words known in the current skill.
  int get sampleKnown => _sampleKnown;

  /// Words of the current skill not asked yet (offered for marking).
  int get restCount => skill == null ? 0 : skill!.words.length - _word;

  /// The learner knew the current word (true) or not.
  void answer(bool knew) {
    final w = word;
    if (w == null) return;
    _answered++;
    if (knew) _known.add(w.itemId);
    final s = skill!;
    final sampleSize = plan.sampleSizeOf(s);
    if (!_checkAll && _word < sampleSize && knew) _sampleKnown++;
    _word++;
    if (!_checkAll && _word == sampleSize && _word < s.words.length) {
      if (plan.samplePassed(_sampleKnown, sampleSize)) {
        _offer = true;
      } else {
        _checkAll = true;
      }
    }
    _settle();
  }

  /// "Mark the other N as known": the rest of the skill counts as known.
  void markRest() {
    if (!_offer) return;
    final s = skill!;
    for (final w in s.words.skip(_word)) {
      _known.add(w.itemId);
    }
    _offer = false;
    _nextSkill();
  }

  /// "Check them one by one" after a good sample.
  void checkRest() {
    if (!_offer) return;
    _offer = false;
    _checkAll = true;
    _settle();
  }

  /// "I'll learn these as new": the rest of the current unit stays new.
  void skipUnit() {
    if (isDone) return;
    _offer = false;
    _unit++;
    _skill = 0;
    _resetSkill();
    _settle();
  }

  /// Ends the check here: everything not answered stays new.
  void stop() => _stopped = true;

  void _resetSkill() {
    _word = 0;
    _sampleKnown = 0;
    _checkAll = false;
  }

  void _nextSkill() {
    _skill++;
    _resetSkill();
    _settle();
  }

  /// Moves past finished skills and units.
  void _settle() {
    while (_unit < plan.units.length) {
      final u = plan.units[_unit];
      if (_skill >= u.skills.length) {
        _unit++;
        _skill = 0;
        _resetSkill();
        continue;
      }
      if (!_offer && _word >= u.skills[_skill].words.length) {
        _skill++;
        _resetSkill();
        continue;
      }
      return;
    }
  }
}
