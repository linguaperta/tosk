/// Small hand-made demo courses. The app falls back to them (labelled "Demo")
/// when no course pack is installed, and widget tests use them.
/// Content is illustrative only (and the demo Dutch course is flagged unverified
/// to exercise the badge).
library;

import '../../core/core.dart';
import '../course_catalog.dart';

class DemoCourseCatalog implements CourseCatalog {
  DemoCourseCatalog();

  late final Map<String, CourseData> _courses = {'it': buildDemoItalian(), 'nl': buildDemoDutch()};

  @override
  Future<List<CourseMeta>> listCourses() async => [for (final c in _courses.values) c.meta];

  @override
  Future<CourseData> open(String courseId) async {
    final c = _courses[courseId];
    if (c == null) throw ArgumentError('Unknown course: $courseId');
    return c;
  }

  @override
  bool isDemo(String courseId) => true;
}

// ------------------------------------------------------------------ helpers

class _Builder {
  _Builder(this.courseId);
  final String courseId;
  final items = <Item>[];
  final skillItems = <String, List<String>>{};
  final facets = <SkillFacet>[];
  final verbs = <Verb>[];
  final forms = <VerbForm>[];

  String id(String lemma) => '$courseId:$lemma';

  void item(
    String lemma,
    String pos,
    String en,
    String nl, {
    String? article,
    int? freq,
    String? unit,
    List<String> tags = const [],
    String? gender,
  }) {
    items.add(
      Item(
        id: id(lemma),
        pos: pos,
        lemma: lemma,
        tr: {
          'en': [en],
          'nl': [nl],
        },
        article: article,
        gender: gender,
        freq: freq,
        unitId: unit,
        tags: tags,
      ),
    );
  }

  /// Vocab skill: `#rec` and `#prod` per item.
  void vocab(String skillId, List<String> lemmas) {
    skillItems[skillId] = [for (final l in lemmas) id(l)];
    var ord = 0;
    for (final l in lemmas) {
      facets.add(SkillFacet(skillId: skillId, facetId: '${id(l)}#rec', itemId: id(l), kind: FacetKind.rec, ord: ord++));
      facets.add(
        SkillFacet(skillId: skillId, facetId: '${id(l)}#prod', itemId: id(l), kind: FacetKind.prod, ord: ord++),
      );
    }
  }

  /// Verb grammar skill: `#form:{tense}` per verb.
  void verbSkill(String skillId, String tense, List<String> lemmas) {
    skillItems[skillId] = [for (final l in lemmas) id(l)];
    var ord = 0;
    for (final l in lemmas) {
      facets.add(
        SkillFacet(
          skillId: skillId,
          facetId: '${id(l)}#form:$tense',
          itemId: id(l),
          kind: FacetKind.form,
          tense: tense,
          ord: ord++,
        ),
      );
    }
  }

  /// Article skill: `#article` per noun.
  void articleSkill(String skillId, List<String> lemmas) {
    skillItems[skillId] = [for (final l in lemmas) id(l)];
    var ord = 0;
    for (final l in lemmas) {
      facets.add(
        SkillFacet(skillId: skillId, facetId: '${id(l)}#article', itemId: id(l), kind: FacetKind.article, ord: ord++),
      );
    }
  }

  void verb(
    String lemma,
    String tense,
    List<String> persons,
    String stem,
    List<String> endings, {
    String? cls,
    bool irregular = false,
    List<String>? full,
  }) {
    if (!verbs.any((v) => v.itemId == id(lemma))) {
      verbs.add(Verb(itemId: id(lemma), verbClass: cls, stem: stem, irregular: irregular));
    }
    for (var i = 0; i < persons.length; i++) {
      final form = full != null ? full[i] : '$stem${endings[i]}';
      forms.add(
        VerbForm(
          itemId: id(lemma),
          tense: tense,
          person: persons[i],
          form: form,
          stem: full == null ? stem : null,
          ending: full == null ? endings[i] : null,
        ),
      );
    }
  }
}

Map<String, I18n> _labels(Map<String, (String, String)> m) => {
  for (final e in m.entries) e.key: {'en': e.value.$1, 'nl': e.value.$2},
};

// ------------------------------------------------------------------ Italian

const _itPersons = ['io', 'tu', 'lui/lei', 'noi', 'voi', 'loro'];

