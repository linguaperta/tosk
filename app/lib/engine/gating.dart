/// Grammar gating and sentence variety: which course sentences a learner may
/// meet in an exercise, and which of those to prefer.
///
/// See docs/ARCHITECTURE.md ("Grammar gating") and docs/engine.md
/// ("Grammar gating and sentence variety").
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../core/interfaces/course_data.dart';
import '../core/interfaces/progress_store.dart';
import '../core/interfaces/session.dart';
import '../core/models/course.dart';
import 'course_index.dart';

/// What a learner knows at the start of a session: the grammar features and
/// the words of the skills they have started, plus the session's current
/// skills. Sentence-based templates only use sentences it [allows].
///
/// * `knownFeatures` = `meta.base_features` ∪ the features of every started
///   or current skill and of their prerequisites (transitively: a skill's
///   sentences are built on its prerequisites' grammar, see the pipeline's
///   home-skill rule).
/// * `knownItems` = the items of every started or current skill (no
///   prerequisite closure: vocabulary is counted strictly).
/// * Unknown words of a sentence: word tokens aligned to an item outside
///   `knownItems` count 1. An unaligned word counts 0 when it is a name or a
///   number ([CourseIndex.isNameOrNumber]) and 2 otherwise: the word is
///   unknown and so is its grammar (the pipeline cannot tag the features of
///   a word it could not align, e.g. a passato remoto `Comprai`), so such a
///   sentence never passes the grammar cap and only alone the vocabulary cap.
///
/// A started skill is one with at least one reviewed facet. [markStarted]
/// adds skills during a session (the facet's skills after each answer).
///
/// Courses without `base_features` (packs built before grammar gating, or a
/// course that does not declare it) are not gated: [supports] is false and
/// sessions then use no gate at all.
class SentenceGate {
  SentenceGate(this.course, {Iterable<String> started = const [], Iterable<String> current = const []}) {
    _started.addAll(started);
    _current.addAll(current);
    _recompute();
  }

  /// At most this many unknown words per sentence with a grammar focus or in
  /// a grammar skill.
  static const int grammarCap = 1;

  /// At most this many unknown words per sentence otherwise.
  static const int vocabCap = 2;

  /// Whether [course] carries grammar-gating data.
  static bool supports(CourseData course) => course.meta.baseFeatures.isNotEmpty;

  /// The unknown-word cap for an exercise in [skill] under [focus].
  static int capFor(LessonFocus focus, Skill? skill) =>
      focus == LessonFocus.grammar || skill?.kind == SkillKind.grammar ? grammarCap : vocabCap;

  /// Skills with at least one facet in [reviewedFacetIds].
  static Set<String> startedSkills(CourseData course, Iterable<String> reviewedFacetIds) => {
        for (final f in reviewedFacetIds) ...course.skillsForFacet(f),
      };

  final CourseData course;
  final Set<String> _started = {};
  final Set<String> _current = {};
  Set<String> _knownFeatures = const {};
  Set<String> _knownItems = const {};
  final Map<String, int> _unknown = {};
  final Map<String, Object?> _memo = {};

  CourseIndex get index => CourseIndex.of(course);

  Set<String> get startedSkillIds => UnmodifiableSetView(_started);
  Set<String> get currentSkillIds => UnmodifiableSetView(_current);
  Set<String> get knownFeatures => UnmodifiableSetView(_knownFeatures);
  Set<String> get knownItems => UnmodifiableSetView(_knownItems);

  void _recompute() {
    final anchors = {..._started, ..._current};
    final closure = <String>{};
    final stack = [...anchors];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      if (!closure.add(id)) continue;
      stack.addAll(course.skill(id)?.requires ?? const []);
    }
    _knownFeatures = {
      ...course.meta.baseFeatures,
      for (final s in closure) ...course.skillFeatures(s),
    };
    _knownItems = {
      for (final s in anchors)
        for (final i in course.skillItems(s)) i.id,
    };
    _unknown.clear();
    _memo.clear();
  }

  /// Marks [skillIds] as started; returns whether anything changed.
  bool markStarted(Iterable<String> skillIds) {
    var changed = false;
    for (final s in skillIds) {
      if (_started.add(s) && !_current.contains(s)) changed = true;
    }
    if (changed) _recompute();
    return changed;
  }

  bool featureKnown(String feature) => _knownFeatures.contains(feature);

  late final Set<String> _courseFeatures = {for (final s in course.skills) ...course.skillFeatures(s.id)};

  /// Whether forms of [tense] may be shown (as wrong options or tiles too):
  /// the tense is known, and so are its irregular forms when the course
  /// teaches those separately (`irregular:futuro`, `irregular:verleden_tijd`).
  bool tenseShowable(String tense) =>
      featureKnown('tense:$tense') &&
      (!_courseFeatures.contains('irregular:$tense') || featureKnown('irregular:$tense'));

  /// Whether every grammar feature of the sentence is known.
  bool featuresKnown(String sentenceId) => course.sentenceFeatures(sentenceId).every(_knownFeatures.contains);

  /// Unknown words of [s] (see the class comment), cached.
  int unknownWords(Sentence s) => _unknown[s.id] ??= _count(s);

  int _count(Sentence s) {
    final ix = index;
    var n = 0;
    var first = true;
    for (final t in s.tokens) {
      if (!t.isWord) continue;
      final lex = t.lex;
      if (lex != null) {
        if (!_knownItems.contains(lex)) n++;
      } else if (!ix.isNameOrNumber(t, first: first)) {
        n += 2;
      }
      first = false;
    }
    return n;
  }

  /// Whether a sentence may be shown: known features and at most [cap] unknown words.
  bool allows(Sentence s, int cap) => featuresKnown(s.id) && unknownWords(s) <= cap;

  /// Memoizes a value that depends on this gate's state (cleared by [markStarted]).
  T memo<T>(String key, T Function() compute) {
    if (_memo.containsKey(key)) return _memo[key] as T;
    final v = compute();
    _memo[key] = v;
    return v;
  }
}

