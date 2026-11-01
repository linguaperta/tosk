part of 'assessment.dart';

// ==================================================================== placement

/// How placement probes and decides (docs/engine.md, "Placement").
class PlacementConfig {
  const PlacementConfig({
    this.maxExercises = kPlacementMaxExercises,
    this.grammarItems = 6,
    this.allowedWrong = 1,
    this.wordItems = 2,
    this.vocabUnitItems = 6,
    this.nearMiss = 3,
  });

  /// The test never asks more than this.
  final int maxExercises;

  /// Grammar items in a probe of a unit with grammar (production without
  /// context, across its grammar skills). The unit passes with at most
  /// [allowedWrong] wrong (5 of 6, about 85 %: decided as soon as 5 are
  /// right) and fails as soon as one more is wrong.
  final int grammarItems;
  final int allowedWrong;

  /// Vocabulary items in a probe of a unit with grammar (sampled across its
  /// vocabulary skills): evidence for the word check (a word produced right
  /// is credited), not for the unit's verdict. Asked while the budget allows.
  final int wordItems;

  /// Items of a probe of a unit without grammar (its words decide it, with
  /// the same [allowedWrong]).
  final int vocabUnitItems;

  /// A failed probe with at least this many right answers is a near miss:
  /// the unit is probed once more straight away, with other items.
  final int nearMiss;

  /// Right answers a probe of a unit with grammar needs to pass.
  int get grammarToPass => grammarItems - allowedWrong;

  /// Right answers a probe of a unit without grammar needs to pass.
  int get vocabToPass => vocabUnitItems - allowedWrong;
}

/// The default length cap of a placement test.
const int kPlacementMaxExercises = 40;

/// The share of right answers a probe needs when it runs out of items before
/// it is decided (a unit with very few items).
const double kPlacementPassMark = 0.85;

/// One main-tree unit as placement sees it.
class _UnitPlan {
  _UnitPlan(this.position, this.unit, this.skills, this.grammar, this.words);

  /// Position among the plans (course order).
  final int position;
  final Unit unit;
  final List<String> skills;

  /// Grammar facets to ask, in order (round-robin across the unit's grammar
  /// skills, irregular verbs first; verb forms and inflections come back for
  /// more persons in later rounds).
  final List<SkillFacet> grammar;

  /// One word facet per word the unit introduces (`#prod`, else `#rec`),
  /// round-robin across its vocabulary skills.
  final List<SkillFacet> words;

  bool get hasGrammar => grammar.isNotEmpty;

  /// Its grammar is articles only (then a probe may ask several).
  late final bool onlyArticles = grammar.every((f) => f.kind == FacetKind.article);

  int gNext = 0;
  int wNext = 0;

  /// Persons (cells) asked per facet, so later items ask others.
  final Map<String, Set<String>> usedCells = {};

  /// Probes run on this unit (a near miss or the boundary gets a second).
  int probes = 0;

  /// The verdict of the last probe (null: not asked).
  bool? passed;

  /// Words of this unit the learner produced right in a probe.
  final Set<String> rightWords = {};
}

class _Probe {
  _Probe(this.plan, {required this.vocabOnly});
  final _UnitPlan plan;

  /// The unit's words decide it (it has no grammar, or none could be asked).
  bool vocabOnly;

  /// Verdict items (grammar, or words when [vocabOnly]) answered and right.
  int answered = 0;
  int right = 0;

  /// Word items asked in a grammar probe (evidence for the word check).
  int extraWords = 0;
  int articles = 0;
}

/// What one served exercise counts for.
class _Asked {
  _Asked(this.probe, {required this.verdict, this.wordItem});
  final _Probe probe;
  final bool verdict;

  /// The word's item id when the exercise asked a word.
  final String? wordItem;
  bool right = false;
}

enum _Phase { search, linear, done }

class PlacementBuilder {
  const PlacementBuilder({this.config = const PlacementConfig()});

  final PlacementConfig config;

