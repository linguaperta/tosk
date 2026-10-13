import 'dart:math';

import '../../core/models/course.dart';
import '../../core/models/exercise.dart';
import '../../core/models/facet.dart';
import '../../core/models/progress.dart';
import '../course_index.dart';
import '../gen_context.dart';
import '../grading/rating.dart';
import '../strings.dart';
import '../template.dart';
import '../text/normalize.dart';
import 'alterations.dart';

/// A gap in a real sentence at an aligned token.
class _Gap {
  _Gap({
    required this.sentence,
    required this.from,
    required this.to,
    required this.expected,
    required this.accepted,
    required this.distractors,
    required this.instructionKey,
    this.hint,
    this.charEnd,
  });

  final Sentence sentence;

  /// Gap covers token positions [from, to] (inclusive).
  final int from;
  final int to;

  /// For an elided article inside one token: the gap is the first [charEnd]
  /// characters of token [from].
  final int? charEnd;
  final String expected;
  final List<String> accepted;
  final List<String> distractors; // unshuffled candidates
  final String instructionKey;
  final String? hint;

  String get before => renderRange(sentence, 0, from) + sentence.tokens[from].pre;
  String get after => charEnd != null
      ? sentence.tokens[from].t.substring(charEnd!) + renderRange(sentence, from + 1, sentence.tokens.length)
      : renderRange(sentence, to + 1, sentence.tokens.length);
}

/// Fill a gap in a real sentence. Choice mode while the facet is young; free
/// text when the learner prefers keyboard/ink or the facet is very stable.
///
/// * `#form:{tense}`: the gap is the verb form (a contiguous multi-word form
///   like `ho mangiato` is one gap; of a split form like Dutch `heb … gegeten`
///   only the person-dependent word is gapped). Wrong options are other forms
///   of the same verb, never an accepted form of the cell or of a person that
///   shares its pronoun.
/// * `#prod`: the gap is the item (a verb in its inflected form, with the
///   same cell of other verbs as options; other words as lemma or plural).
/// * `#article`: the gap is the article before the noun (`l'` inside
///   `l'acqua` too); options are the course's other articles.
class ClozeTemplate extends ExerciseTemplate {
  const ClozeTemplate({this.optionCount = 4});

  final int optionCount;

  @override
  ExerciseType get type => ExerciseType.cloze;

  @override
  Set<FacetKind> get kinds => const {FacetKind.form, FacetKind.prod, FacetKind.article};

  @override
  bool canGenerate(SkillFacet facet, GenContext ctx) => supports(facet) && _gaps(facet, ctx, shuffle: false).isNotEmpty;

  int _minDistractors(SkillFacet f) => f.kind == FacetKind.article ? 1 : 2;

  List<_Gap> _gaps(SkillFacet facet, GenContext ctx, {bool shuffle = true, int limit = 1 << 30}) {
    final item = ctx.course.item(facet.itemId);
    if (item == null) return const [];
    final out = <_Gap>[];
    final minD = _minDistractors(facet);
    void add(_Gap? g) {
      if (g != null && g.distractors.length >= minD) out.add(g);
    }

    switch (facet.kind) {
      case FacetKind.form:
        final occ = ctx.index.formOccurrencesIn(facet.itemId, facet.tense!);
        for (final o in shuffle ? ctx.shuffled(occ) : occ) {
          if (out.length >= limit) break;
          add(_formGap(o, item, ctx));
        }
      case FacetKind.prod:
        if (item.isVerb) {
          final occ = ctx.index.formOccurrences(facet.itemId);
          for (final o in shuffle ? ctx.shuffled(occ) : occ) {
            if (out.length >= limit) break;
            if (o.contiguous) add(_verbProdGap(o, item, ctx));
          }
        } else {
          final occ = ctx.index.wordOccurrences(facet.itemId);
          for (final o in shuffle ? ctx.shuffled(occ) : occ) {
            if (out.length >= limit) break;
            add(_wordGap(o, item, ctx));
          }
        }
      case FacetKind.article:
        final occ = ctx.index.articleOccurrences(facet.itemId);
        for (final o in shuffle ? ctx.shuffled(occ) : occ) {
          if (out.length >= limit) break;
          add(_articleGap(o, item, ctx));
        }
      case FacetKind.rec:
        break;
    }
    return out;
  }

