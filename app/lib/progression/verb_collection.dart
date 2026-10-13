/// The verb collection: one card per verb, one cell per tense, lit by mastery.
library;

import 'package:meta/meta.dart';

import '../core/core.dart';
import 'tiers.dart';

/// Mastery of one verb table (a `#form:{tense}` facet).
enum VerbMastery {
  /// Never practiced.
  unseen,

  /// Practiced but not learned yet, or learned and faded below the silver recall threshold.
  learning,

  /// Learned and recalled well now (R ≥ 0.85).
  known,

  /// Gold criteria: R ≥ 0.90 now and stability ≥ 21 days.
  mastered,
}

VerbMastery verbMasteryOf(FacetState? s, double r, {TierRules rules = const TierRules()}) {
  if (s == null) return VerbMastery.unseen;
  if (rules.meetsGold(s, r)) return VerbMastery.mastered;
  if (rules.isLearned(s) && r >= rules.silverRecall) return VerbMastery.known;
  return VerbMastery.learning;
}

@immutable
class VerbTenseCell {
  const VerbTenseCell({
    required this.tense,
    required this.facetId,
    required this.mastery,
    required this.retrievability,
    this.stability,
  });

  final String tense;
  final String facetId;
  final VerbMastery mastery;

  /// Predicted recall now (0 if unseen).
  final double retrievability;

  /// FSRS stability in days (null if unseen).
  final double? stability;
}

@immutable
class VerbCard {
  const VerbCard({required this.item, required this.cells});

  final Item item;

  /// One cell per tense the course trains for this verb, in course tense order.
  final List<VerbTenseCell> cells;

  String get itemId => item.id;
  String get lemma => item.lemma;

  int count(VerbMastery m) => cells.where((c) => c.mastery == m).length;

  /// The verb's weakest table (for sorting / a card frame).
  VerbMastery get overall => cells.isEmpty
      ? VerbMastery.unseen
      : cells.map((c) => c.mastery).reduce((a, b) => a.index <= b.index ? a : b);

  bool get isComplete => cells.isNotEmpty && cells.every((c) => c.mastery == VerbMastery.mastered);
}

@immutable
class VerbCollection {
  const VerbCollection({required this.tenses, required this.verbs});

  /// Tenses that appear in the collection, in course order.
  final List<String> tenses;

  /// Verbs ordered by frequency rank, then lemma.
  final List<VerbCard> verbs;

  int get totalTables => verbs.fold(0, (a, v) => a + v.cells.length);

  int count(VerbMastery m) => verbs.fold(0, (a, v) => a + v.count(m));

  Map<VerbMastery, int> get counts => {for (final m in VerbMastery.values) m: count(m)};
}

/// Builds the collection for every verb in [course].
///
/// A (verb, tense) cell is included when the verb has forms in that tense and
/// either some skill trains `{itemId}#form:{tense}` or the facet has been reviewed.
VerbCollection computeVerbCollection({
  required CourseData course,
  required Map<String, FacetState> states,
  required Scheduler scheduler,
  required DateTime now,
  TierRules rules = const TierRules(),
}) {
  final verbs = course.allItems.where((i) => i.isVerb).toList()
    ..sort((a, b) {
      final c = (a.freq ?? 1 << 30).compareTo(b.freq ?? 1 << 30);
      return c != 0 ? c : a.lemma.compareTo(b.lemma);
    });
  final usedTenses = <String>{};
  final cards = <VerbCard>[];
  for (final v in verbs) {
    final cells = <VerbTenseCell>[];
    for (final tense in course.meta.tenses) {
      final facetId = '${v.id}#form:$tense';
      final s = states[facetId];
      if (course.verbFormsInTense(v.id, tense).isEmpty) continue;
      if (s == null && course.skillsForFacet(facetId).isEmpty) continue;
      final r = s == null ? 0.0 : scheduler.retrievability(s, now).clamp(0.0, 1.0);
      cells.add(VerbTenseCell(
        tense: tense,
        facetId: facetId,
        mastery: verbMasteryOf(s, r, rules: rules),
        retrievability: r,
        stability: s?.stability,
      ));
      usedTenses.add(tense);
    }
    if (cells.isNotEmpty) cards.add(VerbCard(item: v, cells: List.unmodifiable(cells)));
  }
  return VerbCollection(
    tenses: [for (final t in course.meta.tenses) if (usedTenses.contains(t)) t],
    verbs: List.unmodifiable(cards),
  );
}
