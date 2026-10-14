/// `CourseRepo`: a loaded course (all of it, in memory) plus pack info and counts.
///
/// Pure Dart. Implements [CourseData] by delegating to [InMemoryCourseData], so
/// the engine can take either.
library;

import '../../core/core.dart';

/// Counts gathered while loading a pack.
class CourseCounts {
  const CourseCounts({
    this.items = 0,
    this.verbs = 0,
    this.verbForms = 0,
    this.sentences = 0,
    this.tokens = 0,
    this.skillFacets = 0,
    this.notes = 0,
  });
  final int items;
  final int verbs;
  final int verbForms;
  final int sentences;
  final int tokens;
  final int skillFacets; // rows of skill_facets (a facet in two skills counts twice)
  final int notes;

  @override
  String toString() => 'items=$items verbs=$verbs forms=$verbForms sentences=$sentences '
      'tokens=$tokens skillFacets=$skillFacets notes=$notes';
}

class CourseRepo implements CourseData {
  CourseRepo(
    this.data, {
    this.rawMeta = const {},
    this.counts = const CourseCounts(),
    this.loadTime,
  });

  /// The underlying indexed data; hand this to the engine if it wants the concrete type.
  final InMemoryCourseData data;

  /// Every `meta` row as stored (text values, JSON not decoded).
  final Map<String, String> rawMeta;
  final CourseCounts counts;

  /// How long loading took (null when not measured).
  final Duration? loadTime;

  String get id => meta.id;
  String get version => meta.version;

  /// ISO-8601 build time from `meta.built_at`, if present.
  String? get builtAt => rawMeta['built_at'];

  int get itemCount => counts.items;
  int get sentenceCount => counts.sentences;
  int get verbCount => counts.verbs;

  /// Skills of [unitId] in order.
  List<Skill> skillsInUnit(String unitId) => [
        for (final s in skills)
          if (s.unitId == unitId) s,
      ];

  int skillItemCount(String skillId) => data.skillItems(skillId).length;
  int skillFacetCount(String skillId) => data.skillFacets(skillId).length;

  /// Distinct facet ids trained by any skill of the course.
  late final Set<String> allFacetIds = {
    for (final s in skills)
      for (final f in data.skillFacets(s.id)) f.facetId,
  };

  // ------------------------------------------------------- CourseData delegation

  @override
  CourseMeta get meta => data.meta;
  @override
  List<Unit> get units => data.units;
  @override
  List<Skill> get skills => data.skills;
  @override
  Skill? skill(String id) => data.skill(id);
  @override
  Item? item(String id) => data.item(id);
  @override
  Iterable<Item> get allItems => data.allItems;
  @override
  List<Item> skillItems(String skillId) => data.skillItems(skillId);
  @override
  List<SkillFacet> skillFacets(String skillId) => data.skillFacets(skillId);
  @override
  List<String> skillsForFacet(String facetId) => data.skillsForFacet(facetId);
  @override
  List<Item> itemsByTag(String tag) => data.itemsByTag(tag);
  @override
  List<Item> itemsNearFreq(String pos, int? freq, {int limit = 50}) =>
      data.itemsNearFreq(pos, freq, limit: limit);
  @override
  Verb? verb(String itemId) => data.verb(itemId);
  @override
  Map<String, VerbForm> verbForms(String itemId) => data.verbForms(itemId);
  @override
  List<VerbForm> verbFormsInTense(String itemId, String tense) =>
      data.verbFormsInTense(itemId, tense);
  @override
  List<Sentence> sentencesFor(String itemId, {String? form, String? tense}) =>
      data.sentencesFor(itemId, form: form, tense: tense);
  @override
  Sentence? sentence(String id) => data.sentence(id);
  @override
  String? note(String skillId, String lang) => data.note(skillId, lang);
  @override
  Set<String> sentenceFeatures(String sentenceId) => data.sentenceFeatures(sentenceId);
  @override
  Set<String> skillFeatures(String skillId) => data.skillFeatures(skillId);
}
