/// Session builders: lesson, exercise lab, non-stop and "what's fading".
library;

import '../../core/interfaces/course_data.dart';
import '../../core/interfaces/progress_store.dart';
import '../../core/interfaces/session.dart';
import '../../core/models/course.dart';
import '../../core/models/facet.dart';
import '../../core/models/progress.dart';
import 'engine_session.dart';
import 'my_words.dart';

/// Weakest first: lowest predicted recall, then least recently reviewed.
List<SkillFacet> _byWeakness(
  Iterable<SkillFacet> facets,
  Map<String, FacetState> states,
  Scheduler scheduler,
  DateTime now,
) {
  final list = facets.toList();
  final r = {for (final f in list) f.facetId: scheduler.retrievability(states[f.facetId], now)};
  list.sort((a, b) {
    final c = r[a.facetId]!.compareTo(r[b.facetId]!);
    if (c != 0) return c;
    final la = states[a.facetId]?.lastReview;
    final lb = states[b.facetId]?.lastReview;
    if (la == null || lb == null) return 0;
    return la.compareTo(lb);
  });
  return list;
}

List<SkillFacet> _dueSorted(Iterable<SkillFacet> facets, Map<String, FacetState> states, DateTime now) {
  final due = [
    for (final f in facets)
      if (states[f.facetId] != null && states[f.facetId]!.isDue(now)) f,
  ];
  due.sort((a, b) => states[a.facetId]!.due.compareTo(states[b.facetId]!.due));
  return due;
}

/// Appends [item] to [list] unless it would repeat the last element; returns success.
bool _appendNoRepeat(List<SkillFacet> list, SkillFacet item) {
  if (list.isNotEmpty && list.last.facetId == item.facetId) return false;
  list.add(item);
  return true;
}

/// Fills [out] up to [length] by cycling through [pool] without immediate repeats.
void _fill(List<SkillFacet> out, List<SkillFacet> pool, int length) {
  if (pool.isEmpty) return;
  var i = 0;
  var misses = 0;
  while (out.length < length && misses < pool.length * 2) {
    if (_appendNoRepeat(out, pool[i % pool.length])) {
      misses = 0;
    } else {
      misses++;
    }
    i++;
  }
}

// ==================================================================== lesson

/// The facets of a lesson, in serving order.
class LessonPlan {
  const LessonPlan({required this.due, required this.fresh, required this.filler, this.myWords = const []});

  /// 1) Due facets of the skill, most overdue first.
  final List<SkillFacet> due;

  /// 2) Up to `maxNew` new facets in introduction order.
  final List<SkillFacet> fresh;

  /// 3) Filler: weakest / least recently reviewed facets, then repeats of the
  ///    lesson's new and due facets.
  final List<SkillFacet> filler;

  /// 4) Due facets of the learner's own words ("my words"), as reviews: only
  ///    due ones, never new words, about one in six exercises
  ///    ([myWordsPerLesson]); spread evenly through the lesson.
  final List<SkillFacet> myWords;

  /// The lesson's own facets, in serving order.
  List<SkillFacet> get skillPart => [...due, ...fresh, ...filler];

  /// Everything in serving order: [skillPart] with [myWords] spread through it.
  List<SkillFacet> get all {
    final out = skillPart;
    final n = myWords.length;
    for (var i = n - 1; i >= 0; i--) {
      out.insert(((i + 1) * out.length / (n + 1)).round().clamp(0, out.length), myWords[i]);
    }
    return out;
  }
}

/// About 12 exercises from one skill: due facets, then up to 5 new facets,
/// then filler. Mistakes come back after the planned exercises (see [EngineSession]).
class LessonBuilder {
  const LessonBuilder(this.skill, this.focus, {this.length = 12, this.maxNew = 5});

  final Skill skill;
  final LessonFocus focus;
  final int length;
  final int maxNew;