  /// Gap over a verb form occurrence for a `#form` facet.
  _Gap? _formGap(FormOccurrence o, Item verb, GenContext ctx) {
    final ix = ctx.index;
    final forms = ctx.course.verbForms(o.verbId);
    final meta = ctx.course.meta;
    final hint = formHint(meta, verb, o.person, o.tense, ctx.lang);
    if (o.contiguous) {
      final expected = renderRange(o.sentence, o.positions.first, o.positions.last + 1, includeFirstPre: false);
      final forbidden = contextKeys(ix, o.verbId, o.tense, o.person);
      final picker = OptionPicker(forbidden: [...o.cell.accepted, expected], max: optionCount - 1);
      final sameTense = <String>[];
      final sameP = <String>[];
      final rest = <String>[];
      for (final f in forms.values) {
        if (f.person == kNoPerson || f.key == o.cell.key) continue;
        if (forbidden.contains(foldAnswer(f.form))) continue;
        final opt = matchCase(f.form, expected);
        if (f.tense == o.tense) {
          sameTense.add(opt);
        } else if (f.person == o.person) {
          sameP.add(opt);
        } else {
          rest.add(opt);
        }
      }
      picker.addGroups([sameTense, sameP, rest], ctx.random);
      return _Gap(
        sentence: o.sentence,
        from: o.positions.first,
        to: o.positions.last,
        expected: expected,
        accepted: o.cell.accepted,
        distractors: picker.picked,
        instructionKey: 'cloze.form',
        hint: hint,
      );
    }
    // Split form: gap the person-dependent word.
    final cells = ix.finiteForms(o.verbId, o.tense);
    final n = o.wordCount;
    int? k;
    for (var j = 0; j < n && k == null; j++) {
      final variants = {
        for (final c in cells)
          if (splitWords(c.form).length == n) foldAnswer(splitWords(c.form)[j]),
      };
      if (variants.length > 1) k = j;
    }
    if (k == null) return null;
    final kk = k;
    final surface = o.surface;
    bool othersMatch(List<String> w) {
      for (var j = 0; j < n; j++) {
        if (j != kk && foldAnswer(w[j]) != foldAnswer(surface[j])) return false;
      }
      return true;
    }

    List<String> partials(VerbForm f) => [
          for (final a in f.accepted)
            if (splitWords(a).length == n && othersMatch(splitWords(a))) splitWords(a)[kk],
        ];
    final accepted = partials(o.cell);
    if (accepted.isEmpty) return null;
    final forbidden = [
      ...accepted,
      for (final p in ix.ambiguousPersons(o.person))
        if (forms['${o.tense}.$p'] != null) ...partials(forms['${o.tense}.$p']!),
    ];
    final expected = surface[kk];
    final picker = OptionPicker(forbidden: [...forbidden, expected], max: optionCount - 1);
    final ownOthers = [
      for (final c in cells)
        if (c.person != o.person && splitWords(c.form).length == n) matchCase(splitWords(c.form)[kk], expected),
    ];
    final auxAmbiguous = (ctx.course.verb(o.verbId)?.auxiliary ?? '').contains('|');
    final otherVerbs = <String>[
      if (!auxAmbiguous)
        for (final v in ix.verbs)
          if (v.id != o.verbId)
            if (ctx.course.verbForms(v.id)[o.cell.key] case final f?)
              if (splitWords(f.form).length == n) matchCase(splitWords(f.form)[kk], expected),
    ];
    picker.addGroups([ownOthers, otherVerbs], ctx.random);
    final pos = o.positions[kk];
    return _Gap(
      sentence: o.sentence,
      from: pos,
      to: pos,
      expected: expected,
      accepted: accepted,
      distractors: picker.picked,
      instructionKey: 'cloze.form',
      hint: hint,
    );
  }

  /// Gap over a verb for its `#prod` facet: options are the same cell of other verbs.
  _Gap? _verbProdGap(FormOccurrence o, Item verb, GenContext ctx) {
    final ix = ctx.index;
    final expected = renderRange(o.sentence, o.positions.first, o.positions.last + 1, includeFirstPre: false);
    final syn = {for (final s in ix.synonymsOf(verb)) s.id};
    final forbidden = [
      ...o.cell.accepted,
      expected,
      for (final s in syn)
        if (ctx.course.verbForms(s)[o.cell.key] case final f?) ...f.accepted,
    ];
    final picker = OptionPicker(forbidden: forbidden, max: optionCount - 1);
    final groups = ix.relatedItems(verb);
    picker.addGroups([
      for (final g in groups)
        [
          for (final v in g)
            if (!syn.contains(v.id))
              if (ctx.course.verbForms(v.id)[o.cell.key] case final f?) matchCase(f.form, expected),
        ],
    ], ctx.random);
    return _Gap(
      sentence: o.sentence,
      from: o.positions.first,
      to: o.positions.last,
      expected: expected,
      accepted: o.cell.accepted,
      distractors: picker.picked,
      instructionKey: 'cloze',
      hint: verb.gloss(ctx.lang),
    );
  }

