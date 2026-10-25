/// "My words" in the engine: the learner's own words ([UserWord]) as facets
/// with FSRS scheduling like pack items, their exercises, the "My words"
/// session, and the due ones mixed into lessons as reviews. See
/// docs/engine.md, "My words".
///
/// A user word has two facets, `{course}:user~<uuid>#rec` and `#prod`,
/// planned under the pseudo skill [kMyWordsSkillId] (no pack has it, so
/// nothing on the map, in the skill stats or in progression's tiers sees
/// them). They are generated here, not by the pack templates (a user word is
/// no course item), as the existing exercise types, so the UI and grading
/// are unchanged:
///
/// * **flashcard** (recognise and produce; the first exposure),
/// * **multiple choice**: the word → its meaning (`#rec`), the meaning → the
///   word (`#prod`); wrong options come from the learner's other words first,
///   then from the course's lexicon of the same part of speech,
/// * **cloze over the whole word** (`#prod`, "Write the word"): typed recall
///   for keyboard and handwriting learners, a choice of words for tap learners
///   (typing is never required).
library;

import 'dart:math';

import '../../core/interfaces/course_data.dart';
import '../../core/interfaces/progress_store.dart';
import '../../core/interfaces/session.dart';
import '../../core/models/course.dart';
import '../../core/models/exercise.dart';
import '../../core/models/facet.dart';
import '../../core/models/progress.dart';
import '../../core/models/user_word.dart';
import '../gen_context.dart';
import '../strings.dart';
import '../template.dart';
import '../text/normalize.dart';
import 'engine_session.dart';

/// The exercise types a user word can get.
const Set<ExerciseType> kUserWordTypes = {ExerciseType.flashcard, ExerciseType.multipleChoice, ExerciseType.cloze};

/// Type weights per stage, like the selector's `kStageAffinity`.
const Map<FacetKind, Map<ExerciseType, Map<FacetStage, double>>> _weights = {
  FacetKind.rec: {
    ExerciseType.flashcard: {FacetStage.fresh: 5, FacetStage.learning: 1, FacetStage.stable: 0.3},
    ExerciseType.multipleChoice: {FacetStage.fresh: 1, FacetStage.learning: 3, FacetStage.stable: 3},
  },
  FacetKind.prod: {
    ExerciseType.flashcard: {FacetStage.fresh: 5, FacetStage.learning: 1, FacetStage.stable: 0.3},
    ExerciseType.multipleChoice: {FacetStage.fresh: 1, FacetStage.learning: 3, FacetStage.stable: 1.5},
    ExerciseType.cloze: {FacetStage.fresh: 0, FacetStage.learning: 2, FacetStage.stable: 3},
  },
};

/// The words of one course, ready for sessions (deleted and empty ones left out).
class UserWordPool {
  UserWordPool(this.courseId, Iterable<UserWord> words)
    : words =
          [
            for (final w in words)
              if (!w.removed && w.word.trim().isNotEmpty && w.translation.trim().isNotEmpty) w,
          ]..sort((a, b) {
            final c = a.created.compareTo(b.created);
            return c != 0 ? c : a.id.compareTo(b.id);
          }) {
    _byItem = {for (final w in this.words) w.itemId(courseId): w};
  }

  static final UserWordPool empty = UserWordPool('', const []);

  final String courseId;

  /// Oldest first (the order new words are introduced in).
  final List<UserWord> words;
  late final Map<String, UserWord> _byItem;

  bool get isEmpty => words.isEmpty;

  UserWord? wordOf(String itemId) => _byItem[itemId];

  /// The word whose facet is [facetId].
  UserWord? wordOfFacet(String facetId) {
    final hash = facetId.lastIndexOf('#');
    return hash <= 0 ? null : _byItem[facetId.substring(0, hash)];
  }

  /// [w]'s two facets: recognise, then produce.
  List<SkillFacet> facetsOf(UserWord w) => [
    SkillFacet(
      skillId: kMyWordsSkillId,
      facetId: w.recFacet(courseId),
      itemId: w.itemId(courseId),
      kind: FacetKind.rec,
      ord: 0,
    ),
    SkillFacet(
      skillId: kMyWordsSkillId,
      facetId: w.prodFacet(courseId),
      itemId: w.itemId(courseId),
      kind: FacetKind.prod,
      ord: 1,
    ),
  ];

  /// Every facet, oldest word first.
  List<SkillFacet> get facets => [for (final w in words) ...facetsOf(w)];

  /// The facet [facetId] (null when the word is gone).
  SkillFacet? facet(String facetId) {
    final w = wordOfFacet(facetId);
    if (w == null) return null;
    for (final f in facetsOf(w)) {
      if (f.facetId == facetId) return f;
    }
    return null;
  }