  Future<PlacementSession> start(SessionEnv env) async {
    final states = await env.store.allStates(courseId: env.course.meta.id);
    return build(env, {for (final s in states) s.facetId: s});
  }

  PlacementSession build(SessionEnv env, Map<String, FacetState> states) {
    final course = env.course;
    final ix = CourseIndex.of(course);
    final plans = <_UnitPlan>[];
    final known = <String>[];
    // The main tree only: topics are side trees, entered on their own.
    for (final u in CourseTrees.of(course).mainUnits) {
      final skills = [for (final s in course.skills) if (s.unitId == u.id && course.skillFacets(s.id).isNotEmpty) s.id];
      if (skills.isEmpty) continue;
      final own = skills.toSet();
      // Facets this unit introduces (a facet shared with an earlier unit belongs to that unit).
      List<SkillFacet> ownFacets(String skillId) => [
            for (final f in course.skillFacets(skillId))
              if (own.contains(ix.introducingSkill(f.facetId) ?? skillId)) f,
          ];
      final grammarBySkill = <List<SkillFacet>>[];
      final wordsBySkill = <List<SkillFacet>>[];
      final seenItems = <String>{};
      for (final id in skills) {
        final facets = ownFacets(id);
        // A function word is asked for production (`#prod`), not recognised.
        final g = <SkillFacet>[];
        final seenGrammar = <String>{};
        for (final f in facets) {
          if (!isPlacementGrammarFacet(course, f)) continue;
          final asked = f.kind == FacetKind.rec ? (_wordFacet(course, f) ?? f) : f;
          if (seenGrammar.add(asked.facetId)) g.add(asked);
        }
        if (g.isNotEmpty) grammarBySkill.add(_grammarOrder(course, g, env.random));
        final w = <SkillFacet>[];
        for (final f in facets) {
          if (isPlacementGrammarFacet(course, f) || !seenItems.add(f.itemId)) continue;
          w.add(_wordFacet(course, f) ?? f);
        }
        if (w.isNotEmpty) wordsBySkill.add(w..shuffle(env.random));
      }
      final grammar = _roundRobin(grammarBySkill);
      // Verb forms and inflections come back for other persons.
      final again = [for (final f in grammar) if (f.kind == FacetKind.form || f.kind == FacetKind.infl) f];
      for (var r = 0; r < 5 && again.isNotEmpty && grammar.length < 48; r++) {
        grammar.addAll(again);
      }
      final words = _roundRobin(wordsBySkill);
      if (grammar.isEmpty && words.isEmpty) continue;
      // A unit already learned (a re-run) has nothing to place: its grammar
      // (or, without grammar, its words) is learned.
      final decisive = grammar.isNotEmpty ? grammar : words;
      if (decisive.every((f) => isLearned(states[f.facetId]))) {
        known.add(u.id);
        continue;
      }
      plans.add(_UnitPlan(plans.length, u, skills, grammar, words));
    }
    return PlacementSession._(env, states, plans, known, config);
  }

  /// A grammar skill's facets: verb forms of irregular verbs first, then the
  /// rest, each shuffled.
  static List<SkillFacet> _grammarOrder(CourseData course, List<SkillFacet> facets, Random random) {
    bool irregular(SkillFacet f) => f.kind == FacetKind.form && (course.verb(f.itemId)?.irregular ?? false);
    return [
      ...[for (final f in facets) if (irregular(f)) f]..shuffle(random),
      ...[for (final f in facets) if (!irregular(f)) f]..shuffle(random),
    ];
  }

  /// The facet to ask for a word: its `#prod` when the course trains it.
  static SkillFacet? _wordFacet(CourseData course, SkillFacet f) {
    if (f.kind == FacetKind.prod) return f;
    final prod = FacetId(f.itemId, FacetKind.prod).toString();
    for (final s in course.skillsForFacet(prod)) {
      for (final g in course.skillFacets(s)) {
        if (g.facetId == prod) return g;
      }
    }
    return null;
  }