  _Gap? _wordGap(WordOccurrence o, Item item, GenContext ctx) {
    final ix = ctx.index;
    final expected = o.sentence.tokens[o.pos].t;
    final accepted = o.plural ? [item.plural!] : item.spellings;
    final syn = ix.synonymsOf(item);
    final forbidden = [
      ...accepted,
      expected,
      for (final s in syn) ...[...s.spellings, ?s.plural],
    ];
    final picker = OptionPicker(forbidden: forbidden, max: optionCount - 1);
    picker.addGroups([
      for (final g in ix.relatedItems(item))
        [
          for (final v in g)
            if (o.plural ? v.plural != null : true)
              if (splitWords(o.plural ? v.plural! : v.lemma).length == 1)
                matchCase(o.plural ? v.plural! : v.lemma, expected),
        ],
    ], ctx.random);
    return _Gap(
      sentence: o.sentence,
      from: o.pos,
      to: o.pos,
      expected: expected,
      accepted: accepted,
      distractors: picker.picked,
      instructionKey: 'cloze',
      hint: item.gloss(ctx.lang),
    );
  }

  _Gap? _articleGap(ArticleOccurrence o, Item noun, GenContext ctx) {
    final ix = ctx.index;
    final valid = ix.articlesOf(noun);
    final picker = OptionPicker(forbidden: [...valid, o.article], max: optionCount - 1);
    picker.addGroups([
      [for (final a in wrongArticles(ix, noun)) matchCase(a, o.article)],
    ], ctx.random);
    return _Gap(
      sentence: o.sentence,
      from: o.articlePos,
      to: o.articlePos,
      charEnd: o.withinToken ? o.article.length : null,
      expected: o.article,
      accepted: valid,
      distractors: picker.picked,
      instructionKey: 'cloze.article',
      hint: noun.gloss(ctx.lang),
    );
  }

  @override
  Exercise? generate(SkillFacet facet, GenContext ctx) {
    if (!supports(facet)) return null;
    final gaps = _gaps(facet, ctx, limit: 3);
    if (gaps.isEmpty) return null;
    final g = gaps[ctx.random.nextInt(min(gaps.length, 3))];
    final free = ctx.freeText(facet.facetId);
    List<String>? options;
    int? correctIndex;
    if (!free) {
      final (o, i) = placeOptions(g.expected, g.distractors, ctx.random);
      options = o;
      correctIndex = i;
    }
    return ClozeExercise(
      id: ctx.nextId(),
      facetId: facet.facetId,
      skillId: ctx.skill?.id,
      instruction: instruction(g.instructionKey, ctx.lang),
      before: g.before,
      after: g.after,
      expected: g.expected,
      accepted: {g.expected, ...g.accepted}.toList(),
      options: options,
      correctIndex: correctIndex,
      hint: g.hint,
      translation: g.sentence.translation(ctx.lang),
      sentenceId: g.sentence.id,
    );
  }

  @override
  Result grade(Exercise exercise, Answer answer, {required Duration elapsed, GradeOptions options = const GradeOptions()}) {
    final e = exercise as ClozeExercise;
    if (answer is ChoiceAnswer && e.options != null && e.correctIndex != null) {
      return gradeChoice(e, answer, e.options!, e.correctIndex!, elapsed: elapsed, grade: options);
    }
    if (answer is TextAnswer) {
      final m = matchAnswer(answer.text, e.accepted, options.accents, candidates: answer.candidates);
      return Result(
        correct: m.correct,
        expected: e.expected,
        given: answer.text,
        accentSlip: m.accentSlip,
        outcomes: [
          rateOutcome(e.type, e.facetId, correct: m.correct, elapsed: elapsed, options: options, accentSlip: m.accentSlip),
        ],
      );
    }
    return wrongKind(e, answer, e.expected);
  }
}