  /// Due facets ([states]), most overdue first.
  List<SkillFacet> due(Map<String, FacetState> states, DateTime now) {
    final out = [
      for (final f in facets)
        if (states[f.facetId] case final s? when s.isDue(now)) f,
    ];
    out.sort((a, b) => states[a.facetId]!.due.compareTo(states[b.facetId]!.due));
    return out;
  }

  // -------------------------------------------------------------- exercises

  /// An exercise for [facet] (a user-word facet of this pool), or null when
  /// the word is gone or no allowed type can be built. [only] restricts the
  /// types; [retryType] (a retry) is tried first; [avoid] weighs less.
  Exercise? generate(
    SkillFacet facet, {
    required CourseData course,
    required SessionOptions options,
    required Random random,
    required FacetState? state,
    required String Function() nextId,
    StagePolicy stagePolicy = const StagePolicy(),
    Set<ExerciseType>? only,
    ExerciseType? retryType,
    ExerciseType? avoid,
  }) {
    final w = wordOf(facet.itemId);
    final weights = _weights[facet.kind];
    if (w == null || weights == null) return null;
    final stage = stagePolicy.stageOf(state);
    final allowed = [
      for (final t in weights.keys)
        if (only == null || only.contains(t)) t,
    ];
    if (allowed.isEmpty) return null;
    // A retry asks the missed type again first.
    final order = <ExerciseType>[if (retryType != null && allowed.contains(retryType)) retryType];
    // Then a weighted draw without replacement; zero-weight types last.
    final rest = [
      for (final t in allowed)
        if (!order.contains(t)) t,
    ];
    double weightOf(ExerciseType t) => (weights[t]![stage] ?? 0) * (t == avoid ? 0.5 : 1);
    while (rest.any((t) => weightOf(t) > 0)) {
      final total = rest.fold<double>(0, (s, t) => s + weightOf(t));
      var r = random.nextDouble() * total;
      var pick = rest.firstWhere((t) => weightOf(t) > 0);
      for (final t in rest) {
        r -= weightOf(t);
        if (r < 0 && weightOf(t) > 0) {
          pick = t;
          break;
        }
      }
      order.add(pick);
      rest.remove(pick);
    }
    order.addAll(rest);
    final ctx = _Ctx(this, w, facet, course, options, random, nextId);
    for (final t in order) {
      final e = switch (t) {
        ExerciseType.flashcard => ctx.flashcard(),
        ExerciseType.multipleChoice => ctx.multipleChoice(),
        ExerciseType.cloze => ctx.cloze(),
        _ => null,
      };
      if (e != null) return e;
    }
    return null;
  }
}

class _Ctx {
  _Ctx(this.pool, this.w, this.facet, this.course, this.options, this.random, this.nextId);
  final UserWordPool pool;
  final UserWord w;
  final SkillFacet facet;
  final CourseData course;
  final SessionOptions options;
  final Random random;
  final String Function() nextId;

  bool get rec => facet.kind == FacetKind.rec;
  String get lang => options.sourceLang;

  Item? get _lemma => w.lemmaId == null ? null : course.item(w.lemmaId!);

  String? get _pos => w.pos ?? _lemma?.pos;

  /// Course items for wrong options: the same part of speech near the word's
  /// frequency (its lemma's, else a random middle rank), else nouns and verbs.
  List<Item> _courseItems() {
    final pos = _pos;
    final freq = _lemma?.freq ?? (200 + random.nextInt(2000));
    final out = <Item>[];
    for (final p in [
      ?pos,
      if (pos == null) ...['noun', 'verb', 'adj'],
    ]) {
      out.addAll(course.itemsNearFreq(p, freq, limit: 40));
    }
    out.removeWhere((i) => i.id == w.lemmaId);
    return out;
  }

  Set<String> _keys(Iterable<String> xs) => {for (final x in xs) foldAnswer(x)};

  /// Up to three wrong meanings: none sharing a meaning with the word.
  List<String> _wrongMeanings() {
    final mine = _keys([w.translation, ...w.meanings]);
    bool overlaps(Iterable<String> meanings) => _keys(meanings).any(mine.contains);
    final picker = OptionPicker(forbidden: [w.translation, ...w.meanings]);
    final others = [
      for (final o in pool.words)
        if (o.id != w.id && !overlaps([o.translation, ...o.meanings])) o.translation,
    ];
    final fromCourse = [
      for (final i in _courseItems())
        if (i.glosses(lang).isNotEmpty && !overlaps(i.glosses(lang))) i.gloss(lang),
    ];
    picker.addGroups([others.take(12), fromCourse], random);
    return picker.picked;
  }

