/// Template validity checks that run against any [CourseData]: the hand-built
/// fixtures now, the real packs (`app/assets/courses/*.sqlite`) later.
///
/// For every skill x template where the template can serve at least one facet
/// of the skill, it generates [perPair] exercises (cycling facets, seeds and
/// facet stages) and checks each one independently of the generator:
/// * rendering fields are non-empty;
/// * no duplicate options after normalization; the correct answer is present
///   exactly once (validated against the course data, synonyms included);
/// * grading the correct answer is correct and grading every wrong option is
///   wrong;
/// * sentences re-render: cloze `before + expected + after`, spot-the-error
///   with the correction, builder/transform answers vs the sentence text.
library;

import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';

/// Pairs of (skill, template label).
typedef PairKey = (String, String);

class ValidityReport {
  final Map<PairKey, int> generated = {};
  final Set<PairKey> applicable = {};
  final List<String> failures = [];

  int generatedFor(String skillId, String label) => generated[(skillId, label)] ?? 0;

  /// Applicable pairs that produced fewer than [min] exercises.
  List<String> shortfalls(int min) => [
        for (final k in applicable)
          if ((generated[k] ?? 0) < min) '${k.$1} × ${k.$2}: ${generated[k] ?? 0}/$min',
      ];

  /// Template labels that generated nothing in any skill.
  List<String> unusedLabels(Iterable<String> labels) => [
        for (final l in labels)
          if (!applicable.any((k) => k.$2 == l)) l,
      ];

  @override
  String toString() {
    final b = StringBuffer();
    final skills = {for (final k in generated.keys) k.$1};
    for (final s in skills) {
      b.writeln('$s: ${[for (final e in generated.entries) if (e.key.$1 == s) '${e.key.$2}=${e.value}'].join(', ')}');
    }
    return b.toString();
  }
}

/// Default templates under test, labelled. Multiple choice is also run with
/// the sentence variant forced on and off so both are always covered.
Map<String, ExerciseTemplate> validityTemplates() => {
      for (final t in defaultTemplates()) t.type.id: t,
      'multiple_choice/sentence': const MultipleChoiceTemplate(sentenceShare: 1),
      'multiple_choice/word': const MultipleChoiceTemplate(sentenceShare: 0),
      'listen_pick/sentence': const ListenPickTemplate(sentenceShare: 1),
      'listen_pick/word': const ListenPickTemplate(sentenceShare: 0),
    };

/// Runs the checks; returns a report (callers assert on it).
ValidityReport runTemplateValidity(
  CourseData course, {
  int perPair = 20,
  List<String>? langs,
  Map<String, ExerciseTemplate>? templates,
}) {
  final report = ValidityReport();
  final tpls = templates ?? validityTemplates();
  final now = DateTime.utc(2026, 10, 13, 12);
  for (final lang in langs ?? course.meta.translations) {
    for (final skill in course.skills) {
      final facets = course.skillFacets(skill.id);
      for (final entry in tpls.entries) {
        final label = entry.key;
        final t = entry.value;
        final key = (skill.id, label);
        final usable = [for (final f in facets) if (t.supports(f)) f];
        if (usable.isEmpty) continue;
        GenContext ctx(int i, SkillFacet f) {
          final stage = i % 3;
          final states = <String, FacetState>{
            if (stage == 1) f.facetId: _state(f.facetId, 2, now),
            if (stage == 2) f.facetId: _state(f.facetId, 40, now),
          };
          return GenContext(
            course: course,
            // Text-to-speech assumed available, so listen_pick is checked too.
            options: SessionOptions(
              sourceLang: lang,
              preferredInput: i % 7 == 6 ? InputMode.keyboard : InputMode.tap,
              listening: true,
            ),
            random: Random(i * 31 + lang.hashCode),
            states: states,
            skill: skill,
            now: now,
            nextId: () => '$label#$i',
          );
        }

        final applicable = [for (final f in usable) if (t.canGenerate(f, ctx(0, f))) f];
        if (applicable.isEmpty) continue;
        report.applicable.add(key);
        var count = report.generated[key] ?? 0;
        final target = count + perPair;
        for (var i = 0; i < perPair * 6 && count < target; i++) {
          final f = applicable[i % applicable.length];
          final e = t.generate(f, ctx(i, f));
          if (e == null) continue;
          count++;
          for (final p in validateExercise(e, t, course, lang)) {
            report.failures.add('[$lang ${skill.id} $label ${f.facetId} i=$i] $p\n${formatExercise(e)}');
          }
        }
        report.generated[key] = count;
      }
    }
  }
  return report;
}

