/// Human-readable rendering of exercises: one-line prompts (stored with
/// mistakes) and a multi-line debug format used by `tool/sample_exercises.dart`.
library;

import 'dart:math';

import '../../core/interfaces/course_data.dart';
import '../../core/interfaces/session.dart';
import '../../core/models/exercise.dart';
import '../../core/models/facet.dart';
import '../gating.dart';
import '../gen_context.dart';
import '../template.dart';
import '../templates/templates.dart';

/// A one-line description of what the learner was asked.
String exercisePrompt(Exercise e) {
  final body = switch (e) {
    FlashcardExercise() => e.front,
    MultipleChoiceExercise() => '${e.prompt}${e.hint == null ? '' : ' (${e.hint})'} — ${e.options.join(' / ')}',
    MatchPairsExercise() => '${e.left.join(', ')} ↔ ${e.right.join(', ')}',
    ConjPickExercise() => e.inflection
        ? '${e.lemma} (${e.personLabel}): ${e.stem}___ — ${e.endings.join(' / ')}'
        : '${e.lemma} (${e.personLabel}, ${e.tenseLabel}): ${e.stem}___ — ${e.endings.join(' / ')}',
    ConjGridExercise() => '${e.lemma} (${e.tenseLabel}): ${[
        for (final c in e.cells) '${c.personLabel} ${c.prefilled ? c.expected : '___'}',
      ].join(', ')}',
    SentenceBuilderExercise() => e.prompt,
    ClozeExercise() => '${e.before}___${e.after}${e.hint == null ? '' : ' (${e.hint})'}',
    SpotErrorExercise() => renderSpotError(e),
    TransformExercise() => '${e.source} ${e.targetDescription}',
  };
  if (e.instruction.isEmpty) return body;
  // "What does this mean? ciao", not "What does this mean?: ciao".
  final sep = RegExp(r'[?:!.]$').hasMatch(e.instruction.trimRight()) ? ' ' : ': ';
  return '${e.instruction.trimRight()}$sep$body';
}

/// Multi-line debug rendering with the correct answer marked by `*`.
String formatExercise(Exercise e) {
  final b = StringBuffer('[${e.type.id}] ${e.facetId}${e.skillId == null ? '' : '  (skill ${e.skillId})'}\n');
  b.writeln('  ${e.instruction}');
  String opts(List<String> o, int correct) =>
      [for (var i = 0; i < o.length; i++) '${i == correct ? '*' : ' '}${o[i]}'].join('  |  ');
  switch (e) {
    case FlashcardExercise():
      b.writeln('  ${e.front}  =>  ${e.back}${e.hint == null ? '' : '   [${e.hint}]'}');
    case MultipleChoiceExercise():
      b.writeln('  ${e.prompt}${e.hint == null ? '' : '   (${e.hint})'}');
      b.writeln('  ${opts(e.options, e.correctIndex)}');
    case MatchPairsExercise():
      for (var i = 0; i < e.left.length; i++) {
        b.writeln('  ${e.left[i]}  =  ${e.right[e.solution[i]!]}');
      }
    case ConjPickExercise():
      b.writeln(e.inflection
          ? '  ${e.lemma} (${e.gloss}) — ${e.personLabel}'
          : '  ${e.lemma} (${e.gloss}) — ${e.personLabel}, ${e.tenseLabel}');
      b.writeln('  ${e.stem}___   ${opts(e.endings, e.correctIndex)}   => ${e.fullForm}');
    case ConjGridExercise():
      b.writeln('  ${e.lemma} (${e.gloss}) — ${e.tenseLabel}');
      for (final c in e.cells) {
        b.writeln('    ${c.personLabel.padRight(8)} ${c.prefilled ? '(${c.expected})' : c.expected}');
      }
      b.writeln('  tiles: ${e.tiles.join(' · ')}');
    case SentenceBuilderExercise():
      b.writeln('  ${e.prompt}');
      b.writeln('  tiles: ${e.tiles.join(' · ')}');
      for (final a in e.answers) {
        b.writeln('  => ${a.join(' ')}');
      }
    case ClozeExercise():
      b.writeln('  ${e.before}___${e.after}${e.hint == null ? '' : '   (${e.hint})'}');
      if (e.translation != null) b.writeln('  "${e.translation}"');
      if (e.options != null) {
        b.writeln('  ${opts(e.options!, e.correctIndex!)}');
      } else {
        b.writeln('  free text => ${e.accepted.join(' / ')}');
      }
    case SpotErrorExercise():
      b.writeln('  ${renderSpotError(e)}');
      if (e.translation != null) b.writeln('  "${e.translation}"');
      b.writeln('  error: "${e.tokens[e.errorIndex]}" -> "${e.correction}"');
    case TransformExercise():
      b.writeln('  ${e.source}   ${e.targetDescription}');
      b.writeln('  tiles: ${e.tiles.join(' · ')}');
      for (final a in e.answers) {
        b.writeln('  => ${a.join(' ')}');
      }
  }
  return b.toString();
}

/// Generates up to [perType] exercises per skill and template and renders
/// them. Facets are cycled and seeds varied; templates that cannot serve a
/// skill are listed as such.
///
/// With [startedSkills] (and a course with gating data), exercises are gated
/// as in a lesson of each skill (mixed focus) for a learner who started those
/// skills, and sentences are not repeated within a skill (variety).
String sampleExercises(
  CourseData course, {
  int perType = 20,
  String lang = 'en',
  int seed = 0,
  List<ExerciseTemplate>? templates,
  Iterable<String>? skillIds,
  Set<String>? startedSkills,
}) {
  final b = StringBuffer();
  final tpls = templates ?? defaultTemplates();
  final options = SessionOptions(sourceLang: lang, seed: seed);
  for (final skill in course.skills) {
    if (skillIds != null && !skillIds.contains(skill.id)) continue;
    b.writeln('=' * 72);
    b.writeln('SKILL ${skill.id} (${skill.kind.name})  ${skill.title[lang] ?? skill.title['en'] ?? ''}');
    b.writeln('=' * 72);
    final facets = course.skillFacets(skill.id);
    final gate = startedSkills != null && SentenceGate.supports(course)
        ? SentenceGate(course, started: startedSkills, current: [skill.id])
        : null;
    final history = startedSkills != null ? SentenceHistory() : null;
    for (final t in tpls) {
      if (skill.exercises.isNotEmpty && !skill.exercises.contains(t.type.id)) continue;
      final usable = <SkillFacet>[for (final f in facets) if (t.supports(f)) f];
      if (usable.isEmpty) continue;
      final out = <String>[];
      for (var i = 0; i < perType * 3 && out.length < perType; i++) {
        final f = usable[i % usable.length];
        final ctx = GenContext(
          course: course,
          options: options,
          random: Random(seed * 7919 + i),
          skill: skill,
          nextId: () => '${skill.id}/${t.type.id}/$i',
          gate: gate,
          history: history,
          wordCap: SentenceGate.capFor(LessonFocus.mixed, skill),
        );
        if (!t.canGenerate(f, ctx)) continue;
        final e = t.generate(f, ctx);
        if (e != null) out.add(formatExercise(e));
      }
      b.writeln('--- ${t.type.id}: ${out.length} example(s)');
      for (final s in out) {
        b.writeln(s);
      }
    }
  }
  return b.toString();
}
