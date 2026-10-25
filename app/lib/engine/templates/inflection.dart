/// Inflection tables of non-verbs (`#infl:{table}` facets): the ending
/// picker, the grid, cloze and spot the error for noun number, adjective
/// agreement, Dutch diminutives, ... (docs/engine.md, "Inflection tables").
///
/// The four templates delegate here for `FacetKind.infl`; grading is theirs
/// (the exercises are the same [ConjPickExercise], [ConjGridExercise],
/// [ClozeExercise] and [SpotErrorExercise], with `inflection: true` on the
/// first two).
///
/// Validity rules:
/// * A wrong option is never an accepted form of the asked cell (homographs:
///   Italian `grande` is m.sg and f.sg).
/// * In sentences (cloze, spot the error) only two kinds of wrong forms are
///   used: for an **agreement** table (the pipeline aligned the token only
///   where it found the controlling noun) the item's other cells, and for any
///   table the cell's `wrong` forms, which the pipeline checked are no word of
///   the language. A real word of another lemma could be right against the
///   translation (`gatte` for `gatti`), and a singular for a plural changes
///   the meaning, so neither is offered.
/// * The ending picker and the grid name the cell, so there the item's other
///   cells and other items' endings are wrong by definition.
library;

import '../../core/interfaces/course_data.dart';
import '../../core/models/course.dart';
import '../../core/models/facet.dart';
import '../course_index.dart';
import '../gen_context.dart';
import '../text/normalize.dart';

/// A token aligned to an inflection cell of an item.
class InflOccurrence {
  InflOccurrence(this.sentence, this.pos, this.cell);
  final Sentence sentence;
  final int pos;
  final InflectionForm cell;
  String get text => sentence.tokens[pos].t;
}

/// The table of an `#infl` facet, or null.
InflectionTable? inflTableOf(GenContext ctx, SkillFacet facet) {
  final t = facet.table;
  return t == null ? null : ctx.course.meta.inflectionTables[t];
}

/// Tokens aligned to a cell of [table] of [itemId] whose text is an accepted
/// form of that cell (for agreement tables: the canonical form only, so
/// Italian `bel` before a noun is left alone). Cached per course.
List<InflOccurrence> inflOccurrences(CourseIndex ix, String itemId, String table) =>
    ix.memo('infl.occ|$itemId|$table', () {
      final course = ix.course;
      final spec = course.meta.inflectionTables[table];
      final cells = course.inflections(itemId);
      final out = <InflOccurrence>[];
      for (final s in course.sentencesFor(itemId)) {
        for (var i = 0; i < s.tokens.length; i++) {
          final t = s.tokens[i];
          if (!t.isWord || t.lex != itemId || t.inflTable != table) continue;
          final cell = cells['$table.${t.inflCell}'];
          if (cell == null) continue;
          final forms = spec?.agreement == true ? [cell.form] : cell.accepted;
          if (!forms.any((f) => normalizeAnswer(f) == normalizeAnswer(t.t))) continue;
          out.add(InflOccurrence(s, i, cell));
        }
      }
      return out;
    });

/// Folded accepted forms of [cell].
Set<String> inflAcceptedKeys(InflectionForm cell) => {for (final a in cell.accepted) foldAnswer(a)};

/// Wrong forms for [o] in its sentence, in priority order, cased like the
/// token: the item's other cells (agreement tables only), then the cell's
/// `wrong` forms. None is an accepted form of the cell.
List<String> inflSentenceWrongs(CourseData course, InflOccurrence o) {
  final spec = course.meta.inflectionTables[o.cell.table];
  final accepted = inflAcceptedKeys(o.cell);
  final out = <String>[];
  final seen = <String>{...accepted};
  void add(String f) {
    // a citation stem (Bantu adjectives '-iza', possessives '-anjye') is no word of a sentence
    if (f.contains(' ') || f.startsWith('-')) return;
    if (seen.add(foldAnswer(f))) out.add(matchCase(f, o.text));
  }

  if (spec?.agreement == true) {
    for (final c in course.inflectionTable(o.cell.itemId, o.cell.table)) {
      if (c.cell != o.cell.cell) add(c.form);
    }
  }
  for (final w in o.cell.wrong) {
    add(w);
  }
  return out;
}

/// Whether [occ] may be asked in a sentence: agreement tables any cell, other
/// tables only non-base cells (the plural, the diminutive: asking for the
/// lemma itself teaches nothing).
bool inflAskable(InflectionTable? spec, InflectionForm cell) =>
    spec == null || spec.agreement || cell.cell != spec.base;

/// Cells the ending picker may ask: not the base cell, a stem/ending split, one word.
List<InflectionForm> inflPickCells(GenContext ctx, SkillFacet facet) {
  final spec = inflTableOf(ctx, facet);
  return [
    for (final c in ctx.course.inflectionTable(facet.itemId, facet.table!))
      if (c.cell != spec?.base && c.hasSplit && c.stem!.isNotEmpty && !c.form.contains(' ')) c,
  ];
}

/// Items of the course with [table] (inflecting: at least two different forms),
/// for the picker's and the grid's fallback distractors. Cached per course.
List<String> inflItems(CourseIndex ix, String table) => ix.memo('infl.items|$table', () {
      final course = ix.course;
      final out = <String>[];
      for (final i in course.allItems) {
        final t = course.inflectionTable(i.id, table);
        if (t.length > 1 && {for (final c in t) foldAnswer(c.form)}.length > 1) out.add(i.id);
      }
      return out;
    });

/// Wrong endings for the picker, in priority groups: the item's other cells,
/// the cell's `wrong` forms, the same cell of other items whose stem ends in
/// the same letter (`padr` takes `signor`'s `i`/`e`, never `amic`'s `hi`).
/// Endings that make an accepted form are left out.
List<List<String>> inflPickGroups(GenContext ctx, SkillFacet facet, InflectionForm cell) {
  final stem = cell.stem!;
  String? ending(String form) =>
      !form.contains(' ') && form.toLowerCase().startsWith(stem.toLowerCase()) ? form.substring(stem.length) : null;
  final own = [
    for (final c in ctx.course.inflectionTable(facet.itemId, cell.table))
      if (c.cell != cell.cell) ?ending(c.form),
  ];
  final wrong = [for (final w in cell.wrong) ?ending(w)];
  // Other items' endings of this cell after a stem ending in the same letter,
  // and only common ones (used by at least 3 items): `mooi` never gets `que`.
  final last = _lastLetter(stem);
  final others = [
    for (final e in _commonEndings(ctx.index, cell.table, cell.cell).entries)
      if (e.key == last) ...e.value,
  ];
  return [own, wrong, others];
}

/// Per last stem letter, the endings of [table].[cell] used by at least 3
/// items, most common first. Cached per course.
Map<String, List<String>> _commonEndings(CourseIndex ix, String table, String cell) =>
    ix.memo('infl.endings|$table.$cell', () {
      final counts = <String, Map<String, int>>{};
      for (final id in inflItems(ix, table)) {
        final f = ix.course.inflections(id)['$table.$cell'];
        if (f == null || !f.hasSplit || f.stem!.isEmpty) continue;
        final m = counts[_lastLetter(f.stem!)] ??= {};
        m[f.ending!] = (m[f.ending!] ?? 0) + 1;
      }
      return {
        for (final e in counts.entries)
          e.key: [
            for (final x in (e.value.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
              if (x.value >= 3) x.key,
          ],
      };
    });

String _lastLetter(String s) => s.isEmpty ? '' : foldDiacritics(s.substring(s.length - 1).toLowerCase());