FacetState _state(String id, double stability, DateTime now) => FacetState(
      facetId: id,
      stability: stability,
      difficulty: 5,
      due: now.add(Duration(days: stability.round())),
      lastReview: now.subtract(const Duration(days: 1)),
      reps: 3,
      lapses: 0,
      phase: CardPhase.review,
    );

const _fast = Duration(seconds: 1);
const _tapGrade = GradeOptions();
const _strict = GradeOptions(accents: AccentStrictness.strict);

String _k(String s) => foldAnswer(s);

/// Per-course caches of the checker's own (generator-independent) lookups.
final Expando<Map<String, List<Item>>> _synonymCache = Expando();
final Expando<Map<String, Sentence>> _textIndex = Expando();

/// Items that share a folded gloss (any language) or spelling with [item].
List<Item> _synonyms(CourseData c, Item item) => (_synonymCache[c] ??= {})[item.id] ??= () {
      String strip(String g) => g.replaceAll(RegExp(r'\([^)]*\)'), ' ');
      final g = {for (final gs in item.tr.values) for (final x in gs) ...[_k(x), _k(strip(x))]}..remove('');
      final sp = {for (final s in item.spellings) _k(s)};
      return [
        for (final o in c.allItems)
          if (o.id != item.id &&
              ({for (final gs in o.tr.values) for (final x in gs) ...[_k(x), _k(strip(x))]}.any(g.contains) ||
                  o.spellings.any((s) => sp.contains(_k(s)))))
            o,
      ];
    }();

/// Folded accepted forms of [cell] and of the same tense's cells whose
/// person shares a pronoun with it (Dutch `hij/zij` and `zij`).
Set<String> _contextForms(CourseData c, String verbId, VerbForm cell) {
  final mine = cell.person.split('/').map(_k).toSet();
  return {
    for (final f in c.verbForms(verbId).values)
      if (f.tense == cell.tense && (f.person == cell.person || f.person.split('/').map(_k).any(mine.contains)))
        for (final a in f.accepted) _k(a),
  };
}

/// Spellings of [item] and of all its synonyms (folded).
Set<String> _synonymSpellings(CourseData c, Item item) => {
      for (final s in item.spellings) _k(s),
      for (final o in _synonyms(c, item)) ...o.spellings.map(_k),
    };

List<String> _dupes(Iterable<String> options) {
  final seen = <String>{};
  return [for (final o in options) if (!seen.add(_k(o))) o];
}

Map<String, int> _bag(Iterable<String> words) {
  final m = <String, int>{};
  for (final w in words) {
    m[normalizeAnswer(w)] = (m[normalizeAnswer(w)] ?? 0) + 1;
  }
  return m;
}

bool _subBag(Map<String, int> need, Map<String, int> have) => need.entries.every((e) => (have[e.key] ?? 0) >= e.value);

List<String> _bagMinus(List<String> tiles, List<String> answer) {
  final need = _bag(answer);
  final out = <String>[];
  for (final t in tiles) {
    final k = normalizeAnswer(t);
    if ((need[k] ?? 0) > 0) {
      need[k] = need[k]! - 1;
    } else {
      out.add(t);
    }
  }
  return out;
}

Sentence? _sentenceByText(CourseData c, String text) {
  final index = _textIndex[c] ??= () {
    final m = <String, Sentence>{};
    for (final s in CourseIndex.of(c).allSentences) {
      m.putIfAbsent(normalizeAnswer(s.text), () => s);
    }
    return m;
  }();
  return index[normalizeAnswer(text)];
}

final Expando<Map<String, List<Sentence>>> _allByText = Expando();

/// Every course sentence with this text (a few courses have duplicates with
/// different translations).
List<Sentence> _sentencesByText(CourseData c, String text) {
  final index = _allByText[c] ??= () {
    final m = <String, List<Sentence>>{};
    for (final s in CourseIndex.of(c).allSentences) {
      (m[normalizeAnswer(s.text)] ??= []).add(s);
    }
    return m;
  }();
  return index[normalizeAnswer(text)] ?? const [];
}