  static List<SkillFacet> _roundRobin(List<List<SkillFacet>> lists) {
    final out = <SkillFacet>[];
    final seen = <String>{};
    for (var round = 0; lists.any((l) => round < l.length); round++) {
      for (final l in lists) {
        if (round < l.length && seen.add(l[round].facetId)) out.add(l[round]);
      }
    }
    return out;
  }
}

/// "Find my level" (docs/engine.md, "Placement"): a binary search over the
/// main tree's units with grammar. Each probe asks one unit about
/// [PlacementConfig.grammarItems] production items without context (plus a
/// couple of its words); the middle unit first, then the middle of the half
/// that is left. A near miss is probed again at once, and the unit the
/// search ends on (the first one not passed) is confirmed by a second probe.
/// Units without grammar between the last passed unit and the boundary are
/// then asked one by one. Credits: the grammar of every unit up to the last
/// one passed (units below a passed probe count too); words per word, after
/// the word check ([wordCheck], [confirmWords]).
class PlacementSession extends _Assessment implements PlacementControl {
  PlacementSession._(super.env, Map<String, FacetState> states, this._plans, this._known, this.config)
      : super(mode: SessionMode.placement, states: states, passMark: kPlacementPassMark) {
    _search = [for (final p in _plans) if (p.hasGrammar) p];
    // A course without grammar units: the search runs over every unit.
    if (_search.isEmpty) _search = List.of(_plans);
    _hi = _search.length;
  }

  final PlacementConfig config;
  final List<_UnitPlan> _plans;
  final List<String> _known;

  /// The units the binary search runs over (those with grammar).
  late List<_UnitPlan> _search;
  int _lo = -1;
  late int _hi;
  _Phase _phase = _Phase.search;
  final List<_UnitPlan> _linear = [];

  /// The last plan position credited (every plan at or before it is).
  int _creditedEnd = -1;
  _Probe? _current;
  bool _done = false;
  final Map<String, _Asked> _asked = {};
  final List<String> _askedUnits = [];
  WordCheckPlan? _wordCheck;
  Set<String> _wordCheckItems = const {};
  int _wordsFromTest = 0;
  bool _wordsConfirmed = false;

  /// Units in course order that the test may ask (units already learned excluded).
  List<Unit> get units => [for (final p in _plans) p.unit];

  /// Units already learned before the test (nothing to place; re-runs).
  List<String> get knownUnits => List.unmodifiable(_known);

  /// The unit being probed (null before the first exercise and when done).
  Unit? get currentUnit => _current?.plan.unit;

  /// The last verdict of each unit asked so far (by unit id): true passed.
  Map<String, bool> get verdicts => {
        for (final p in _plans)
          if (p.passed != null) p.unit.id: p.passed!,
      };

  /// How many probes each asked unit got (a near miss or the boundary: 2).
  Map<String, int> get probes => {
        for (final p in _plans)
          if (p.probes > 0) p.unit.id: p.probes,
      };

  @override
  int get maxExercises => config.maxExercises;

  @override
  int? get targetLength => config.maxExercises;

  int get _budget => config.maxExercises - answered;

  int _toPass(_Probe p) => p.vocabOnly ? config.vocabToPass : config.grammarToPass;

  @override
  Future<Result> submit(Exercise exercise, Answer answer, {required Duration elapsed}) async {
    final before = answered;
    final r = await super.submit(exercise, answer, elapsed: elapsed);
    final a = _asked[exercise.id];
    if (answered > before && a != null) {
      a.right = r.correct;
      if (a.verdict) {
        a.probe.answered++;
        if (r.correct) a.probe.right++;
      }
      if (r.correct && a.wordItem != null) a.probe.plan.rightWords.add(a.wordItem!);
    }
    return r;
  }