CourseData buildDemoItalian() {
  final b = _Builder('it');
  b.item('ciao', 'intj', 'hi / bye', 'hoi / doei', freq: 40, unit: 'u1', tags: ['greetings']);
  b.item('buongiorno', 'intj', 'good morning', 'goedemorgen', freq: 300, unit: 'u1', tags: ['greetings']);
  b.item('grazie', 'intj', 'thank you', 'dank je', freq: 90, unit: 'u1', tags: ['greetings']);
  b.item('arrivederci', 'intj', 'goodbye', 'tot ziens', freq: 900, unit: 'u1', tags: ['greetings']);
  b.item('pane', 'noun', 'bread', 'brood', article: 'il', gender: 'm', freq: 700, unit: 'u1', tags: ['food']);
  b.item('acqua', 'noun', 'water', 'water', article: "l'", gender: 'f', freq: 500, unit: 'u1', tags: ['food']);
  b.item('mela', 'noun', 'apple', 'appel', article: 'la', gender: 'f', freq: 1500, unit: 'u1', tags: ['food']);
  b.item('formaggio', 'noun', 'cheese', 'kaas', article: 'il', gender: 'm', freq: 1800, unit: 'u1', tags: ['food']);
  b.item('madre', 'noun', 'mother', 'moeder', article: 'la', gender: 'f', freq: 400, unit: 'u1', tags: ['family']);
  b.item('padre', 'noun', 'father', 'vader', article: 'il', gender: 'm', freq: 380, unit: 'u1', tags: ['family']);
  b.item('fratello', 'noun', 'brother', 'broer', article: 'il', gender: 'm', freq: 800, unit: 'u1', tags: ['family']);
  b.item('sorella', 'noun', 'sister', 'zus', article: 'la', gender: 'f', freq: 850, unit: 'u1', tags: ['family']);
  b.item('mangiare', 'verb', 'to eat', 'eten', freq: 312, unit: 'u2');
  b.item('parlare', 'verb', 'to speak', 'spreken', freq: 250, unit: 'u2');
  b.item('comprare', 'verb', 'to buy', 'kopen', freq: 600, unit: 'u2');
  b.item('prendere', 'verb', 'to take', 'nemen', freq: 150, unit: 'u2');
  b.item('leggere', 'verb', 'to read', 'lezen', freq: 420, unit: 'u2');
  b.item('dormire', 'verb', 'to sleep', 'slapen', freq: 650, unit: 'u2');
  b.item('partire', 'verb', 'to leave', 'vertrekken', freq: 520, unit: 'u2');
  b.item('essere', 'verb', 'to be', 'zijn', freq: 2, unit: 'u2');
  b.item('avere', 'verb', 'to have', 'hebben', freq: 5, unit: 'u2');
  b.item('ieri', 'adv', 'yesterday', 'gisteren', freq: 700, unit: 'u3', tags: ['time']);
  b.item('oggi', 'adv', 'today', 'vandaag', freq: 200, unit: 'u3', tags: ['time']);
  b.item('domani', 'adv', 'tomorrow', 'morgen', freq: 450, unit: 'u3', tags: ['time']);

  const are = ['o', 'i', 'a', 'iamo', 'ate', 'ano'];
  const ere = ['o', 'i', 'e', 'iamo', 'ete', 'ono'];
  const ire = ['o', 'i', 'e', 'iamo', 'ite', 'ono'];
  b.verb('mangiare', 'presente', _itPersons, 'mang', const ['io', 'i', 'ia', 'iamo', 'iate', 'iano'], cls: 'are');
  b.verb('parlare', 'presente', _itPersons, 'parl', are, cls: 'are');
  b.verb('comprare', 'presente', _itPersons, 'compr', are, cls: 'are');
  b.verb('prendere', 'presente', _itPersons, 'prend', ere, cls: 'ere');
  b.verb('leggere', 'presente', _itPersons, 'legg', ere, cls: 'ere');
  b.verb('dormire', 'presente', _itPersons, 'dorm', ire, cls: 'ire');
  b.verb('partire', 'presente', _itPersons, 'part', ire, cls: 'ire');
  b.verb(
    'essere',
    'presente',
    _itPersons,
    '',
    const [],
    irregular: true,
    full: const ['sono', 'sei', 'è', 'siamo', 'siete', 'sono'],
  );
  b.verb(
    'avere',
    'presente',
    _itPersons,
    '',
    const [],
    irregular: true,
    full: const ['ho', 'hai', 'ha', 'abbiamo', 'avete', 'hanno'],
  );
  b.verb(
    'mangiare',
    'passato_prossimo',
    _itPersons,
    '',
    const [],
    full: const ['ho mangiato', 'hai mangiato', 'ha mangiato', 'abbiamo mangiato', 'avete mangiato', 'hanno mangiato'],
  );
  b.verb(
    'parlare',
    'passato_prossimo',
    _itPersons,
    '',
    const [],
    full: const ['ho parlato', 'hai parlato', 'ha parlato', 'abbiamo parlato', 'avete parlato', 'hanno parlato'],
  );

  b.vocab('greetings', ['ciao', 'buongiorno', 'grazie', 'arrivederci']);
  b.vocab('food', ['pane', 'acqua', 'mela', 'formaggio']);
  b.articleSkill('articles', ['pane', 'acqua', 'mela', 'formaggio', 'madre', 'padre']);
  b.vocab('family', ['madre', 'padre', 'fratello', 'sorella']);
  b.verbSkill('present-are', 'presente', ['mangiare', 'parlare', 'comprare']);
  b.verbSkill('essere-avere', 'presente', ['essere', 'avere']);
  b.verbSkill('present-ere', 'presente', ['prendere', 'leggere']);
  b.verbSkill('present-ire', 'presente', ['dormire', 'partire']);
  b.verbSkill('passato', 'passato_prossimo', ['mangiare', 'parlare']);
  b.vocab('time', ['ieri', 'oggi', 'domani']);

  Skill skill(
    String id,
    String unit,
    int ord,
    SkillKind kind,
    String en,
    String nl, {
    String? icon,
    List<String> requires = const [],
    String? tense,
    int? posX,
    int? posY,
  }) => Skill(
    id: id,
    unitId: unit,
    ord: ord,
    kind: kind,
    title: {'en': en, 'nl': nl},
    icon: icon,
    requires: requires,
    tense: tense,
    posX: posX,
    posY: posY,
  );

  const v = SkillKind.vocab, g = SkillKind.grammar;
  final skills = [
    skill('greetings', 'u1', 1, v, 'Greetings', 'Begroetingen', icon: 'wave'),
    skill('food', 'u1', 2, v, 'Food', 'Eten', icon: 'food', requires: ['greetings']),
    skill('articles', 'u1', 3, g, 'Articles', 'Lidwoorden', icon: 'article', requires: ['greetings']),
    skill('family', 'u1', 4, v, 'Family', 'Familie', icon: 'family', requires: ['greetings']),
    skill(
      'present-are',
      'u2',
      1,
      g,
      'Present: -are',
      'Presente: -are',
      icon: 'verb',
      requires: ['food'],
      tense: 'presente',
    ),
    skill(
      'essere-avere',
      'u2',
      2,
      g,
      'Essere & avere',
      'Essere & avere',
      icon: 'grammar',
      requires: ['articles'],
      tense: 'presente',
    ),
    skill(
      'present-ere',
      'u2',
      3,
      g,
      'Present: -ere',
      'Presente: -ere',
      icon: 'verb',
      requires: ['present-are'],
      tense: 'presente',
    ),
    skill(
      'present-ire',
      'u2',
      4,
      g,
      'Present: -ire',
      'Presente: -ire',
      icon: 'verb',
      requires: ['present-are'],
      tense: 'presente',
    ),
    skill(
      'passato',
      'u3',
      1,
      g,
      'Passato prossimo',
      'Passato prossimo',
      icon: 'past',
      requires: ['present-ere', 'essere-avere'],
      tense: 'passato_prossimo',
    ),
    // `pos` override: pinned to row 1, column 0 of its band.
    skill('time', 'u3', 2, v, 'Time', 'Tijd', icon: 'time', requires: ['passato'], posX: 0, posY: 1),
  ];

  final sentences = [
    Sentence(
      id: 's:demo1',
      text: 'Mangiamo alle otto.',
      tr: const {'en': 'We eat at eight.', 'nl': 'We eten om acht uur.'},
      tokens: const [
        Token(idx: 0, t: 'Mangiamo', lex: 'it:mangiare', form: 'presente.noi'),
        Token(idx: 1, t: 'alle', pre: ' '),
        Token(idx: 2, t: 'otto', pre: ' '),
        Token(idx: 3, t: '.', isWord: false),
      ],
    ),
  ];

  return InMemoryCourseData(
    meta: CourseMeta(
      id: 'it',
      version: '0.0.0-demo',
      title: const {'en': 'Italian', 'nl': 'Italiaans'},
      target: 'it',
      translations: const ['en', 'nl'],
      persons: _itPersons,
      tenses: const ['presente', 'passato_prossimo'],
      tenseLabels: _labels(const {
        'presente': ('present', 'tegenwoordige tijd'),
        'passato_prossimo': ('present perfect', 'voltooid tegenwoordige tijd'),
      }),
      articles: const ['il', 'lo', 'la', "l'", 'i', 'gli', 'le'],
      attribution: 'Demo data (hand-made)',
      description: const {'en': 'A small sample course.', 'nl': 'Een kleine voorbeeldcursus.'},
    ),
    units: const [
      Unit(id: 'u1', ord: 1, title: {'en': 'Basics', 'nl': 'Basis'}),
      Unit(id: 'u2', ord: 2, title: {'en': 'Present tense', 'nl': 'Tegenwoordige tijd'}),
      Unit(id: 'u3', ord: 3, title: {'en': 'The past', 'nl': 'Het verleden'}),
    ],
    skills: skills,
    items: b.items,
    skillItemIds: b.skillItems,
    skillFacets: b.facets,
    verbs: b.verbs,
    verbForms: b.forms,
    sentences: sentences,
    notes: const {
      'present-are': {'en': _presentAreEn, 'nl': _presentAreNl},
      'essere-avere': {'en': _essereAvereEn},
      'articles': {'en': _articlesEn, 'nl': _articlesNl},
      'passato': {'en': _passatoEn},
    },
  );
}

