/// Grammar-gating checks that run against any [CourseData] with gating data
/// (`meta.base_features`, `sentence_features`, `skill_features`), next to
/// [runTemplateValidity] (which assumes every sentence is available: the
/// "everything known" check).
///
/// For a simulated learner (the skills they started) and the skills they
/// practice, every template generates exercises through a [SentenceGate],
/// and each exercise is checked against an expectation computed here,
/// independently of the gate's code:
/// * every sentence it shows uses only known grammar features (base, started
///   and current skills, and their prerequisites);
/// * its main sentence has at most the cap of unknown words (aligned to items
///   outside the started and current skills = 1, unaligned words that are no
///   name or number = 2);
/// * a transform's target tense is known;
/// * the exercise is valid ([validateExercise]).
library;

import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';

import 'template_validity.dart';

/// What the learner knows, computed independently of [SentenceGate].
class Knowledge {
  Knowledge(this.course, {required Iterable<String> started, Iterable<String> current = const []}) {
    final anchors = {...started, ...current};
    final closure = <String>{};
    void visit(String id) {
      if (!closure.add(id)) return;
      for (final r in course.skill(id)?.requires ?? const <String>[]) {
        visit(r);
      }
    }

    anchors.forEach(visit);
    features = {...course.meta.baseFeatures, for (final s in closure) ...course.skillFeatures(s)};
    items = {for (final s in anchors) for (final i in course.skillItems(s)) i.id};
  }

  final CourseData course;
  late final Set<String> features;
  late final Set<String> items;

  static final Expando<Set<String>> _names = Expando();

  /// Unaligned capitalized words seen after the first word of a sentence.
  Set<String> get names => _names[course] ??= {
        for (final s in CourseIndex.of(course).allSentences)
          for (final (i, t) in [for (final t in s.tokens) if (t.isWord) t].indexed)
            if (i > 0 && t.lex == null && t.t.isNotEmpty && t.t[0] != t.t[0].toLowerCase()) t.t,
      };

  Set<String> unknownFeatures(String sentenceId) =>
      course.sentenceFeatures(sentenceId).where((f) => !features.contains(f)).toSet();

  int unknownWords(Sentence s) {
    var n = 0;
    final words = [for (final t in s.tokens) if (t.isWord) t];
    for (final (i, t) in words.indexed) {
      if (t.lex != null) {
        if (!items.contains(t.lex)) n++;
        continue;
      }
      final number = RegExp(r'^[0-9]').hasMatch(t.t);
      final capital = t.t.isNotEmpty && t.t[0] != t.t[0].toLowerCase();
      final name = capital && (i > 0 || names.contains(t.t));
      if (!number && !name) n += 2;
    }
    return n;
  }
}

/// The sentences an exercise shows: (main sentence, other target-language
/// sentences shown as options).
(Sentence?, List<Sentence>) shownSentences(Exercise e, CourseData c) {
  Sentence? byId(String? id) => id == null ? null : c.sentence(id);
  final byText = _textIndex[c] ??= {for (final s in CourseIndex.of(c).allSentences) s.text: s};
  return switch (e) {
    ClozeExercise() => (byId(e.sentenceId), const []),
    SpotErrorExercise() => (byId(e.sentenceId), const []),
    TransformExercise() => (byId(e.sentenceId), const []),
    SentenceBuilderExercise() => (byId(e.sentenceId), const []),
    MultipleChoiceExercise(isSentence: true, direction: Direction.recognize) => (byText[e.prompt], const []),
    ListenPickExercise(isSentence: true) => (
        byId(e.sentenceId),
        [for (final (i, o) in e.options.indexed) if (i != e.correctIndex && byText[o] != null) byText[o]!],
      ),
    MultipleChoiceExercise(isSentence: true) => (
        byText[e.options[e.correctIndex]],
        [for (final (i, o) in e.options.indexed) if (i != e.correctIndex && byText[o] != null) byText[o]!],
      ),
    _ => (null, const []),
  };
}

final Expando<Map<String, Sentence>> _textIndex = Expando();