  /// "I was right" counts for the probe too.
  @override
  Future<List<ReviewEvent>> overrideAnswer(String exerciseId) async {
    final can = canOverride(exerciseId);
    final written = await super.overrideAnswer(exerciseId);
    final a = _asked[exerciseId];
    if (can && a != null && !a.right) {
      a.right = true;
      if (a.verdict) a.probe.right++;
      if (a.wordItem != null) a.probe.plan.rightWords.add(a.wordItem!);
    }
    return written;
  }

  @override
  Future<AssessmentOutcome?> placeNow() async {
    if (outcome != null) return outcome;
    _done = true;
    final o = await finish();
    stop();
    return o;
  }

  /// The probe's verdict so far (null: ask more). [exhausted]: nothing more
  /// can be asked in it; decided on the share right ([kPlacementPassMark]).
  bool? _decide(_Probe p, {bool exhausted = false}) {
    final wrong = p.answered - p.right;
    if (wrong > config.allowedWrong) return false;
    if (p.right >= _toPass(p)) return true;
    if (exhausted && p.answered > 0) return p.right / p.answered >= kPlacementPassMark;
    return null;
  }

  _Probe _probe(_UnitPlan plan) {
    plan.probes++;
    if (!_askedUnits.contains(plan.unit.id)) _askedUnits.add(plan.unit.id);
    // Ask the unit as to a learner who knows it and every unit before it
    // (grammar gating, for the few items that show a sentence).
    final main = CourseTrees.of(env.course).mainUnits;
    final upTo = {for (final m in main.takeWhile((m) => m.id != plan.unit.id)) m.id, plan.unit.id};
    setCurrentSkills([for (final s in env.course.skills) if (upTo.contains(s.unitId)) s.id]);
    return _Probe(plan, vocabOnly: !plan.hasGrammar);
  }

  /// Units still to search after the current interval, roughly (for the budget).
  int _probesLeft() {
    var n = 0;
    if (_phase == _Phase.search) {
      final span = _hi - _lo - 1;
      n = span <= 0 ? 0 : (log(span + 1) / ln2).ceil();
      if (_hi < _search.length) n++; // the boundary's confirmation
    }
    final from = _lo >= 0 ? _search[_lo].position : -1;
    n += [for (final p in _plans) if (!_search.contains(p) && p.position > from && p.passed == null) p].length;
    return n;
  }

  /// The next probe, or null when the test is over.
  _Probe? _startProbe() {
    while (true) {
      switch (_phase) {
        case _Phase.search:
          if (_hi - _lo > 1) {
            if (_budget < config.grammarToPass) return null;
            return _probe(_search[(_lo + _hi) ~/ 2]);
          }
          // The search ended between two units: confirm the boundary once.
          if (_hi < _search.length && _search[_hi].probes < 2 && _budget >= _toPassOf(_search[_hi])) {
            return _probe(_search[_hi]);
          }
          _phase = _Phase.linear;
          // Units without grammar after the last unit passed and before the
          // boundary, one by one (stopping at the first failure).
          final from = _lo >= 0 ? _search[_lo].position : -1;
          final to = _hi < _search.length ? _search[_hi].position : _plans.length;
          _linear.addAll([for (final p in _plans) if (p.position > from && p.position < to && !_search.contains(p)) p]);
        case _Phase.linear:
          if (_linear.isEmpty) {
            _phase = _Phase.done;
            continue;
          }
          final p = _linear.first;
          if (_budget < _toPassOf(p)) return null;
          _linear.removeAt(0);
          return _probe(p);
        case _Phase.done:
          return null;
      }
    }
  }

  int _toPassOf(_UnitPlan p) => p.hasGrammar ? config.grammarToPass : config.vocabToPass;