const _presentAreEn = '''
# Present tense of -are verbs

Most Italian verbs end in **-are**. Drop the ending to get the *stem*, then add:

| Person | Ending | mangiare |
| --- | --- | --- |
| io | -o | mangio |
| tu | -i | mangi |
| lui/lei | -a | mangia |
| noi | -iamo | mangiamo |
| voi | -ate | mangiate |
| loro | -ano | mangiano |

## Watch out

- Verbs in **-iare** keep only one *i*: `mangi`, not ~~mangii~~.
- Subject pronouns are usually dropped: *Mangiamo alle otto.*
''';

const _presentAreNl = '''
# Tegenwoordige tijd van werkwoorden op -are

De meeste Italiaanse werkwoorden eindigen op **-are**. Haal de uitgang weg voor de *stam* en voeg toe:

| Persoon | Uitgang | mangiare |
| --- | --- | --- |
| io | -o | mangio |
| tu | -i | mangi |
| lui/lei | -a | mangia |
| noi | -iamo | mangiamo |
| voi | -ate | mangiate |
| loro | -ano | mangiano |

- Werkwoorden op **-iare** houden maar één *i*: `mangi`.
''';

const _essereAvereEn = '''
# Essere and avere

The two most important irregular verbs. Learn them by heart.

1. **essere** (to be): sono, sei, è, siamo, siete, sono
2. **avere** (to have): ho, hai, ha, abbiamo, avete, hanno

> The *h* in **ho, hai, ha, hanno** is silent.
''';