  /// Up to three wrong words: other words of the learner first, then course lemmas.
  List<String> _wrongWords() {
    final mine = _keys(w.meanings);
    final picker = OptionPicker(forbidden: [w.word]);
    final others = [
      for (final o in pool.words)
        if (o.id != w.id && !_keys(o.meanings).any(mine.contains)) o.word,
    ];
    final fromCourse = [
      for (final i in _courseItems())
        if (!_keys(i.glosses(lang)).any(mine.contains)) i.lemma,
    ];
    picker.addGroups([others.take(12), fromCourse], random);
    return picker.picked;
  }

  Exercise flashcard() => FlashcardExercise(
    id: nextId(),
    facetId: facet.facetId,
    instruction: instruction(rec ? 'flashcard.rec' : 'flashcard.prod', lang),
    front: rec ? w.word : w.translation,
    back: rec ? [w.translation, ?w.example].join('\n') : w.word,
    direction: rec ? Direction.recognize : Direction.produce,
    hint: _pos,
  );

  Exercise? multipleChoice() {
    final wrong = rec ? _wrongMeanings() : _wrongWords();
    if (wrong.length < 2) return null;
    final (opts, correct) = placeOptions(rec ? w.translation : w.word, wrong, random);
    return MultipleChoiceExercise(
      id: nextId(),
      facetId: facet.facetId,
      instruction: instruction(rec ? 'mc.rec' : 'mc.prod', lang),
      prompt: rec ? w.word : w.translation,
      options: opts,
      correctIndex: correct,
      direction: rec ? Direction.recognize : Direction.produce,
    );
  }

  /// "Write the word": the whole word is the gap, its meaning the hint.
  Exercise? cloze() {
    if (rec) return null;
    final typed = options.preferredInput == InputMode.keyboard || options.preferredInput == InputMode.ink;
    List<String>? opts;
    int? correct;
    if (!typed) {
      final wrong = _wrongWords();
      if (wrong.length < 2) return null;
      (opts, correct) = placeOptions(w.word, wrong, random);
    }
    return ClozeExercise(
      id: nextId(),
      facetId: facet.facetId,
      instruction: instruction('cloze.word', lang),
      before: '',
      after: '',
      expected: w.word,
      accepted: [w.word],
      options: opts,
      correctIndex: correct,
      hint: w.translation,
    );
  }
}

/// Plans the "My words" session: due facets (most overdue first), then new
/// words (up to [maxNew] facets, oldest word first, recognise before
/// produce), then the weakest of the rest; each facet once, at most
/// [length]. Wrong answers come back as in any session.
class MyWordsBuilder {
  const MyWordsBuilder({this.length = 12, this.maxNew = 6});

  final int length;
  final int maxNew;

  List<SkillFacet> plan(
    UserWordPool pool,
    Map<String, FacetState> states, {
    required Scheduler scheduler,
    required DateTime now,
  }) {
    final due = pool.due(states, now);
    final fresh = [
      for (final f in pool.facets)
        if (states[f.facetId] == null) f,
    ].take(maxNew);
    final used = {
      for (final f in [...due, ...fresh]) f.facetId,
    };
    final rest =
        [
          for (final f in pool.facets)
            if (!used.contains(f.facetId) && states[f.facetId] != null) f,
        ]..sort(
          (a, b) => scheduler
              .retrievability(states[a.facetId], now)
              .compareTo(scheduler.retrievability(states[b.facetId], now)),
        );
    return [...due, ...fresh, ...rest].take(length).toList();
  }

  Future<MyWordsSession> start(SessionEnv env) async {
    final pool = await env.loadUserWords();
    final states = await env.store.states(pool.facets.map((f) => f.facetId));
    return MyWordsSession._(env, states, plan(pool, states, scheduler: env.scheduler, now: env.now()));
  }
}

/// The "My words" session (mode [SessionMode.myWords]).
class MyWordsSession extends EngineSession {
  MyWordsSession._(super.env, Map<String, FacetState> states, this.slots)
    : super(mode: SessionMode.myWords, states: states);

  final List<SkillFacet> slots;
  int _i = 0;

  @override
  int? get targetLength => slots.length;

  @override
  SessionSlot? nextSlot() => _i < slots.length ? SessionSlot(slots[_i++]) : null;
}

/// How many due user words a lesson of [length] mixes in: about one in six
/// exercises (1 for a quick lesson, 2 for a normal one, 3 for a long one).
int myWordsPerLesson(int length) => length <= 0 ? 0 : max(1, length ~/ 6);