  /// Settles [p] with [passed]; [last]: the test is ending (no second probe).
  void _settle(_Probe p, bool passed, {bool last = false}) {
    final plan = p.plan;
    plan.passed = passed;
    _current = null;
    if (!passed && !last && p.right >= config.nearMiss && plan.probes < 2 && _budget >= _toPassOf(plan)) {
      // A near miss: once more, with other items.
      _current = _probe(plan);
      return;
    }
    switch (_phase) {
      case _Phase.search:
        final i = _search.indexOf(plan);
        if (passed) {
          if (i > _lo) _lo = i;
          if (_hi <= _lo) {
            _hi = _search.length;
            for (var j = _lo + 1; j < _search.length; j++) {
              if (_search[j].passed == false) {
                _hi = j;
                break;
              }
            }
          }
          _creditedEnd = max(_creditedEnd, _search[_lo].position);
        } else if (i < _hi) {
          _hi = i;
        }
      case _Phase.linear:
        if (passed) {
          _creditedEnd = max(_creditedEnd, plan.position);
        } else {
          _linear.clear();
        }
      case _Phase.done:
        break;
    }
  }

  /// A unit none of whose items could be built: leaves the search (it counts
  /// with the units around it).
  void _drop(_UnitPlan plan) {
    _current = null;
    final i = _search.indexOf(plan);
    if (i < 0) return;
    _search.removeAt(i);
    if (i < _hi) _hi--;
    if (i <= _lo) _lo--;
  }

  /// The next item of [p] (its facet and exercise), or null when none can be built.
  (SkillFacet, Exercise)? _nextItem(_Probe p) {
    final plan = p.plan;
    // A grammar probe mixes in a couple of words (after the 2nd and 4th
    // grammar item) while the budget allows.
    final wantWord = !p.vocabOnly &&
        p.extraWords < config.wordItems &&
        p.answered >= 2 * (p.extraWords + 1) &&
        _budget - 1 >= max(0, _toPass(p) - p.right) + config.grammarToPass * _probesLeft();
    if (wantWord) {
      final w = _wordItem(plan);
      if (w != null) {
        p.extraWords++;
        _asked[w.$2.id] = _Asked(p, verdict: false, wordItem: w.$1.itemId);
        return w;
      }
      p.extraWords = config.wordItems; // none left
    }
    if (p.vocabOnly) {
      final w = _wordItem(plan);
      if (w != null) _asked[w.$2.id] = _Asked(p, verdict: true, wordItem: w.$1.itemId);
      return w;
    }
    while (plan.gNext < plan.grammar.length) {
      final f = plan.grammar[plan.gNext++];
      // An article is a guess among two or three: at most one per probe.
      if (f.kind == FacetKind.article && p.articles >= 1 && !plan.onlyArticles) continue;
      final ex = _grammarExercise(f, plan);
      if (ex == null) continue;
      if (f.kind == FacetKind.article) p.articles++;
      _asked[ex.id] = _Asked(p, verdict: true);
      return (f, ex);
    }
    return null;
  }

  (SkillFacet, Exercise)? _wordItem(_UnitPlan plan) {
    while (plan.wNext < plan.words.length) {
      final f = plan.words[plan.wNext++];
      final ctx = genContext(f);
      final ex = (f.kind == FacetKind.prod && !ctx.index.recognitionOnly(f) ? placementWordItem(f, ctx) : null) ??
          env.selector.generate(f, ctx, only: const {ExerciseType.multipleChoice});
      if (ex != null) return (f, ex);
    }
    return null;
  }

  Exercise? _grammarExercise(SkillFacet f, _UnitPlan plan) {
    final ctx = genContext(f);
    Exercise? viaSelector(Set<ExerciseType> only) => env.selector.generate(f, ctx, only: only);
    if (ctx.index.recognitionOnly(f)) return viaSelector(const {ExerciseType.multipleChoice});
    final used = plan.usedCells.putIfAbsent(f.facetId, () => {});
    switch (f.kind) {
      case FacetKind.form:
        final e = placementFormItem(f, ctx, usedPersons: used) ?? viaSelector(const {ExerciseType.conjGrid});
        if (e is ConjPickExercise) used.add(e.person);
        return e;
      case FacetKind.infl:
        final e = placementInflItem(f, ctx, usedCells: used) ?? viaSelector(const {ExerciseType.conjGrid});
        if (e is ConjPickExercise) used.add(e.person);
        return e;
      case FacetKind.article:
        return viaSelector(const {ExerciseType.multipleChoice});
      case FacetKind.prod:
        return placementWordItem(f, ctx) ?? viaSelector(const {ExerciseType.multipleChoice});
      case FacetKind.rec:
        return viaSelector(const {ExerciseType.multipleChoice});
    }
  }