const _articlesEn = '''
# Definite articles

- **il** before most masculine nouns: *il pane*
- **la** before feminine nouns: *la mela*
- **l'** before a vowel: *l'acqua*
''';

const _articlesNl = '''
# Bepaalde lidwoorden

- **il** voor de meeste mannelijke woorden: *il pane*
- **la** voor vrouwelijke woorden: *la mela*
- **l'** voor een klinker: *l'acqua*
''';

const _passatoEn = '''
# Passato prossimo

Formed with **avere** (or **essere**) plus the past participle.

- mangiare → *ho mangiato*
- parlare → *ho parlato*
''';

// ------------------------------------------------------------------ Dutch

const _nlPersons = ['ik', 'jij', 'hij/zij', 'wij', 'jullie', 'zij'];

CourseData buildDemoDutch() {
  final b = _Builder('nl');
  b.item('hallo', 'intj', 'hello', 'hallo', freq: 100, unit: 'u1', tags: ['greetings']);
  b.item('dank je', 'intj', 'thank you', 'dank je', freq: 200, unit: 'u1', tags: ['greetings']);
  b.item('tot ziens', 'intj', 'goodbye', 'tot ziens', freq: 600, unit: 'u1', tags: ['greetings']);
  b.item('goedemorgen', 'intj', 'good morning', 'goedemorgen', freq: 800, unit: 'u1', tags: ['greetings']);
  b.item('brood', 'noun', 'bread', 'brood', article: 'het', freq: 700, unit: 'u1', tags: ['food']);
  b.item('appel', 'noun', 'apple', 'appel', article: 'de', freq: 1200, unit: 'u1', tags: ['food']);
  b.item('kaas', 'noun', 'cheese', 'kaas', article: 'de', freq: 1300, unit: 'u1', tags: ['food']);
  b.item('water', 'noun', 'water', 'water', article: 'het', freq: 400, unit: 'u1', tags: ['food']);
  b.item('werken', 'verb', 'to work', 'werken', freq: 300, unit: 'u2');
  b.item('lopen', 'verb', 'to walk', 'lopen', freq: 350, unit: 'u2');
  b.item('eten', 'verb', 'to eat', 'eten', freq: 380, unit: 'u2');

  b.verb('werken', 'presens', _nlPersons, 'werk', const ['', 't', 't', 'en', 'en', 'en']);
  b.verb(
    'lopen',
    'presens',
    _nlPersons,
    '',
    const [],
    full: const ['loop', 'loopt', 'loopt', 'lopen', 'lopen', 'lopen'],
  );
  b.verb('eten', 'presens', _nlPersons, '', const [], full: const ['eet', 'eet', 'eet', 'eten', 'eten', 'eten']);
  b.verb(
    'werken',
    'perfectum',
    _nlPersons,
    '',
    const [],
    full: const ['heb gewerkt', 'hebt gewerkt', 'heeft gewerkt', 'hebben gewerkt', 'hebben gewerkt', 'hebben gewerkt'],
  );

  b.vocab('groeten', ['hallo', 'dank je', 'tot ziens', 'goedemorgen']);
  b.vocab('eten', ['brood', 'appel', 'kaas', 'water']);
  b.articleSkill('de-het', ['brood', 'appel', 'kaas', 'water']);
  b.verbSkill('presens', 'presens', ['werken', 'lopen', 'eten']);
  b.verbSkill('perfectum', 'perfectum', ['werken']);

  return InMemoryCourseData(
    meta: CourseMeta(
      id: 'nl',
      version: '0.0.0-demo',
      title: const {'en': 'Dutch', 'nl': 'Nederlands'},
      target: 'nl',
      translations: const ['en'],
      persons: _nlPersons,
      tenses: const ['presens', 'perfectum'],
      tenseLabels: _labels(const {
        'presens': ('present', 'tegenwoordige tijd'),
        'perfectum': ('present perfect', 'voltooide tijd'),
      }),
      articles: const ['de', 'het'],
      unverified: true,
      attribution: 'Demo data (hand-made)',
      description: const {'en': 'A small sample course.', 'nl': 'Een kleine voorbeeldcursus.'},
    ),
    units: const [
      Unit(id: 'u1', ord: 1, title: {'en': 'Basics'}),
      Unit(id: 'u2', ord: 2, title: {'en': 'Verbs'}),
    ],
    skills: const [
      Skill(id: 'groeten', unitId: 'u1', ord: 1, kind: SkillKind.vocab, title: {'en': 'Greetings'}, icon: 'wave'),
      Skill(
        id: 'eten',
        unitId: 'u1',
        ord: 2,
        kind: SkillKind.vocab,
        title: {'en': 'Food'},
        icon: 'food',
        requires: ['groeten'],
      ),
      Skill(
        id: 'de-het',
        unitId: 'u1',
        ord: 3,
        kind: SkillKind.grammar,
        title: {'en': 'De or het'},
        icon: 'article',
        requires: ['groeten'],
      ),
      Skill(
        id: 'presens',
        unitId: 'u2',
        ord: 1,
        kind: SkillKind.grammar,
        title: {'en': 'Present tense'},
        icon: 'verb',
        tense: 'presens',
        requires: ['eten', 'de-het'],
      ),
      Skill(
        id: 'perfectum',
        unitId: 'u2',
        ord: 2,
        kind: SkillKind.grammar,
        title: {'en': 'Perfectum'},
        icon: 'past',
        tense: 'perfectum',
        requires: ['presens'],
      ),
    ],
    items: b.items,
    skillItemIds: b.skillItems,
    skillFacets: b.facets,
    verbs: b.verbs,
    verbForms: b.forms,
    notes: const {
      'presens': {
        'en':
            '# Present tense\n\nStem + **-t** for *jij* and *hij/zij*; **-en** in the plural.\n\n'
            '| Person | werken |\n| --- | --- |\n| ik | werk |\n| jij | werkt |\n| hij/zij | werkt |\n'
            '| wij | werken |\n| jullie | werken |\n| zij | werken |\n',
      },
      'de-het': {'en': '# De or het\n\n- Most nouns take **de**.\n- Diminutives (*-je*) always take **het**.\n'},
    },
  );
}