/// The verb cell token [idx] of [s] belongs to, as (verb id, cell), by the
/// pipeline's alignment convention: a compound form (`ho mangiato`, `heb …
/// gegeten`) is aligned on one of its words (the participle) and its other
/// words (the auxiliary, aligned separately to the auxiliary verb's present,
/// or not at all) are the nearest tokens (within 6) reading those words. Such
/// an auxiliary belongs to the compound form, not to its own alignment.
(String, VerbForm)? _ownerCell(CourseData c, Sentence s, int idx) {
  final tokens = s.tokens;
  for (var j = 0; j < tokens.length; j++) {
    final t = tokens[j];
    if (!t.isWord || t.lex == null || t.form == null) continue;
    final cell = c.verbForms(t.lex!)[t.form!];
    if (cell == null) continue;
    for (final a in cell.accepted) {
      final w = splitWords(a).map(_k).toList();
      final k = w.indexOf(_k(t.t));
      if (w.length < 2 || k < 0) continue;
      if (j == idx) return (t.lex!, cell);
      // The first accepted spelling whose other words are all present.
      final taken = <int>{j};
      for (var m = 0; m < w.length; m++) {
        if (m == k) continue;
        int? best;
        for (var q = 0; q < tokens.length; q++) {
          if (taken.contains(q) || !tokens[q].isWord || (q - j).abs() > 6 || _k(tokens[q].t) != w[m]) continue;
          final lex = tokens[q].lex;
          if (lex != null && c.verbForms(lex).isEmpty) continue;
          if (best == null || (q - j).abs() < (best - j).abs()) best = q;
        }
        if (best != null) taken.add(best);
      }
      if (taken.length < w.length) continue;
      if (taken.contains(idx)) return (t.lex!, cell);
      break;
    }
  }
  final t = tokens[idx];
  final cell = t.lex == null || t.form == null ? null : c.verbForms(t.lex!)[t.form!];
  return cell == null ? null : (t.lex!, cell);
}

final Expando<Set<String>> _wordSets = Expando();

/// Every word the course knows (folded): lemmas, variants, plurals, inflection
/// and verb forms, sentence tokens. A wrong form offered in a sentence for a
/// non-agreement table must be none of them.
Set<String> _courseWords(CourseData c) => _wordSets[c] ??= {
      for (final i in c.allItems) ...[
        _k(i.lemma),
        for (final v in i.variants) _k(v),
        if (i.plural != null) _k(i.plural!),
        for (final f in c.inflections(i.id).values) ...f.accepted.map(_k),
        for (final f in c.verbForms(i.id).values) ...f.accepted.expand(splitWords).map(_k),
      ],
      for (final s in CourseIndex.of(c).allSentences)
        for (final t in s.tokens)
          if (t.isWord) _k(t.t),
    };

/// Checks a wrong option [w] for an inflection cell in a sentence: not an
/// accepted form of the cell; another cell of the same item only for an
/// agreement table; otherwise no word of the course.
String? _inflWrongProblem(CourseData c, InflectionForm cell, String w) {
  if (cell.accepted.any((a) => _k(a) == _k(w))) return '"$w" is an accepted form of ${cell.key}';
  final spec = c.meta.inflectionTables[cell.table];
  final ownCells = {for (final f in c.inflectionTable(cell.itemId, cell.table)) _k(f.form)};
  if (spec?.agreement == true && ownCells.contains(_k(w))) return null;
  if (_courseWords(c).contains(_k(w))) return '"$w" is a word of the course (may be right in the sentence)';
  return null;
}

/// The inflection cell of token [idx] of [s] for [item] and [table], checked
/// independently: aligned to the item, an `infl:` form of that table, and the
/// token text an accepted form of the cell.
InflectionForm? _inflCellAt(CourseData c, Sentence s, int idx, String itemId, String table) {
  if (idx < 0 || idx >= s.tokens.length) return null;
  final t = s.tokens[idx];
  if (t.lex != itemId || t.inflTable != table) return null;
  final cell = c.inflections(itemId)['$table.${t.inflCell}'];
  if (cell == null || !cell.accepted.any((a) => _k(a) == _k(t.t))) return null;
  return cell;
}

/// Indices of the tokens of [s] overlapping the characters [from, to).
List<int> _tokensInRange(Sentence s, int from, int to) {
  final out = <int>[];
  var pos = 0;
  for (var i = 0; i < s.tokens.length; i++) {
    pos += s.tokens[i].pre.length;
    final end = pos + s.tokens[i].t.length;
    if (pos < to && end > from) out.add(i);
    pos = end;
  }
  return out;
}