  @override
  SessionSlot? nextQueued() {
    for (var guard = 0; guard < 1000 && !_done; guard++) {
      if (_budget <= 0) break;
      final p = _current ??= _startProbe();
      if (p == null) break;
      final v = _decide(p);
      if (v != null) {
        _settle(p, v);
        continue;
      }
      final item = _nextItem(p);
      if (item != null) return SessionSlot(item.$1, fixed: item.$2);
      // Nothing more to ask in this probe.
      if (!p.vocabOnly && p.answered < 3 && p.plan.words.length > p.plan.wNext) {
        // Too few grammar items could be built: its words decide (with them).
        p.vocabOnly = true;
        continue;
      }
      final w = _decide(p, exhausted: true);
      if (w != null) {
        _settle(p, w);
      } else {
        _drop(p.plan);
      }
    }
    _done = true;
    return null;
  }

  @override
  Future<AssessmentOutcome> conclude() async {
    final p = _current;
    if (p != null) {
      // Ended with a probe under way (the budget, or "place me now"): it
      // counts only when its answers already decide it.
      final v = _decide(p);
      if (v != null) _settle(p, v, last: true);
      _current = null;
    }
    final course = env.course;
    final credited = [for (final p in _plans) if (p.position <= _creditedEnd) p];
    final creditedIds = {for (final p in credited) p.unit.id};
    final creditedSkills = [for (final p in credited) ...p.skills];
    // Grammar per unit.
    final grammar = <String>[
      for (final s in creditedSkills)
        for (final f in course.skillFacets(s))
          if (isPlacementGrammarFacet(course, f)) f.facetId,
    ];
    await writeCreditsFor(this, grammar, ratings: kPlacementCreditRatings);
    // Words per word: those produced right in the test now, the rest after the word check.
    final fromTest = {for (final p in credited) ...p.rightWords};
    await writeCreditsFor(this, [for (final i in fromTest) ...wordFacetIds(course, i)], ratings: kPlacementCreditRatings);
    _wordsFromTest = fromTest.length;
    final plan = _buildWordCheck([
      for (final u in CourseTrees.of(course).mainUnits)
        if (creditedIds.contains(u.id) || _known.contains(u.id)) u.id,
    ], fromTest);
    _wordCheck = plan;
    _wordCheckItems = {
      for (final u in plan.units)
        for (final s in u.skills)
          for (final w in s.words) w.itemId,
    };
    final place = placementOf(course, credited: creditedIds, known: _known.toSet());
    final failed = [for (final p in _plans) if (p.passed == false && !creditedIds.contains(p.unit.id)) p.unit.id];
    final asked = _askedUnits.toSet();
    return AssessmentOutcome(
      passed: credited.isNotEmpty,
      correct: correctCount,
      total: answered,
      passMark: passMark,
      creditedSkills: creditedSkills,
      passedUnits: [for (final p in credited) p.unit.id],
      failedUnit: failed.firstOrNull,
      placedUnit: place.placed,
      gapUnits: place.gaps,
      inferredUnits: [for (final p in credited) if (!asked.contains(p.unit.id)) p.unit.id],
      knownUnits: List.of(_known),
      askedUnits: [for (final p in _plans) if (asked.contains(p.unit.id)) p.unit.id],
      wordsKnown: _wordsFromTest,
      wordsTotal: _wordsFromTest + plan.wordCount,
      wordsChecked: plan.isEmpty,
    );
  }

