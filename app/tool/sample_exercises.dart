// Prints example exercises per skill and exercise type, to check generated
// content by eye.
//
//   dart run tool/sample_exercises.dart [it|nl|path/to/pack.sqlite] [--lang en|nl] [--per 20] [--skill id] [--seed 0]
//       [--started-units N]
//
// A course id loads the bundled pack `assets/courses/{id}.sqlite` (built by
// `python -m pipeline build it nl --install`); a path loads that pack.
// `--started-units N` applies grammar gating for a learner who started every
// skill of the first N units (each skill sampled as a lesson's current skill).
// The committed samples in docs/samples/ are made with:
//
//   dart run tool/sample_exercises.dart nl --per 8 --started-units 4 > ../docs/samples/nl_exercises.txt
//   dart run tool/sample_exercises.dart it --per 8 --started-units 5 > ../docs/samples/it_exercises.txt
//   dart run tool/sample_exercises.dart es --per 8 --started-units 5 > ../docs/samples/es_exercises.txt
//     (es: keep the review header at the top of the committed file)
// ignore_for_file: avoid_print
import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/engine/engine.dart';

CourseData _load(String course) =>
    loadCourseFile(course.endsWith('.sqlite') ? course : 'assets/courses/$course.sqlite');

void main(List<String> args) {
  var course = 'it';
  var lang = 'en';
  var per = 20;
  var seed = 0;
  String? skill;
  int? startedUnits;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--lang':
        lang = args[++i];
      case '--per':
        per = int.parse(args[++i]);
      case '--seed':
        seed = int.parse(args[++i]);
      case '--skill':
        skill = args[++i];
      case '--started-units':
        startedUnits = int.parse(args[++i]);
      default:
        course = args[i];
    }
  }
  final data = _load(course);
  Set<String>? started;
  if (startedUnits != null) {
    final units = data.units.take(startedUnits).map((u) => u.id).toSet();
    started = {for (final s in data.skills) if (units.contains(s.unitId)) s.id};
    print('# Gated samples (docs/ARCHITECTURE.md, "Grammar gating"): a mid-course learner who started every');
    print('# skill of units ${data.units.first.id}-${data.units.take(startedUnits).last.id} '
        '(${started.length} skills). Each skill is sampled as the current skill of a mixed-focus lesson:');
    print('# known grammar = base + started skills + the skill and its prerequisites; at most '
        '${SentenceGate.vocabCap} unknown words per sentence (${SentenceGate.grammarCap} in grammar skills);');
    print('# no sentence twice within a skill. Skills after unit ${data.units.take(startedUnits).last.id} show what the learner meets on opening them.');
    print('');
  }
  print(sampleExercises(
    data,
    perType: per,
    lang: lang,
    seed: seed,
    skillIds: skill == null ? null : [skill],
    startedSkills: started,
  ));
}