/// Problems with one exercise (empty when valid).
List<String> validateExercise(Exercise e, ExerciseTemplate t, CourseData c, String lang) {
  final p = <String>[];
  void check(bool ok, String msg) {
    if (!ok) p.add(msg);
  }

  check(e.id.isNotEmpty, 'empty id');
  check(e.instruction.trim().isNotEmpty, 'empty instruction');
  check(e.facetIds.isNotEmpty && e.facetIds.every((f) => f.isNotEmpty), 'facet ids');
  check(e.type == t.type, 'type mismatch');
  final facet = FacetId.parse(e.facetId);
  final item = c.item(facet.itemId);
  check(item != null, 'unknown item ${facet.itemId}');
  if (item == null) return p;

  Result g(Answer a, [GradeOptions o = _tapGrade]) => t.grade(e, a, elapsed: _fast, options: o);

  void choiceChecks(List<String> options, int correctIndex, bool Function(String) isValid, {int minOptions = 3}) {
    check(options.length >= minOptions, 'only ${options.length} options');
    check(correctIndex >= 0 && correctIndex < options.length, 'correctIndex out of range');
    check(options.every((o) => o.trim().isNotEmpty), 'empty option');
    final d = _dupes(options);
    check(d.isEmpty, 'duplicate options $d');
    final valid = [for (final o in options) if (isValid(o)) o];
    check(valid.length == 1, 'expected exactly one valid option, got $valid');
    if (correctIndex >= 0 && correctIndex < options.length) {
      check(isValid(options[correctIndex]), 'option at correctIndex is not valid');
    }
    for (var i = 0; i < options.length; i++) {
      final r = g(ChoiceAnswer(i));
      check(r.correct == (i == correctIndex), 'grading option $i gave ${r.correct}');
      check(r.outcomes.length == 1 && r.outcomes.single.facetId == e.facetId, 'outcomes');
      check(r.outcomes.single.rating == (i == correctIndex ? Rating.easy : Rating.again), 'rating for option $i');
    }
  }

  switch (e) {
    case FlashcardExercise():
      check(e.front.trim().isNotEmpty && e.back.trim().isNotEmpty, 'empty card');
      check(!g(const SelfGradeAnswer(Rating.again)).correct, 'again is correct');
      final r = g(const SelfGradeAnswer(Rating.good));
      check(r.correct && r.outcomes.single.rating == Rating.good, 'good self-grade');

    case MultipleChoiceExercise():
      check(e.prompt.trim().isNotEmpty, 'empty prompt');
      if (facet.kind == FacetKind.article) {
        final valid = {for (final a in CourseIndex.of(c).articlesOf(item)) _k(a)};
        choiceChecks(e.options, e.correctIndex, (o) => valid.contains(_k(o)), minOptions: 2);
      } else if (!e.isSentence) {
        if (e.direction == Direction.recognize) {
          final valid = {for (final x in item.glosses(lang)) _k(x)};
          choiceChecks(e.options, e.correctIndex, (o) => valid.contains(_k(o)));
          check(_k(e.prompt) == _k(item.lemma), 'prompt is not the lemma');
          // No wrong option may be the meaning of a synonym of the target.
          final synGlosses = {for (final o in _synonyms(c, item)) for (final x in o.glosses(lang)) _k(x)};
          for (var i = 0; i < e.options.length; i++) {
            if (i != e.correctIndex) check(!synGlosses.contains(_k(e.options[i])), 'option "${e.options[i]}" means the same as a synonym');
          }
        } else {
          final valid = _synonymSpellings(c, item);
          choiceChecks(e.options, e.correctIndex, (o) => valid.contains(_k(o)));
          check(_k(e.prompt) == _k(item.gloss(lang)), 'prompt is not the gloss');
        }
      } else {
        final same = _sentencesByText(c, e.direction == Direction.recognize ? e.prompt : e.options[e.correctIndex]);
        // Among sentences sharing the text, the one whose translation is the prompt.
        final s = e.direction == Direction.recognize
            ? _sentenceByText(c, e.prompt)
            : same.where((x) => _k(x.translation(lang) ?? '') == _k(e.prompt)).firstOrNull ??
                _sentenceByText(c, e.options[e.correctIndex]);
        check(s != null, 'sentence not found');
        if (s != null) {
          check(s.tokens.any((t) => t.lex == item.id), 'sentence does not contain the item');
          if (e.direction == Direction.recognize) {
            final valid = {for (final x in same) _k(x.translation(lang)!)};
            choiceChecks(e.options, e.correctIndex, (o) => valid.contains(_k(o)));
          } else {
            // Any course sentence with the same translation would also be right.
            final tr = _k(s.translation(lang)!);
            final valid = {
              for (final x in CourseIndex.of(c).allSentences)
                if (x.translation(lang) != null && _k(x.translation(lang)!) == tr) _k(x.text),
            };
            choiceChecks(e.options, e.correctIndex, (o) => valid.contains(_k(o)));
            check(_k(e.prompt) == tr, 'prompt is not the translation');
          }
        }
      }

    case MatchPairsExercise():
      final n = e.left.length;
      check(n == 5 && e.right.length == 5, 'not 5 pairs');
      check(_dupes(e.left).isEmpty && _dupes(e.right).isEmpty, 'duplicates');
      check(e.solution.length == n && e.solution.values.toSet().length == n, 'solution not a bijection');
      check(e.pairFacetIds.length == n, 'pair facets');
      final items = [for (var i = 0; i < n; i++) c.item(FacetId.parse(e.pairFacetIds[i]!).itemId)];
      for (var i = 0; i < n; i++) {
        final it = items[i];
        check(it != null, 'pair $i item');
        if (it == null) continue;
        check(_k(e.left[i]) == _k(it.lemma), 'left $i is not the lemma');
        final gl = {for (final x in it.glosses(lang)) _k(x)};
        final synGl = {for (final o in _synonyms(c, it)) for (final x in o.glosses(lang)) _k(x)};
        for (var j = 0; j < n; j++) {
          final shown = _k(e.right[e.solution[j]!]);
          if (i == j) {
            check(gl.contains(shown), 'pair $i meaning is wrong');
          } else {
            check(!gl.contains(shown) && !synGl.contains(shown), 'meaning of pair $j also fits ${e.left[i]}');
          }
        }
      }
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final a = items[i];
          final b = items[j];
          if (a != null && b != null) check(!_synonyms(c, a).any((x) => x.id == b.id), '${a.id} and ${b.id} overlap');
        }
      }
      final ok = g(MatchAnswer(Map.of(e.solution)));
      check(ok.correct && ok.outcomes.length == n && ok.outcomes.every((o) => o.correct), 'grading the solution');
      final swapped = Map.of(e.solution)
        ..[0] = e.solution[1]!
        ..[1] = e.solution[0]!;
      final bad = g(MatchAnswer(swapped));
      check(!bad.correct && bad.outcomes.where((o) => !o.correct).length == 2, 'grading a swap');

    case ConjPickExercise() when e.inflection:
      check(facet.kind == FacetKind.infl && facet.table == e.tense, 'inflection pick on a ${facet.kind} facet');
      final cell = c.inflections(item.id)['${e.tense}.${e.person}'];
      check(cell != null, 'no inflection cell');
      check(cell?.cell != c.meta.inflectionTables[e.tense]?.base, 'asks the base cell');
      if (cell != null) {
        final acc = {for (final a in cell.accepted) _k(a)};
        String full(String ending) => e.stem + (ending == kNoEnding ? '' : ending);
        check(e.fullForm == cell.form, 'fullForm');
        final keys = [for (final o in e.endings) foldDiacritics(o.toLowerCase())];
        check(keys.toSet().length == keys.length, 'duplicate endings ${e.endings}');
        choiceChecks(e.endings, e.correctIndex, (o) => acc.contains(_k(full(o))));
        final typed = g(TextAnswer(cell.ending!.isEmpty ? '-' : cell.ending!));
        check(typed.correct, 'typed ending rejected');
      }
      check(e.stem.isNotEmpty && e.lemma.isNotEmpty && e.personLabel.isNotEmpty && e.tenseLabel.isNotEmpty, 'labels');

    case ConjPickExercise():
      final cell = c.verbForms(item.id)['${e.tense}.${e.person}'];
      check(cell != null, 'no cell');
      if (cell != null) {
        final acc = {for (final a in cell.accepted) _k(a)};
        String full(String ending) => e.stem + (ending == kNoEnding ? '' : ending);
        check(e.fullForm == cell.form, 'fullForm');
        final keys = [for (final o in e.endings) foldDiacritics(o.toLowerCase())];
        check(keys.toSet().length == keys.length, 'duplicate endings ${e.endings}');
        choiceChecks(e.endings, e.correctIndex, (o) => acc.contains(_k(full(o))));
      }
      check(e.stem.isNotEmpty && e.lemma.isNotEmpty && e.personLabel.isNotEmpty && e.tenseLabel.isNotEmpty, 'labels');

    case ConjGridExercise():
      check(e.cells.length >= 3, 'too few cells');
      final asked = [for (final cell in e.cells) if (!cell.prefilled) cell];
      check(asked.length >= 2, 'fewer than 2 asked cells');
      final forms = c.verbForms(item.id);
      final inflForms = c.inflections(item.id);
      check(e.inflection == (facet.kind == FacetKind.infl), 'inflection flag');
      for (final cell in e.cells) {
        final expected = e.inflection ? inflForms['${e.tense}.${cell.person}']?.form : forms['${e.tense}.${cell.person}']?.form;
        check(expected != null && expected == cell.expected, 'cell ${cell.person} expected');
        if (e.inflection && cell.person == c.meta.inflectionTables[e.tense]?.base) {
          check(cell.prefilled, 'base cell ${cell.person} is asked');
        }
        check(cell.accepted.contains(cell.expected), 'cell accepted lacks expected');
      }
      check(_subBag(_bag([for (final cell in asked) cell.expected]), _bag(e.tiles)), 'tiles miss a correct form');
      final distractors = _bagMinus(e.tiles, [for (final cell in asked) cell.expected]);
      check(distractors.isNotEmpty, 'no distractor tiles');
      check(_dupes(distractors).isEmpty, 'duplicate distractors $distractors');
      final allAccepted = {for (final cell in e.cells) for (final a in cell.accepted) _k(a)};
      for (final d in distractors) {
        check(!allAccepted.contains(_k(d)), 'distractor "$d" is a correct form');
      }
      final answer = [for (final cell in e.cells) cell.prefilled ? '' : cell.expected];
      final r = g(GridAnswer(answer));
      check(r.correct && r.cellCorrect!.every((x) => x), 'grading the solution');
      final first = e.cells.indexWhere((x) => !x.prefilled);
      for (final d in distractors) {
        final wrong = List.of(answer)..[first] = d;
        final rw = g(GridAnswer(wrong));
        check(!rw.correct && rw.cellCorrect![first] == false, 'distractor "$d" graded correct');
      }
      for (final cell in asked) {
        for (final alt in cell.accepted) {
          final a2 = [for (final x in e.cells) x == cell ? alt : (x.prefilled ? '' : x.expected)];
          check(g(GridAnswer(a2, inputMode: InputMode.keyboard)).correct, 'alt "$alt" rejected');
        }
      }

    case SentenceBuilderExercise():
      final s = c.sentence(e.sentenceId ?? '');
      check(s != null, 'sentence');
      check(e.prompt.trim().isNotEmpty && e.answers.isNotEmpty, 'empty');
      if (s != null) {
        check(e.prompt == s.translation(lang), 'prompt is not the translation');
        check(normalizeAnswer(e.answers.first.join(' ')) == normalizeAnswer(s.text), 'answer does not re-render the sentence');
        check(s.tokens.any((t) => t.lex == item.id), 'sentence lacks the item');
      }
      _tileChecks(e.tiles, e.answers, check, (a) => g(a));

    case ClozeExercise():
      final s = c.sentence(e.sentenceId ?? '');
      check(s != null, 'sentence');
      if (s != null) check('${e.before}${e.expected}${e.after}' == s.text, 'cloze does not re-render the sentence');
      check(e.expected.trim().isNotEmpty, 'empty gap');
      final acc = {for (final a in e.accepted) _k(a)};
      check(acc.contains(_k(e.expected)), 'expected not accepted');
      if (facet.kind == FacetKind.form || (facet.kind == FacetKind.prod && item.isVerb)) {
        // Independent check: the gap is (part of) a form of this verb, in the
        // facet's tense; an auxiliary counts as part of its compound form.
        final gapTokens = s == null ? const <int>[] : _tokensInRange(s, e.before.length, e.before.length + e.expected.length);
        final owners = [
          for (final i in gapTokens)
            if (_ownerCell(c, s!, i) case (final v, final cell) when v == item.id) cell,
        ];
        if (facet.kind == FacetKind.form) check(owners.isNotEmpty, 'gap is not on the verb');
        final cell = owners.firstOrNull;
        if (cell != null && facet.kind == FacetKind.form) {
          check(owners.every((x) => x.key == cell.key), 'gap spans several forms');
          check(cell.tense == facet.tense, 'gap is in the wrong tense');
          // Wrong options are not right for the cell nor for a person sharing its pronoun.
          final ctxForms = _contextForms(c, item.id, cell);
          final words = splitWords(cell.form).length;
          final opts = e.options ?? const <String>[];
          for (var i = 0; i < opts.length; i++) {
            if (i == e.correctIndex || splitWords(opts[i]).length != words) continue;
            check(!ctxForms.contains(_k(opts[i])), 'option "${opts[i]}" fits the context');
          }
        }
      }
      if (facet.kind == FacetKind.infl && s != null) {
        final gap = _tokensInRange(s, e.before.length, e.before.length + e.expected.length);
        final cell = gap.length == 1 ? _inflCellAt(c, s, gap.single, item.id, facet.table!) : null;
        check(cell != null, 'gap is not an inflected form of the item');
        if (cell != null) {
          final spec = c.meta.inflectionTables[facet.table!];
          check(spec == null || spec.agreement || cell.cell != spec.base, 'gap on the base cell of ${facet.table}');
          final opts = e.options ?? const <String>[];
          for (var i = 0; i < opts.length; i++) {
            if (i == e.correctIndex) continue;
            final problem = _inflWrongProblem(c, cell, opts[i]);
            check(problem == null, 'option: $problem');
          }
        }
      }
      if (e.options != null) {
        check(e.correctIndex != null, 'choice without correctIndex');
        check(e.options![e.correctIndex!] == e.expected, 'correct option is not expected');
        choiceChecks(e.options!, e.correctIndex!, (o) => acc.contains(_k(o)),
            minOptions: facet.kind == FacetKind.article || facet.kind == FacetKind.infl ? 2 : 3);
        if (facet.kind == FacetKind.article) {
          final valid = {for (final a in CourseIndex.of(c).articlesOf(item)) _k(a)};
          for (var i = 0; i < e.options!.length; i++) {
            if (i != e.correctIndex) check(!valid.contains(_k(e.options![i])), 'article option is valid');
          }
        }
        if (facet.kind == FacetKind.prod) {
          final syn = _synonymSpellings(c, item);
          for (var i = 0; i < e.options!.length; i++) {
            if (i != e.correctIndex) check(!syn.contains(_k(e.options![i])), 'option is a synonym');
          }
        }
      } else {
        check(g(TextAnswer(e.expected)).correct, 'free text expected rejected');
        check(g(TextAnswer('  ${e.expected.toUpperCase()}!  ')).correct, 'normalization');
        final folded = foldDiacritics(e.expected);
        // Unless the folded spelling is itself accepted (Sarnami `baaṯie` / `baatie`).
        if (folded != e.expected && !e.accepted.any((a) => normalizeAnswer(a) == normalizeAnswer(folded))) {
          final r = g(TextAnswer(folded));
          check(r.correct && r.accentSlip, 'lenient accent');
          check(!g(TextAnswer(folded), _strict).correct, 'strict accent accepted');
        }
        check(!g(const TextAnswer('qqqq')).correct, 'garbage accepted');
      }

    case SpotErrorExercise():
      final s = c.sentence(e.sentenceId ?? '');
      check(s != null, 'sentence');
      check(e.tokens.length == e.tokenIsWord.length && e.tokenPre?.length == e.tokens.length, 'token lists');
      final ei = e.errorIndex;
      check(ei >= 0 && ei < e.tokens.length && e.tokenIsWord[ei], 'error index');
      if (s == null || ei < 0 || ei >= e.tokens.length) break;
      check(_k(e.tokens[ei]) != _k(e.correction), 'error equals correction');
      // An elision swap (`il ragazzo` -> `l'ragazzo`) changes spacing, so
      // article sentences are compared without spaces.
      String norm(String x) =>
          facet.kind == FacetKind.article ? normalizeAnswer(x).replaceAll(' ', '') : normalizeAnswer(x);
      check(norm(renderSpotError(e, replace: {ei: e.correction})) == norm(s.text),
          'correction does not re-render the sentence');
      final orig = s.tokens[ei];
      check(orig.t == e.correction, 'correction is not the original token');
      if (facet.kind == FacetKind.form) {
        // The changed word belongs to the verb form (it may be the auxiliary
        // of a compound form aligned on its participle).
        final owner = _ownerCell(c, s, ei);
        final cell = owner != null && owner.$1 == item.id ? owner.$2 : null;
        check(cell != null, 'error is not on the verb');
        if (cell != null) {
          check(cell.tense == facet.tense, 'error in wrong tense');
          // The wrong word must not make any accepted form of the cell.
          for (final a in cell.accepted) {
            final w = splitWords(a);
            final i = w.indexWhere((x) => _k(x) == _k(orig.t));
            if (i < 0) continue;
            final changed = (List.of(w)..[i] = e.tokens[ei]).join(' ');
            check(!_contextForms(c, item.id, cell).contains(_k(changed)), 'swap "$changed" is still correct');
          }
        }
      } else if (facet.kind == FacetKind.infl) {
        final cell = _inflCellAt(c, s, ei, item.id, facet.table!);
        check(cell != null, 'error is not on an inflected form of the item');
        if (cell != null) {
          final problem = _inflWrongProblem(c, cell, e.tokens[ei]);
          check(problem == null, 'replacement: $problem');
        }
      } else if (facet.kind == FacetKind.article) {
        final valid = {for (final a in CourseIndex.of(c).articlesOf(item)) _k(a)};
        final shown = e.tokens[ei];
        final isWithin = orig.lex == item.id;
        final art = isWithin ? splitWords(normalizeApostrophes(shown).replaceAll("'", "' ")).first : shown;
        check(!valid.contains(_k(art)), 'replacement article "$art" is valid');
      }
      check(g(TokenAnswer(ei)).correct, 'error index graded wrong');
      for (var i = 0; i < e.tokens.length; i++) {
        if (i != ei && e.tokenIsWord[i]) check(!g(TokenAnswer(i)).correct, 'token $i graded correct');
      }

    case ListenPickExercise():
      check(e.text.trim().isNotEmpty, 'nothing to speak');
      check(e.languageCode == c.meta.target, 'language ${e.languageCode} is not the course target');
      check(facet.kind == FacetKind.rec, 'listen_pick on a ${facet.kind.name} facet');
      // Exactly one option sounds like what is spoken (and it is the text).
      final heard = soundKey(e.text);
      choiceChecks(e.options, e.correctIndex, (o) => soundKey(o) == heard);
      if (e.correctIndex >= 0 && e.correctIndex < e.options.length) {
        check(e.options[e.correctIndex] == e.text, 'correct option is not the spoken text');
      }
      check(_dupes([for (final o in e.options) soundKey(o)]).isEmpty, 'two options sound alike');
      if (e.isSentence) {
        final s = c.sentence(e.sentenceId ?? '');
        check(s != null && s.text == e.text, 'spoken text is not the sentence');
        if (s != null) {
          check(s.tokens.any((t) => t.lex == item.id), 'sentence does not contain the item');
          check(e.translation == s.translation(lang), 'translation is not the sentence translation');
        }
      } else {
        check(_k(e.text) == _k(item.lemma), 'spoken word is not the lemma');
        final spellings = {for (final x in item.spellings) _k(x)};
        for (var i = 0; i < e.options.length; i++) {
          if (i != e.correctIndex) check(!spellings.contains(_k(e.options[i])), 'option "${e.options[i]}" spells the item');
        }
      }

    case TransformExercise():
      final s = c.sentence(e.sentenceId ?? '');
      check(s != null && s.text == e.source, 'source is not the sentence');
      check(e.targetDescription.trim().isNotEmpty, 'empty description');
      check(normalizeAnswer(e.answers.first.join(' ')) != normalizeAnswer(e.source), 'answer equals source');
      // The answer contains a form of the facet's tense of this verb.
      final words = e.answers.first.map(_k).toList();
      final hasForm = c.verbForms(item.id).values.where((f) => f.tense == facet.tense).any((f) => f.accepted.any((a) {
            final w = splitWords(a).map(_k).toList();
            var j = 0;
            for (final x in words) {
              if (j < w.length && x == w[j]) j++;
            }
            return j == w.length;
          }));
      check(hasForm, 'answer lacks a ${facet.tense} form');
      _tileChecks(e.tiles, e.answers, check, (a) => g(a));
      if (s != null) {
        final srcWords = [for (final t in s.tokens) if (t.isWord) t.t];
        if (_subBag(_bag(srcWords), _bag(e.tiles))) check(!g(TilesAnswer(srcWords)).correct, 'source accepted');
      }
  }
  return p;
}