  /// The still-new words of [unitIds], by unit and introducing skill, each
  /// skill's words shuffled (the first [WordCheckPlan.sample] are its sample).
  WordCheckPlan _buildWordCheck(List<String> unitIds, Set<String> skip) {
    final course = env.course;
    final ix = CourseIndex.of(course);
    final lang = env.options.sourceLang;
    final seen = <String>{...skip};
    final units = <WordCheckUnit>[];
    for (final unitId in unitIds) {
      final skills = <WordCheckSkill>[];
      for (final s in course.skills) {
        if (s.unitId != unitId) continue;
        final words = <WordCheckWord>[];
        for (final f in course.skillFacets(s.id)) {
          if (f.kind != FacetKind.prod && f.kind != FacetKind.rec) continue;
          if (isPlacementGrammarFacet(course, f) || ix.introducingSkill(f.facetId) != s.id) continue;
          if (!seen.add(f.itemId)) continue;
          final facets = wordFacetIds(course, f.itemId);
          if (facets.every((id) => isLearned(states[id]))) continue;
          final item = course.item(f.itemId);
          if (item == null) continue;
          final prompt = placementPrompt(item, lang);
          if (prompt.trim().isEmpty) continue;
          words.add(WordCheckWord(
            itemId: item.id,
            prompt: prompt,
            answer: ix.withArticle(item),
            accepted: placementAccepted(ix, item, lang),
          ));
        }
        if (words.isNotEmpty) skills.add(WordCheckSkill(skillId: s.id, words: words..shuffle(env.random)));
      }
      if (skills.isNotEmpty) units.add(WordCheckUnit(unitId: unitId, skills: skills));
    }
    return WordCheckPlan(units: units, knownFromTest: skip.length);
  }

  @override
  WordCheckPlan? get wordCheck => outcome == null ? null : _wordCheck;

  @override
  Future<AssessmentOutcome> confirmWords(Iterable<String> knownItemIds) async {
    final o = outcome ?? await finish();
    if (_wordsConfirmed) return o;
    _wordsConfirmed = true;
    final known = [for (final i in {...knownItemIds}) if (_wordCheckItems.contains(i)) i];
    await writeCreditsFor(this, [for (final i in known) ...wordFacetIds(env.course, i)], ratings: kPlacementCreditRatings);
    final updated = o.withWords(known: _wordsFromTest + known.length, total: o.wordsTotal);
    _outcome = updated;
    return updated;
  }
}

/// Where a learner stands on the main tree given the units [credited] now
/// and [known] before: [placed] is the unit after the last one done (null
/// past the end), [gaps] the units before it that are not done (a unit left
/// open between learned ones).
({String? placed, List<String> gaps}) placementOf(
  CourseData course, {
  required Set<String> credited,
  Set<String> known = const {},
}) {
  final main = CourseTrees.of(course).mainUnits;
  bool done(Unit u) =>
      credited.contains(u.id) ||
      known.contains(u.id) ||
      // A unit with nothing to learn (no facets) is done when reached.
      course.skills.where((s) => s.unitId == u.id).every((s) => course.skillFacets(s.id).isEmpty);
  var last = -1;
  for (var i = 0; i < main.length; i++) {
    if (credited.contains(main[i].id) || known.contains(main[i].id)) last = i;
  }
  var p = last + 1;
  while (p < main.length && done(main[p])) {
    p++;
  }
  return (
    placed: p < main.length ? main[p].id : null,
    gaps: [for (var i = 0; i < last; i++) if (!done(main[i])) main[i].id],
  );
}

/// Ratings of the credits a placement writes per facet, 1 ms apart: Hard,
/// Good, Good graduates a new facet into review with a stability of about
/// 1.4 days (FSRS-6 defaults), so it comes back the next day as a quick
/// confirmation; a lapse there is an ordinary FSRS lapse. (A facet the test
/// asked already has a state; its credits graduate it too, back in a day or two.)
const List<Rating> kPlacementCreditRatings = [Rating.hard, Rating.good, Rating.good];