/// Recently seen sentences of one course, to prefer unseen or least recently
/// seen sentences, and never to repeat a sentence within a session while
/// others are left.
///
/// Persisted as a bounded LRU ([capacity] ids, oldest first, JSON) in the
/// progress store's key/value settings under [settingKey]. [save] merges the
/// session's sentences into what is stored at that moment (read, merge,
/// write, serialized per key within the process), so concurrent sessions
/// never drop each other's exposures.
class SentenceHistory {
  SentenceHistory({Iterable<String> recent = const [], this.capacity = defaultCapacity}) {
    for (final id in recent) {
      _seq[id] = _next++;
    }
    _loaded = _next;
  }

  static const int defaultCapacity = 1000;

  static String settingKey(String courseId) => 'engine.recent_sentences.$courseId';

  final int capacity;
  final Map<String, int> _seq = {};
  int _next = 0;
  int _loaded = 0;
  final List<String> _session = [];
  final Set<String> _sessionSet = {};

  /// Sentences used in this session, in order of first use.
  List<String> get sessionSentences => UnmodifiableListView(_session);

  bool usedInSession(String id) => _sessionSet.contains(id);

  bool seen(String id) => _seq.containsKey(id);

  /// 0 for a sentence never seen; for one seen before, 1 (seen [capacity]
  /// sentences ago or longer) up to 3 (seen last).
  double penalty(String id) {
    final q = _seq[id];
    if (q == null) return 0;
    final age = _next - 1 - q;
    final recentness = 1 - age / capacity;
    return 1 + 2 * (recentness < 0 ? 0 : recentness);
  }

  /// Records that [id] was shown now.
  void use(String id) {
    _seq[id] = _next++;
    if (_sessionSet.add(id)) _session.add(id);
  }

  /// [stored] (oldest first) with [session] appended (moved to the end when
  /// already present), trimmed to the last [capacity] ids.
  static List<String> merge(List<String> stored, List<String> session, int capacity) {
    final s = session.toSet();
    final out = [for (final id in stored) if (!s.contains(id)) id, ...session];
    return out.length <= capacity ? out : out.sublist(out.length - capacity);
  }

  static List<String> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final v = jsonDecode(raw);
      if (v is List) return [for (final x in v) if (x is String) x];
    } on FormatException {
      // A corrupt value is ignored (and replaced on the next save).
    }
    return const [];
  }

  static Future<SentenceHistory> load(ProgressStore store, String courseId, {int capacity = defaultCapacity}) async {
    try {
      final raw = await store.getSetting(settingKey(courseId));
      return SentenceHistory(recent: decode(raw), capacity: capacity);
    } catch (_) {
      return SentenceHistory(capacity: capacity);
    }
  }

  static final Map<String, Future<void>> _saving = {};

  /// Merges this session's sentences into the stored history. Safe to call
  /// more than once (only sentences not saved yet are written).
  Future<void> save(ProgressStore store, String courseId) {
    final pending = List.of(_session.skip(_saved));
    _saved = _session.length;
    if (pending.isEmpty) return Future.value();
    final key = settingKey(courseId);
    final previous = _saving[key] ?? Future<void>.value();
    final done = previous.then((_) async {
      try {
        final stored = decode(await store.getSetting(key));
        await store.setSetting(key, jsonEncode(merge(stored, pending, capacity)));
      } catch (_) {
        // Variety is best effort: a failing store never breaks a session.
      }
    });
    _saving[key] = done;
    return done.whenComplete(() {
      if (identical(_saving[key], done)) _saving.remove(key);
    });
  }

  int _saved = 0;

  /// Number of ids loaded from the store when the session started.
  int get loadedCount => _loaded;
}
