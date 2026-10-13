/// Facets: the unit FSRS schedules. See docs/ARCHITECTURE.md "Identifiers".
library;

import 'package:meta/meta.dart';

enum FacetKind {
  rec, // recognize: target -> meaning
  prod, // produce: meaning -> target
  form, // a verb's forms in one tense
  article; // a noun's article / gender

  static FacetKind parse(String s) => FacetKind.values.byName(s);
}

/// Parsed facet id: `{itemId}#rec`, `{itemId}#prod`, `{itemId}#form:{tense}`, `{itemId}#article`.
@immutable
class FacetId {
  const FacetId(this.itemId, this.kind, [this.tense])
      : assert(kind != FacetKind.form || tense != null);

  final String itemId;
  final FacetKind kind;
  final String? tense;

  factory FacetId.parse(String id) {
    final hash = id.lastIndexOf('#');
    if (hash <= 0) throw FormatException('Not a facet id: $id');
    final itemId = id.substring(0, hash);
    final rest = id.substring(hash + 1);
    if (rest.startsWith('form:')) {
      return FacetId(itemId, FacetKind.form, rest.substring(5));
    }
    return FacetId(itemId, FacetKind.parse(rest));
  }

  /// Course id is the item id prefix before the first ':'.
  String get courseId => itemId.substring(0, itemId.indexOf(':'));

  @override
  String toString() => switch (kind) {
        FacetKind.form => '$itemId#form:$tense',
        _ => '$itemId#${kind.name}',
      };

  @override
  bool operator ==(Object other) => other is FacetId && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}

/// A facet as trained by a skill (row of `skill_facets`).
@immutable
class SkillFacet {
  const SkillFacet({
    required this.skillId,
    required this.facetId,
    required this.itemId,
    required this.kind,
    required this.ord,
    this.tense,
  });
  final String skillId;
  final String facetId;
  final String itemId;
  final FacetKind kind;
  final String? tense;
  final int ord;

  FacetId get parsed => FacetId(itemId, kind, tense);
}
