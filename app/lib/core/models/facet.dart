/// Facets: the unit FSRS schedules. See docs/ARCHITECTURE.md "Identifiers".
library;

import 'package:meta/meta.dart';

enum FacetKind {
  rec, // recognize: target -> meaning
  prod, // produce: meaning -> target
  form, // a verb's forms in one tense
  article, // a noun's article / gender
  infl; // a non-verb's inflection table (noun number, adjective agreement, ...)

  static FacetKind parse(String s) => FacetKind.values.byName(s);

  /// Null for a kind this app doesn't know (a pack from a newer schema minor).
  static FacetKind? tryParse(String s) {
    for (final k in FacetKind.values) {
      if (k.name == s) return k;
    }
    return null;
  }

  /// Kinds with a parameter after a colon: `#form:{tense}`, `#infl:{table}`.
  bool get hasParam => this == FacetKind.form || this == FacetKind.infl;
}

/// Parsed facet id: `{itemId}#rec`, `{itemId}#prod`, `{itemId}#form:{tense}`, `{itemId}#article`,
/// `{itemId}#infl:{table}`.
@immutable
class FacetId {
  const FacetId(this.itemId, this.kind, [this.tense])
      : assert(!(kind == FacetKind.form || kind == FacetKind.infl) || tense != null);

  final String itemId;
  final FacetKind kind;

  /// The parameter: the tense of a `#form` facet, the table of an `#infl` facet.
  final String? tense;

  /// The inflection table of an `#infl` facet.
  String? get table => kind == FacetKind.infl ? tense : null;

  factory FacetId.parse(String id) {
    final hash = id.lastIndexOf('#');
    if (hash <= 0) throw FormatException('Not a facet id: $id');
    final itemId = id.substring(0, hash);
    final rest = id.substring(hash + 1);
    if (rest.startsWith('form:')) {
      return FacetId(itemId, FacetKind.form, rest.substring(5));
    }
    if (rest.startsWith('infl:')) {
      return FacetId(itemId, FacetKind.infl, rest.substring(5));
    }
    return FacetId(itemId, FacetKind.parse(rest));
  }

  /// Course id is the item id prefix before the first ':'.
  String get courseId => itemId.substring(0, itemId.indexOf(':'));

  @override
  String toString() => switch (kind) {
        FacetKind.form => '$itemId#form:$tense',
        FacetKind.infl => '$itemId#infl:$tense',
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

  /// The tense of a `#form` facet, the table of an `#infl` facet (`skill_facets.tense`).
  final String? tense;
  final int ord;

  /// The inflection table of an `#infl` facet.
  String? get table => kind == FacetKind.infl ? tense : null;

  FacetId get parsed => FacetId(itemId, kind, tense);
}
