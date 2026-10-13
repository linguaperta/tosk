import 'package:tosk/core/core.dart';

/// A tiny Italian-like course:
///
/// * `greetings` (vocab): it:ciao, it:grazie → #rec and #prod (4 facets)
/// * `present-are` (grammar, requires greetings): mangiare, parlare #form:presente
/// * `past` (grammar, requires present-are): mangiare, parlare #form:passato_prossimo
/// * `empty` (vocab, no facets) and `after-empty` (requires empty)
///
/// it:essere has forms but no skill trains it (excluded from the verb collection).
InMemoryCourseData fakeCourse() {
  const persons = ['io', 'tu', 'lui/lei', 'noi', 'voi', 'loro'];
  const tenses = ['presente', 'passato_prossimo'];
  const meta = CourseMeta(
    id: 'it',
    version: '1.0.0',
    title: {'en': 'Italian'},
    target: 'it',
    translations: ['en', 'nl'],
    persons: persons,
    tenses: tenses,
    tenseLabels: {
      'presente': {'en': 'Present'},
      'passato_prossimo': {'en': 'Present perfect'},
    },
  );
  const items = [
    Item(id: 'it:ciao', pos: 'interj', lemma: 'ciao', tr: {'en': ['hi']}, freq: 50),
    Item(id: 'it:grazie', pos: 'interj', lemma: 'grazie', tr: {'en': ['thanks']}, freq: 40),
    Item(id: 'it:mangiare', pos: 'verb', lemma: 'mangiare', tr: {'en': ['to eat']}, freq: 312),
    Item(id: 'it:parlare', pos: 'verb', lemma: 'parlare', tr: {'en': ['to speak']}, freq: 200),
    Item(id: 'it:essere', pos: 'verb', lemma: 'essere', tr: {'en': ['to be']}, freq: 1),
  ];
  final forms = <VerbForm>[
    for (final v in ['mangiare', 'parlare', 'essere'])
      for (final t in tenses)
        for (final p in persons) VerbForm(itemId: 'it:$v', tense: t, person: p, form: '$v-$t-$p'),
  ];
  SkillFacet f(String skill, String item, FacetKind kind, int ord, [String? tense]) => SkillFacet(
      skillId: skill, facetId: FacetId(item, kind, tense).toString(), itemId: item, kind: kind, ord: ord, tense: tense);

  return InMemoryCourseData(
    meta: meta,
    units: const [Unit(id: 'u1', ord: 1, title: {'en': 'Basics'})],
    skills: const [
      Skill(id: 'greetings', unitId: 'u1', ord: 1, kind: SkillKind.vocab, title: {'en': 'Greetings'}),
      Skill(
          id: 'present-are', unitId: 'u1', ord: 2, kind: SkillKind.grammar, title: {'en': 'Present -are'},
          tense: 'presente', requires: ['greetings']),
      Skill(
          id: 'past', unitId: 'u1', ord: 3, kind: SkillKind.grammar, title: {'en': 'Past'},
          tense: 'passato_prossimo', requires: ['present-are']),
      Skill(id: 'empty', unitId: 'u1', ord: 4, kind: SkillKind.vocab, title: {'en': 'Empty'}),
      Skill(
          id: 'after-empty', unitId: 'u1', ord: 5, kind: SkillKind.vocab, title: {'en': 'After empty'},
          requires: ['empty']),
    ],
    items: items,
    skillItemIds: const {
      'greetings': ['it:ciao', 'it:grazie'],
      'present-are': ['it:mangiare', 'it:parlare'],
      'past': ['it:mangiare', 'it:parlare'],
      'after-empty': ['it:ciao'],
    },
    skillFacets: [
      f('greetings', 'it:ciao', FacetKind.rec, 1),
      f('greetings', 'it:ciao', FacetKind.prod, 2),
      f('greetings', 'it:grazie', FacetKind.rec, 3),
      f('greetings', 'it:grazie', FacetKind.prod, 4),
      f('present-are', 'it:mangiare', FacetKind.form, 1, 'presente'),
      f('present-are', 'it:parlare', FacetKind.form, 2, 'presente'),
      f('past', 'it:mangiare', FacetKind.form, 1, 'passato_prossimo'),
      f('past', 'it:parlare', FacetKind.form, 2, 'passato_prossimo'),
      f('after-empty', 'it:ciao', FacetKind.rec, 1),
    ],
    verbs: const [
      Verb(itemId: 'it:mangiare', verbClass: 'are'),
      Verb(itemId: 'it:parlare', verbClass: 'are'),
      Verb(itemId: 'it:essere', irregular: true),
    ],
    verbForms: forms,
  );
}

const greetingFacets = ['it:ciao#rec', 'it:ciao#prod', 'it:grazie#rec', 'it:grazie#prod'];
const presentFacets = ['it:mangiare#form:presente', 'it:parlare#form:presente'];
const pastFacets = ['it:mangiare#form:passato_prossimo', 'it:parlare#form:passato_prossimo'];
