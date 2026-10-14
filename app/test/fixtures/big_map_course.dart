/// A course shaped like the expanded v1 courses (10 units, 30 skills, long
/// titles, prerequisites inside units, across units and skipping units) for
/// map layout and legibility tests. Skills have no items: only the map matters.
library;

import 'package:tosk/core/core.dart';
import 'package:tosk/ui/course_catalog.dart';

const _unitTitles = [
  'Basics',
  'The present tense',
  'Food, drink and eating out',
  'Everyday verbs and the past',
  'Family, friends and other people',
  'Travelling, directions and transport',
  'The imperfect and describing the past',
  'Reflexive verbs and daily routines',
  'The future and making plans',
  'Conditionals, wishes and polite requests',
];

const _skillTitles = [
  'Greetings', 'People', 'Essere and avere', //
  'Present tense of -are verbs', 'Present tense of -ere verbs', 'Present tense of -ire verbs',
  'Food and drink', 'The article', 'At the restaurant',
  'Time and days', 'Irregular verbs in the present', 'The passato prossimo with avere',
  'Family', 'Possessive adjectives and pronouns', 'Describing people',
  'Directions', 'Transport and tickets', 'Passato prossimo with essere',
  'The imperfect', 'Imperfect or passato prossimo?', 'Childhood memories',
  'Reflexive verbs', 'Daily routine', 'Reflexive verbs in the past',
  'The simple future', 'Making plans', 'Weather and seasons',
  'The conditional', 'Polite requests', 'Wishes and hypotheses',
];

/// 10 units × 3 skills.
CourseData bigMapCourse() {
  final units = [
    for (var u = 0; u < 10; u++) Unit(id: 'u$u', ord: u, title: {'en': _unitTitles[u]}),
  ];
  final skills = <Skill>[];
  for (var i = 0; i < 30; i++) {
    final u = i ~/ 3, k = i % 3;
    final requires = <String>[
      if (i == 1 || i == 2) 's0',
      if (u > 0 && k == 0) 's${3 * u - 3}', // chain the units
      if (u > 0 && k == 1) 's${3 * u - 2}',
      if (u > 0 && k == 2) ...['s${3 * u}', 's${3 * u + 1}'], // inside the unit
      if (u >= 3 && k == 1) 's${3 * u - 8}', // skips a unit
    ];
    skills.add(
      Skill(
        id: 's$i',
        unitId: 'u$u',
        ord: k,
        kind: k == 0 && u.isEven ? SkillKind.vocab : SkillKind.grammar,
        title: {'en': _skillTitles[i]},
        requires: requires,
      ),
    );
  }
  return InMemoryCourseData(
    meta: const CourseMeta(
      id: 'big',
      version: '1.0.0',
      title: {'en': 'Big course'},
      target: 'it',
      translations: ['en'],
      persons: ['io', 'tu', 'lui/lei', 'noi', 'voi', 'loro'],
      tenses: ['presente'],
    ),
    units: units,
    skills: skills,
    items: const [],
    skillItemIds: const {},
    skillFacets: const [],
  );
}

/// A catalog with only [bigMapCourse].
class BigCourseCatalog implements CourseCatalog {
  final CourseData course = bigMapCourse();
  @override
  Future<List<CourseMeta>> listCourses() async => [course.meta];
  @override
  Future<CourseData> open(String courseId) async => course;
  @override
  bool isDemo(String courseId) => false;
}