  LessonPlan plan(
    CourseData course,
    Map<String, FacetState> states, {
    required Scheduler scheduler,
    required DateTime now,
    List<SkillFacet> myWordsDue = const [],
  }) {
    final mine = myWordsDue.take(myWordsPerLesson(this.length)).toList();
    final length = this.length - mine.length;
    final facets = course.skillFacets(skill.id);
    final due = _dueSorted(facets, states, now).take(length).toList();
    final fresh = [
      for (final f in facets)
        if (states[f.facetId] == null) f,
    ].take(maxNew.clamp(0, length - due.length)).toList();
    final used = {for (final f in [...due, ...fresh]) f.facetId};
    final known = _byWeakness(
      [for (final f in facets) if (states[f.facetId] != null && !used.contains(f.facetId)) f],
      states,
      scheduler,
      now,
    );
    final ordered = [...due, ...fresh];
    final filler = <SkillFacet>[];
    for (final f in known) {
      if (ordered.length + filler.length >= length) break;
      filler.add(f);
    }
    if (ordered.length + filler.length < length) {
      // Repeat this lesson's facets: new ones first (reinforce what was just introduced).
      final all = [...ordered, ...filler];
      final repeatPool = [...fresh, ...due, ...filler];
      _fill(all, repeatPool, length);
      filler
        ..clear()
        ..addAll(all.skip(ordered.length));
    }
    return LessonPlan(due: due, fresh: fresh, filler: filler, myWords: mine);
  }

  /// Loads the skill's facet states (and the learner's own words with
  /// theirs) once and builds the session.
  Future<LessonSession> start(SessionEnv env) async {
    final pool = await env.loadUserWords();
    final ids = [for (final f in env.course.skillFacets(skill.id)) f.facetId, for (final f in pool.facets) f.facetId];
    final states = await env.store.states(ids);
    return build(env, states);
  }

  LessonSession build(SessionEnv env, Map<String, FacetState> states) {
    final now = env.now();
    final p = plan(env.course, states, scheduler: env.scheduler, now: now, myWordsDue: env.userWords.due(states, now));
    return LessonSession._(env, states, p, focus, length);
  }
}

class LessonSession extends EngineSession {
  LessonSession._(super.env, Map<String, FacetState> states, this.lessonPlan, this.focus, this._length)
      : _queue = List.of(lessonPlan.all),
        super(mode: SessionMode.lesson, states: states);

  final LessonPlan lessonPlan;
  @override
  final LessonFocus focus;
  final int _length;
  final List<SkillFacet> _queue;
  int _cycle = 0;

  @override
  int? get targetLength => _queue.isEmpty && lessonPlan.all.isEmpty ? 0 : _length;

  @override
  Iterable<String> get currentSkillIds => {for (final f in lessonPlan.skillPart) f.skillId};

  @override
  SessionSlot? nextSlot() {
    if (_queue.isNotEmpty) return SessionSlot(_queue.removeAt(0));
    // The plan ran short (some facets could not be generated): cycle the plan.
    final all = lessonPlan.all;
    if (all.isEmpty) return null;
    for (var i = 0; i < all.length; i++) {
      final f = all[_cycle++ % all.length];
      if (!isRecent(f.facetId, window: 1)) return SessionSlot(f);
    }
    return SessionSlot(all[_cycle++ % all.length]);
  }
}

// ==================================================================== lab

/// Exercise lab: any skills, any exercise types, a fixed length. The chosen
/// types override the skills' `exercises` restrictions (the lab is the place
/// to drill one type), but a template is still only used where it can generate.
class LabBuilder {
  const LabBuilder(this.skillIds, this.types, this.length);

  final List<String> skillIds;
  final List<ExerciseType> types;
  final int length;

  Future<LabSession> start(SessionEnv env) async {
    final facets = _facets(env.course);
    final states = await env.store.states(facets.map((f) => f.facetId));
    return build(env, states);
  }

  List<SkillFacet> _facets(CourseData course) {
    final seen = <String>{};
    final templates = [for (final t in types) ?ExerciseSelectorTypes.templateKinds(t)];
    final kinds = {for (final k in templates) ...k};
    return [
      for (final s in skillIds)
        for (final f in course.skillFacets(s))
          if (kinds.contains(f.kind) && seen.add(f.facetId)) f,
    ];
  }

  LabSession build(SessionEnv env, Map<String, FacetState> states) {
    final facets = _facets(env.course);
    final now = env.now();
    final due = _dueSorted(facets, states, now);
    // New facets: round-robin across skills in introduction order.
    final freshBySkill = <String, List<SkillFacet>>{};
    for (final f in facets) {
      if (states[f.facetId] == null) (freshBySkill[f.skillId] ??= []).add(f);
    }
    final fresh = <SkillFacet>[];
    var added = true;
    for (var i = 0; added; i++) {
      added = false;
      for (final l in freshBySkill.values) {
        if (i < l.length) {
          fresh.add(l[i]);
          added = true;
        }
      }
    }
    final dueIds = {for (final f in due) f.facetId};
    final known = _byWeakness(
      [for (final f in facets) if (states[f.facetId] != null && !dueIds.contains(f.facetId)) f],
      states,
      env.scheduler,
      now,
    );
    final order = [...due, ...fresh, ...known];
    return LabSession._(env, states, order, types.toSet(), length);
  }
}

