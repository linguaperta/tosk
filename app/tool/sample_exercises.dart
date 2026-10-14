// Prints example exercises per skill and exercise type, to check generated
// content by eye.
//
//   dart run tool/sample_exercises.dart [it|nl|path/to/pack.sqlite] [--lang en|nl] [--per 20] [--skill id] [--seed 0]
//
// A course id loads the bundled pack `assets/courses/{id}.sqlite` (built by
// `python -m pipeline build it nl --install`); a path loads that pack.
// The committed samples in docs/samples/ are made with:
//
//   dart run tool/sample_exercises.dart nl --per 8 > ../docs/samples/nl_exercises.txt
//   dart run tool/sample_exercises.dart it --per 8 > ../docs/samples/it_exercises.txt
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
      default:
        course = args[i];
    }
  }
  print(sampleExercises(
    _load(course),
    perType: per,
    lang: lang,
    seed: seed,
    skillIds: skill == null ? null : [skill],
  ));
}
