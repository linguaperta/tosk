// Prints example exercises per skill and exercise type, to check generated
// content by eye.
//
//   dart run tool/sample_exercises.dart [it|nl] [--lang en|nl] [--per 20] [--skill id] [--seed 0]
//
// It currently runs on the hand-built test fixtures. Once the data layer's
// loader exists (lib/data/course/course_loader.dart), switch `_load` to
// `loadCourseFile(path)` and accept a path to a compiled .sqlite pack.
// ignore_for_file: avoid_print, avoid_relative_lib_imports
import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';

import '../test/engine/fixtures/dutch_course.dart';
import '../test/engine/fixtures/italian_course.dart';

CourseData _load(String course) => switch (course) {
      'nl' => dutchCourse(),
      _ => italianCourse(),
    };

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