/// Facet kinds each exercise type can serve (mirrors the templates).
abstract final class ExerciseSelectorTypes {
  static Set<FacetKind>? templateKinds(ExerciseType t) => switch (t) {
        ExerciseType.flashcard => const {FacetKind.rec, FacetKind.prod},
        ExerciseType.multipleChoice => const {FacetKind.rec, FacetKind.prod, FacetKind.article},
        ExerciseType.matchPairs => const {FacetKind.rec},
        ExerciseType.conjPick => const {FacetKind.form, FacetKind.infl},
        ExerciseType.conjGrid => const {FacetKind.form, FacetKind.infl},
        ExerciseType.sentenceBuilder => const {FacetKind.prod},
        ExerciseType.cloze => const {FacetKind.form, FacetKind.prod, FacetKind.article, FacetKind.infl},
        ExerciseType.spotError => const {FacetKind.form, FacetKind.article, FacetKind.infl},
        ExerciseType.transform => const {FacetKind.form},
        ExerciseType.listenPick => const {FacetKind.rec},
      };
}

class LabSession extends EngineSession {
  LabSession._(super.env, Map<String, FacetState> states, this._order, this.types, this._length)
      : super(mode: SessionMode.lab, states: states);

  final List<SkillFacet> _order;
  final Set<ExerciseType> types;
  final int _length;
  int _i = 0;

  @override
  int? get targetLength => _order.isEmpty ? 0 : _length;

  @override
  bool get ignoreSkillRestriction => true;

  @override
  Iterable<String> get currentSkillIds => {for (final f in _order) f.skillId};

  @override
  SessionSlot? nextSlot() {
    if (_order.isEmpty) return null;
    final f = _order[_i++ % _order.length];
    return SessionSlot(f, only: types);
  }
}

// ==================================================================== non-stop

/// Endless practice: due facets from every unlocked skill, with a new facet
/// mixed in every [newEvery] exercises; when nothing is due and nothing is
/// new, the weakest facets. A skill is unlocked when every prerequisite is
/// started (at least one of its facets reviewed). Unlocks are re-evaluated
/// after every answer, so finishing a first exercise in a skill can open the
/// next ones mid-run.
class NonStopQueue {
  const NonStopQueue({this.newEvery = 4});

  final int newEvery;

  Future<NonStopSession> start(SessionEnv env) async {
    final states = await env.store.allStates(courseId: env.course.meta.id);
    return build(env, {for (final s in states) s.facetId: s});
  }

  NonStopSession build(SessionEnv env, Map<String, FacetState> states) => NonStopSession._(env, states, newEvery);
}

class NonStopSession extends EngineSession {
  NonStopSession._(super.env, Map<String, FacetState> states, this.newEvery)
      : super(mode: SessionMode.nonstop, states: states);

  final int newEvery;
  int _n = 0;
  int _bonusLeft = 0;
  Set<ExerciseType>? _bonusTypes;

  /// New facets no exercise could be built for in this run: skipped, so one
  /// unbuildable facet never blocks every later new facet (the map's
  /// progress through non-stop alone depends on new facets coming in).
  final Set<String> _unbuildable = {};

  @override
  int? get targetLength => null;

  @override
  void onGenerateFailed(SessionSlot slot) {
    if (!states.containsKey(slot.facet.facetId)) _unbuildable.add(slot.facet.facetId);
  }

  /// Skills whose prerequisites are all started.
  List<Skill> unlockedSkills() {
    final course = env.course;
    bool started(String skillId) => course.skillFacets(skillId).any((f) => states.containsKey(f.facetId));
    return [
      for (final s in course.skills)
        if (s.requires.every(started)) s,
    ];
  }

  /// Progression hook: serve the next [count] exercises with only [types]
  /// (e.g. a timed conjugation blitz). Facets are drawn from unlocked skills.
  void enqueueBonus({required Set<ExerciseType> types, int count = 5}) {
    _bonusTypes = types;
    _bonusLeft = count;
  }