void _tileChecks(
  List<String> tiles,
  List<List<String>> answers,
  void Function(bool, String) check,
  Result Function(Answer) grade,
) {
  check(tiles.every((t) => t.trim().isNotEmpty), 'empty tile');
  final first = answers.first;
  check(first.isNotEmpty, 'empty answer');
  check(_subBag(_bag(first), _bag(tiles)), 'tiles miss answer words');
  final distractors = _bagMinus(tiles, first);
  check(distractors.isNotEmpty, 'no distractor tiles');
  check(_dupes(distractors).isEmpty, 'duplicate distractors');
  final answerWords = {for (final a in answers) for (final w in a) _k(w)};
  for (final d in distractors) {
    check(!answerWords.contains(_k(d)), 'distractor "$d" is an answer word');
  }
  final r = grade(TilesAnswer(first));
  check(r.correct && r.outcomes.single.correct, 'grading the answer');
  for (final d in distractors) {
    final wrong = List.of(first)..[0] = d;
    check(!grade(TilesAnswer(wrong)).correct, 'distractor "$d" accepted');
  }
  if (first.length > 1 && normalizeAnswer(first.first) != normalizeAnswer(first.last)) {
    final rev = first.reversed.toList();
    if (!answers.any((a) => normalizeAnswer(a.join(' ')) == normalizeAnswer(rev.join(' ')))) {
      check(!grade(TilesAnswer(rev)).correct, 'reversed order accepted');
    }
  }
}
