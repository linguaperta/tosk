/// The trees of a course: the main tree and its built-in topics (schema
/// minor 3; docs/extensions.md, docs/pack-format.md "Topics").
///
/// [CourseData.units] and [CourseData.skills] hold every tree in course order
/// (the main tree first, then each topic); this splits them. Progression
/// (tiers, XP, stats) stays per course, and facets are shared by id, so a word
/// known from any tree is known in all of them.
library;

import 'interfaces/course_data.dart';
import 'models/course.dart';

class CourseTrees {
  CourseTrees._(this.course) {
    final unitTopic = {for (final u in course.units) u.id: u.topic};
    final known = {for (final t in course.topics) t.id};
    for (final u in course.units) {
      final t = u.topic != null && known.contains(u.topic) ? u.topic : null;
      if (t == null) {
        mainUnits.add(u);
      } else {
        (_topicUnits[t] ??= []).add(u);
      }
    }
    for (final s in course.skills) {
      final u = unitTopic[s.unitId];
      final t = u != null && known.contains(u) ? u : null;
      _skillTree[s.id] = t;
      if (t == null) {
        mainSkills.add(s);
      } else {
        (_topicSkills[t] ??= []).add(s);
      }
    }
    final mainIds = {for (final s in mainSkills) s.id};
    for (final t in course.topics) {
      if ((_topicSkills[t.id] ?? const []).isEmpty) continue;
      topics.add(t);
      _topics[t.id] = t;
      if (mainIds.contains(t.anchor)) (byAnchor[t.anchor] ??= []).add(t);
    }
  }

  static final Expando<CourseTrees> _cache = Expando('CourseTrees');

  /// The (cached) trees of [course].
  static CourseTrees of(CourseData course) => _cache[course] ??= CourseTrees._(course);

  final CourseData course;

  /// The main tree's units and skills, in course order.
  final List<Unit> mainUnits = [];
  final List<Skill> mainSkills = [];

  /// The topics that have skills, in order.
  final List<Topic> topics = [];

  /// Topics by anchor skill (main-tree skills only), in topic order.
  final Map<String, List<Topic>> byAnchor = {};

  final Map<String, Topic> _topics = {};
  final Map<String, List<Unit>> _topicUnits = {};
  final Map<String, List<Skill>> _topicSkills = {};
  final Map<String, String?> _skillTree = {};

  bool get hasTopics => topics.isNotEmpty;

  Topic? topic(String id) => _topics[id];

  /// The units of [tree] (null: the main tree).
  List<Unit> unitsOf(String? tree) => tree == null ? mainUnits : _topicUnits[tree] ?? const [];

  /// The skills of [tree] (null: the main tree), in course order.
  List<Skill> skillsOf(String? tree) => tree == null ? mainSkills : _topicSkills[tree] ?? const [];

  /// The topic [skillId] belongs to, or null for a main-tree (or unknown) skill.
  String? treeOf(String skillId) => _skillTree[skillId];

  /// Whether [skillId] is a skill of a topic.
  bool inTopic(String skillId) => _skillTree[skillId] != null;

  late final Map<String, int> _mainOrder = {for (final (i, s) in mainSkills.indexed) s.id: i};
  late final Map<String, int> _mainUnitNumber = {for (final (i, u) in mainUnits.indexed) u.id: i + 1};

  /// The main-tree skills topic skill [skillId] requires, in course order
  /// (empty for a main-tree skill). Besides the topic's anchor and its
  /// prerequisites they may be later main-tree skills (pack format 1.2: a
  /// topic's anchor is where it starts; a later skill may need more of the
  /// main tree).
  List<String> mainRequirements(String skillId) {
    if (!inTopic(skillId)) return const [];
    final reqs = [
      for (final r in course.skill(skillId)?.requires ?? const <String>[])
        if (_mainOrder.containsKey(r)) r,
    ];
    return reqs..sort((a, b) => _mainOrder[a]!.compareTo(_mainOrder[b]!));
  }

  /// The number of the main-tree unit [skillId] is in (1-based, as the map
  /// shows them: "unit 12"), or null for a topic skill.
  int? mainUnitNumber(String skillId) => _mainUnitNumber[course.skill(skillId)?.unitId];
}