/// Ratings of a self-declared credit ("Skip ahead without a test"): Again,
/// Good, Good, stability about 0.3 days: also back the next day (FSRS's
/// shortest interval for a graduated facet), and weaker than a tested
/// credit, so it comes first among the reviews.
const List<Rating> kSelfDeclaredCreditRatings = [Rating.again, Rating.good, Rating.good];

/// Writes placement credits for every not-yet-learned facet of [skillIds]
/// through [session] (its id and mode): [kSelfDeclaredCreditRatings] marked
/// self-declared, or [kPlacementCreditRatings].
Future<void> writePlacementCredits(EngineSession session, Iterable<String> skillIds, {required bool selfDeclared}) =>
    writeCreditsFor(
      session,
      [
        for (final s in skillIds)
          for (final f in session.env.course.skillFacets(s)) f.facetId,
      ],
      ratings: selfDeclared ? kSelfDeclaredCreditRatings : kPlacementCreditRatings,
      selfDeclared: selfDeclared,
    );

/// Writes [ratings] as credits (`kTestOutCreditType`) on every facet of
/// [facetIds] that is not learned yet, 1 ms apart, after the facet's last answer.
Future<void> writeCreditsFor(
  EngineSession session,
  Iterable<String> facetIds, {
  required List<Rating> ratings,
  bool selfDeclared = false,
}) async {
  final env = session.env;
  final now = env.now();
  final seen = <String>{};
  for (final facetId in facetIds) {
    if (!seen.add(facetId)) continue;
    final state = session.states[facetId] ?? await env.store.state(facetId);
    if (isLearned(state)) continue;
    // After the facet's last answer, even within the same millisecond.
    final last = state?.lastReview.add(const Duration(milliseconds: 1));
    final at = last != null && last.isAfter(now) ? last : now;
    for (var i = 0; i < ratings.length; i++) {
      await session.recordExtra(ReviewEvent(
        id: const Uuid().v4(),
        facetId: facetId,
        at: at.add(Duration(milliseconds: i)),
        rating: ratings[i],
        exerciseType: kTestOutCreditType,
        inputMode: InputMode.self,
        responseMs: 0,
        correct: true,
        answer: selfDeclared ? kSelfDeclaredCredit : null,
        sessionId: session.id,
        mode: session.mode.name,
      ));
    }
  }
}

/// "Skip ahead without a test": the learner marks main-tree units as known.
/// Every skill of [unitIds] is credited with [kSelfDeclaredCreditRatings],
/// marked [kSelfDeclaredCredit], mode `placement`. Built and concluded at
/// once: [outcome] is set by [declare].
class SkipAheadSession extends _Assessment {
  SkipAheadSession(super.env, Map<String, FacetState> states, this.unitIds)
      : super(mode: SessionMode.placement, states: states, passMark: 0);

  final List<String> unitIds;

  @override
  int? get targetLength => 0;

  @override
  SessionSlot? nextQueued() => null;

  /// Writes the credits and returns the outcome.
  Future<AssessmentOutcome> declare() => finish();

  @override
  Future<AssessmentOutcome> conclude() async {
    final course = env.course;
    final main = CourseTrees.of(course).mainUnits;
    final chosen = unitIds.toSet();
    final units = [for (final u in main) if (chosen.contains(u.id)) u.id];
    final skills = [
      for (final u in units)
        for (final s in course.skills)
          if (s.unitId == u && course.skillFacets(s.id).isNotEmpty) s.id,
    ];
    await writePlacementCredits(this, skills, selfDeclared: true);
    final place = placementOf(course, credited: units.toSet());
    return AssessmentOutcome(
      passed: units.isNotEmpty,
      correct: 0,
      total: 0,
      passMark: 0,
      creditedSkills: skills,
      passedUnits: units,
      placedUnit: place.placed,
      gapUnits: place.gaps,
      selfDeclared: true,
      wordsChecked: true,
    );
  }
}