  /// Remaining exercises in the current bonus round.
  int get bonusRemaining => _bonusLeft;

  @override
  SessionSlot? nextSlot() {
    final course = env.course;
    final now = env.now();
    final skills = unlockedSkills();
    final facets = <SkillFacet>[];
    final seen = <String>{};
    for (final s in skills) {
      for (final f in course.skillFacets(s.id)) {
        if (seen.add(f.facetId)) facets.add(f);
      }
    }
    if (facets.isEmpty) return null;
    final st = states;
    final notRecent = [for (final f in facets) if (!isRecent(f.facetId)) f];
    final pool = notRecent.isEmpty ? facets : notRecent;

    if (_bonusLeft > 0 && _bonusTypes != null) {
      final kinds = {for (final t in _bonusTypes!) ...?ExerciseSelectorTypes.templateKinds(t)};
      // Only facets a bonus type can actually be built for (conj_pick skips
      // irregular tables), or the round would be spent on failed generations.
      bool buildable(SkillFacet f) {
        if (!kinds.contains(f.kind)) return false;
        final ctx = genContext(f);
        return _bonusTypes!.any((t) => env.selector.template(t)?.canGenerate(f, ctx) ?? false);
      }
      final candidates = [for (final f in pool) if (buildable(f)) f];
      final fitting = [for (final f in candidates) if (st.containsKey(f.facetId)) f];
      final any = fitting.isNotEmpty ? fitting : candidates;
      if (any.isNotEmpty) {
        _bonusLeft--;
        final f = _byWeakness(any, st, env.scheduler, now).first;
        return SessionSlot(f, only: _bonusTypes);
      }
      _bonusLeft = 0;
    }

    _n++;
    // New facets in skill order (unlocked skills only), so a learner who only
    // plays non-stop still works through the map.
    final fresh = [for (final f in pool) if (!st.containsKey(f.facetId) && !_unbuildable.contains(f.facetId)) f];
    final due = _dueSorted(pool, st, now);
    if (_n % newEvery == 0 && fresh.isNotEmpty) return SessionSlot(fresh.first);
    if (due.isNotEmpty) return SessionSlot(due.first);
    if (fresh.isNotEmpty) return SessionSlot(fresh.first);
    final weakest = _byWeakness([for (final f in pool) if (st.containsKey(f.facetId)) f], st, env.scheduler, now);
    if (weakest.isNotEmpty) {
      // A little variety among the weakest few.
      return SessionSlot(weakest[env.random.nextInt(weakest.length < 3 ? weakest.length : 3)]);
    }
    return SessionSlot(pool[env.random.nextInt(pool.length)]);
  }
}

// ==================================================================== fading

/// "What's fading": due and lowest-recall facets across all skills.
class FadingBuilder {
  const FadingBuilder({this.length = 12});

  final int length;

  Future<FadingSession> start(SessionEnv env) async {
    final states = await env.store.allStates(courseId: env.course.meta.id);
    return build(env, {for (final s in states) s.facetId: s});
  }

  FadingSession build(SessionEnv env, Map<String, FacetState> states) {
    final course = env.course;
    final now = env.now();
    final seen = <String>{};
    final facets = <SkillFacet>[
      for (final s in course.skills)
        for (final f in course.skillFacets(s.id))
          if (states.containsKey(f.facetId) && seen.add(f.facetId)) f,
    ];
    final due = _dueSorted(facets, states, now);
    final dueIds = {for (final f in due) f.facetId};
    final rest = _byWeakness([for (final f in facets) if (!dueIds.contains(f.facetId)) f], states, env.scheduler, now);
    final order = [...due, ...rest].take(length).toList();
    return FadingSession._(env, states, order, length);
  }
}

class FadingSession extends EngineSession {
  FadingSession._(super.env, Map<String, FacetState> states, this._order, this._length)
      : super(mode: SessionMode.review, states: states);

  final List<SkillFacet> _order;
  final int _length;
  int _i = 0;

  @override
  int? get targetLength => _order.isEmpty ? 0 : _length.clamp(0, _order.length);

  @override
  SessionSlot? nextSlot() {
    if (_order.isEmpty) return null;
    return SessionSlot(_order[_i++ % _order.length]);
  }
}