/// Problems of one exercise shown to a learner with [known] and [cap].
List<String> gatingProblems(Exercise e, CourseData c, Knowledge known, int cap, {SkillFacet? facet}) {
  final out = <String>[];
  final (main, others) = shownSentences(e, c);
  if (main != null) {
    final f = known.unknownFeatures(main.id);
    if (f.isNotEmpty) out.add('sentence ${main.id} "${main.text}" uses unknown features $f');
    final u = known.unknownWords(main);
    if (u > cap) out.add('sentence ${main.id} "${main.text}" has $u unknown words (cap $cap)');
  }
  for (final s in others) {
    final f = known.unknownFeatures(s.id);
    if (f.isNotEmpty) out.add('option ${s.id} "${s.text}" uses unknown features $f');
  }
  if (e is TransformExercise && facet?.tense != null && !known.features.contains('tense:${facet!.tense}')) {
    out.add('transform into unknown tense ${facet.tense}');
  }
  return out;
}

bool isSentenceExercise(Exercise e) =>
    e is ClozeExercise ||
    e is SpotErrorExercise ||
    e is TransformExercise ||
    e is SentenceBuilderExercise ||
    (e is MultipleChoiceExercise && e.isSentence) ||
    (e is ListenPickExercise && e.isSentence);

class GatedReport {
  final List<String> failures = [];

  /// Exercises generated per template label.
  final Map<String, int> generated = {};

  /// Sentence-based exercises per scenario.
  final Map<String, int> sentenceExercises = {};

  int get totalSentenceExercises => sentenceExercises.values.fold(0, (a, b) => a + b);
}

/// Generates up to [perPair] exercises per (skill, template, cap) for a
/// learner who started [started], practicing each of [skills] (as the
/// current skill, or with no current skill when [asCurrent] is false: a
/// non-stop / review session over started skills).
void runGatedValidity(
  CourseData course,
  GatedReport report, {
  required String scenario,
  required Set<String> started,
  required Iterable<String> skills,
  bool asCurrent = true,
  int perPair = 6,
  String? lang,
}) {
  final l = lang ?? course.meta.translations.first;
  final now = DateTime.utc(2026, 10, 14, 12);
  final templates = validityTemplates();
  for (final skillId in skills) {
    final skill = course.skill(skillId)!;
    final current = asCurrent ? [skillId] : const <String>[];
    final gate = SentenceGate(course, started: started, current: current);
    final known = Knowledge(course, started: started, current: current);
    final facets = course.skillFacets(skillId);
    for (final focus in [LessonFocus.mixed, LessonFocus.grammar]) {
      final cap = SentenceGate.capFor(focus, skill);
      if (focus == LessonFocus.grammar && cap == SentenceGate.capFor(LessonFocus.mixed, skill)) continue;
      for (final MapEntry(key: label, value: t) in templates.entries) {
        final usable = [
          for (final f in facets)
            if (t.supports(f) && (!CourseIndex.of(course).recognitionOnly(f) || kRecognitionTypes.contains(t.type))) f,
        ];
        if (usable.isEmpty) continue;
        GenContext ctx(int i, SkillFacet f) => GenContext(
              course: course,
              options: SessionOptions(sourceLang: l, listening: true),
              random: Random(i * 131 + skillId.hashCode),
              states: {
                if (i % 3 == 1) f.facetId: _state(f.facetId, 2, now),
                if (i % 3 == 2) f.facetId: _state(f.facetId, 40, now),
              },
              skill: skill,
              now: now,
              gate: gate,
              wordCap: cap,
              nextId: () => '$label#$i',
            );
        final applicable = [for (final f in usable) if (t.canGenerate(f, ctx(0, f))) f];
        if (applicable.isEmpty) continue;
        var count = 0;
        for (var i = 0; i < perPair * 4 && count < perPair; i++) {
          final f = applicable[i % applicable.length];
          final e = t.generate(f, ctx(i, f));
          if (e == null) continue;
          count++;
          report.generated[label] = (report.generated[label] ?? 0) + 1;
          if (isSentenceExercise(e)) {
            report.sentenceExercises[scenario] = (report.sentenceExercises[scenario] ?? 0) + 1;
          }
          final where = '[$scenario $l $skillId $label cap=$cap ${f.facetId} i=$i]';
          for (final p in gatingProblems(e, course, known, cap, facet: f)) {
            report.failures.add('$where $p\n${formatExercise(e)}');
          }
          for (final p in validateExercise(e, t, course, l)) {
            report.failures.add('$where $p\n${formatExercise(e)}');
          }
        }
      }
    }
  }
}

FacetState _state(String id, double stability, DateTime now) => FacetState(
      facetId: id,
      stability: stability,
      difficulty: 5,
      due: now.add(Duration(days: stability.round())),
      lastReview: now.subtract(const Duration(days: 1)),
      reps: 3,
      lapses: 0,
      phase: CardPhase.review,
    );
