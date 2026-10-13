/// A mini Dutch course (for English speakers): 3 units, 10 skills, 18 verbs
/// with full tegenwoordige tijd and perfectum tables, de/het nouns and 45+
/// aligned sentences.
///
/// Tricky cases on purpose:
/// * homographs: `eet`/`praat` (ik = jij = hij), `werken`/`hebben` (wij =
///   jullie = zij), `dag` (noun "day") vs `dag` (greeting, id `nl:dag.2`)
/// * the person keys `hij/zij` and `zij` share the pronoun "zij"
/// * inversion: `Werk jij…?` / `Heb jij…?` (the jij form drops -t), aligned
///   to the jij cell whose form is `werkt`/`hebt`
/// * split perfectum: `heb … gegeten`, reversed in a subordinate clause
///   (`gegeten heeft`), contiguous at the end (`hebben gewerkt.`)
/// * verbs taking hebben or zijn (`zwemmen`, `lopen`: both auxiliaries accepted)
/// * overlapping glosses: praten/spreken ("to talk"), huis/thuis ("home"),
///   hallo/dag.2 ("hello"); a variant spelling (cadeau/kado); multi-word
///   lemmas (`tot ziens`, `dank je`)
library;

import 'package:tosk/core/core.dart';

import 'course_builder.dart';

const _tt = 'tegenwoordige_tijd';
const _pf = 'perfectum';

/// Regular present: stem for ik/jij/hij, plural stem for wij/jullie/zij.
List<String> _reg(String sg, String pl, {bool tStem = false}) => [
      '$sg|',
      tStem ? '$sg|' : '$sg|t',
      tStem ? '$sg|' : '$sg|t',
      '$pl|en',
      '$pl|en',
      '$pl|en',
    ];

/// Perfectum with hebben (and zijn as accepted alternative when [both]).
List<String> _hebben(String participle, {bool both = false}) {
  const h = ['heb', 'hebt', 'heeft', 'hebben', 'hebben', 'hebben'];
  const z = ['ben', 'bent', 'is', 'zijn', 'zijn', 'zijn'];
  return [for (var i = 0; i < 6; i++) both ? '${h[i]} $participle;${z[i]} $participle' : '${h[i]} $participle'];
}

List<String> _zijn(String participle) =>
    ['ben', 'bent', 'is', 'zijn', 'zijn', 'zijn'].map((a) => '$a $participle').toList();

InMemoryCourseData dutchCourse() {
  final b = CourseBuilder(const CourseMeta(
    id: 'nl',
    version: '0.1.0',
    title: {'en': 'Dutch', 'nl': 'Nederlands'},
    target: 'nl',
    translations: ['en'],
    persons: ['ik', 'jij', 'hij/zij', 'wij', 'jullie', 'zij'],
    tenses: [_tt, _pf],
    tenseLabels: {
      _tt: {'en': 'present', 'nl': 'tegenwoordige tijd'},
      _pf: {'en': 'present perfect', 'nl': 'voltooid tegenwoordige tijd'},
    },
    personLabels: {
      'zij': {'en': 'zij (they)', 'nl': 'zij (meervoud)'},
    },
    articles: ['de', 'het'],
    attribution: 'Hand-written test fixture.',
  ));

  // ------------------------------------------------------------ unit 1
  b.unit('u1', 0, 'Basics', 'Basis');
  b.word('hallo', 'intj', en: ['hello', 'hi'], freq: 300, tags: ['greetings']);
  b.word('hoi', 'intj', en: ['hi', 'hey'], freq: 600, tags: ['greetings']);
  b.word('dag', 'intj', itemId: 'dag.2', en: ['bye', 'hello'], freq: 700, tags: ['greetings']);
  b.word('goedemorgen', 'intj', en: ['good morning'], freq: 900, tags: ['greetings']);
  b.word('tot ziens', 'phrase', itemId: 'tot_ziens', en: ['goodbye', 'see you'], freq: 800, tags: ['greetings']);
  b.word('dank je', 'phrase', itemId: 'dank_je', en: ['thank you', 'thanks'], freq: 400, tags: ['greetings']);
  b.word('alsjeblieft', 'intj', en: ['please', 'here you go'], freq: 500, tags: ['greetings']);
  b.word('sorry', 'intj', en: ['sorry'], freq: 450, tags: ['greetings']);

  b.noun('de', 'man', ['man'], gender: 'm', plural: 'mannen', freq: 90, tags: ['people']);
  b.noun('de', 'vrouw', ['woman', 'wife'], gender: 'f', plural: 'vrouwen', freq: 100, tags: ['people']);
  b.noun('het', 'kind', ['child', 'kid'], gender: 'n', plural: 'kinderen', freq: 120, tags: ['people']);
  b.noun('de', 'jongen', ['boy'], gender: 'm', plural: 'jongens', freq: 200, tags: ['people']);
  b.noun('het', 'meisje', ['girl'], gender: 'n', plural: 'meisjes', freq: 210, tags: ['people']);
  b.noun('de', 'vriend', ['friend'], gender: 'm', plural: 'vrienden', freq: 150, tags: ['people']);

  b.noun('het', 'brood', ['bread'], gender: 'n', freq: 400, tags: ['food']);
  b.noun('het', 'water', ['water'], gender: 'n', freq: 250, tags: ['food']);
  b.noun('de', 'koffie', ['coffee'], gender: 'm', freq: 350, tags: ['food']);
  b.noun('de', 'thee', ['tea'], gender: 'm', freq: 700, tags: ['food']);
  b.noun('de', 'appel', ['apple'], gender: 'm', plural: 'appels', freq: 800, tags: ['food']);
  b.noun('de', 'melk', ['milk'], gender: 'f', freq: 750, tags: ['food']);

  b.word('de', 'det', en: ['the'], freq: 1);
  b.word('het', 'det', en: ['the'], freq: 3);
  b.word('een', 'det', en: ['a', 'an'], freq: 4);
  b.word('ik', 'pron', en: ['I'], freq: 5);
  b.word('jij', 'pron', en: ['you'], freq: 20);
  b.word('hij', 'pron', en: ['he'], freq: 15);
  b.word('zij', 'pron', en: ['she', 'they'], freq: 18);
  b.word('wij', 'pron', en: ['we'], freq: 25);
  b.word('jullie', 'pron', en: ['you (plural)'], freq: 60);
  b.word('en', 'conj', en: ['and'], freq: 2);
  b.word('dat', 'conj', en: ['that'], freq: 9);
  b.word('in', 'prep', en: ['in'], freq: 6);
  b.word('met', 'prep', en: ['with'], freq: 12);
  b.word('naar', 'prep', en: ['to'], freq: 22);

  b.vocabSkill('groeten', 0, 'Greetings', 'Groeten',
      ['hallo', 'hoi', 'dag.2', 'goedemorgen', 'tot_ziens', 'dank_je', 'alsjeblieft', 'sorry']);
  b.vocabSkill('mensen', 1, 'People', 'Mensen', ['man', 'vrouw', 'kind', 'jongen', 'meisje', 'vriend'],
      requires: ['groeten']);
  b.vocabSkill('eten-drinken', 2, 'Food and drink', 'Eten en drinken', ['brood', 'water', 'koffie', 'thee', 'appel', 'melk'],
      requires: ['groeten']);

  // ------------------------------------------------------------ unit 2
  b.unit('u2', 1, 'Verbs', 'Werkwoorden');
  b.verb('werken', ['to work'], cls: 'weak', aux: 'hebben', freq: 110, tags: ['work'],
      tables: {_tt: _reg('werk', 'werk'), _pf: _hebben('gewerkt')});
  b.verb('wonen', ['to live', 'to reside'], cls: 'weak', aux: 'hebben', freq: 230,
      tables: {_tt: _reg('woon', 'won'), _pf: _hebben('gewoond')});
  b.verb('maken', ['to make', 'to do'], cls: 'weak', aux: 'hebben', freq: 70,
      tables: {_tt: _reg('maak', 'mak'), _pf: _hebben('gemaakt')});
  b.verb('spelen', ['to play'], cls: 'weak', aux: 'hebben', freq: 260,
      tables: {_tt: _reg('speel', 'spel'), _pf: _hebben('gespeeld')});
  b.verb('leren', ['to learn', 'to teach'], cls: 'weak', aux: 'hebben', freq: 280,
      tables: {_tt: _reg('leer', 'ler'), _pf: _hebben('geleerd')});
  b.verb('praten', ['to talk', 'to chat'], cls: 'weak', aux: 'hebben', freq: 290, tags: ['communication'],
      tables: {_tt: _reg('praat', 'prat', tStem: true), _pf: _hebben('gepraat')});
  b.verb('spreken', ['to speak', 'to talk'], cls: 'strong', aux: 'hebben', freq: 210, tags: ['communication'],
      tables: {_tt: _reg('spreek', 'sprek'), _pf: _hebben('gesproken')});
  b.verb('eten', ['to eat'], cls: 'strong', aux: 'hebben', freq: 180, tags: ['food'],
      tables: {_tt: _reg('eet', 'et', tStem: true), _pf: _hebben('gegeten')});
  b.verb('drinken', ['to drink'], cls: 'strong', aux: 'hebben', freq: 240, tags: ['food'],
      tables: {_tt: _reg('drink', 'drink'), _pf: _hebben('gedronken')});
  b.verb('lezen', ['to read'], cls: 'strong', aux: 'hebben', freq: 190, tags: ['communication'],
      tables: {_tt: _reg('lees', 'lez'), _pf: _hebben('gelezen')});
  b.verb('schrijven', ['to write'], cls: 'strong', aux: 'hebben', freq: 220, tags: ['communication'],
      tables: {_tt: _reg('schrijf', 'schrijv'), _pf: _hebben('geschreven')});
  b.verb('kopen', ['to buy'], cls: 'strong', aux: 'hebben', freq: 310,
      tables: {_tt: _reg('koop', 'kop'), _pf: _hebben('gekocht')});
  b.verb('komen', ['to come'], cls: 'strong', aux: 'zijn', freq: 40,
      tables: {_tt: _reg('kom', 'kom'), _pf: _zijn('gekomen')});
  b.verb('gaan', ['to go'], aux: 'zijn', irregular: true, freq: 30,
      tables: {_tt: ['ga', 'gaat', 'gaat', 'gaan', 'gaan', 'gaan'], _pf: _zijn('gegaan')});
  b.verb('zijn', ['to be'], aux: 'zijn', irregular: true, freq: 7,
      tables: {_tt: ['ben', 'bent', 'is', 'zijn', 'zijn', 'zijn'], _pf: _zijn('geweest')});
  b.verb('hebben', ['to have'], aux: 'hebben', irregular: true, freq: 8,
      tables: {_tt: ['heb', 'hebt', 'heeft', 'hebben', 'hebben', 'hebben'], _pf: _hebben('gehad')});
  b.verb('zwemmen', ['to swim'], cls: 'strong', aux: 'hebben|zijn', freq: 900,
      tables: {_tt: _reg('zwem', 'zwemm'), _pf: _hebben('gezwommen', both: true)});
  b.verb('lopen', ['to walk'], cls: 'strong', aux: 'hebben|zijn', freq: 330,
      tables: {_tt: _reg('loop', 'lop'), _pf: _hebben('gelopen', both: true)});

  b.vocabSkill('werkwoorden', 0, 'Verbs', 'Werkwoorden',
      ['werken', 'wonen', 'maken', 'eten', 'drinken', 'lezen', 'schrijven', 'gaan', 'komen', 'zijn', 'hebben', 'praten',
       'spreken'],
      requires: ['groeten']);
  b.verbSkill('tt-regelmatig', 1, 'Present tense', 'Tegenwoordige tijd', _tt,
      ['werken', 'wonen', 'maken', 'spelen', 'leren', 'praten', 'spreken', 'lezen', 'schrijven', 'drinken', 'kopen'],
      requires: ['groeten']);
  b.verbSkill('tt-onregelmatig', 2, 'Present: irregular', 'Tegenwoordige tijd: onregelmatig', _tt,
      ['zijn', 'hebben', 'gaan', 'komen', 'eten'],
      requires: ['tt-regelmatig'], exercises: ['conj_pick', 'conj_grid', 'cloze', 'spot_error', 'transform']);

  // ------------------------------------------------------------ unit 3
  b.unit('u3', 2, 'Past and things', 'Verleden en dingen');
  b.noun('het', 'huis', ['house', 'home'], gender: 'n', plural: 'huizen', freq: 130, tags: ['places']);
  b.noun('de', 'stad', ['city', 'town'], gender: 'f', plural: 'steden', freq: 170, tags: ['places']);
  b.noun('het', 'boek', ['book'], gender: 'n', plural: 'boeken', freq: 230, tags: ['things']);
  b.noun('de', 'krant', ['newspaper'], gender: 'f', plural: 'kranten', freq: 520, tags: ['things']);
  b.noun('de', 'school', ['school'], gender: 'f', plural: 'scholen', freq: 260, tags: ['places']);
  b.noun('de', 'kat', ['cat'], gender: 'f', plural: 'katten', freq: 820, tags: ['animals']);
  b.noun('de', 'hond', ['dog'], gender: 'm', plural: 'honden', freq: 610, tags: ['animals']);
  b.noun('de', 'fiets', ['bike', 'bicycle'], gender: 'm', plural: 'fietsen', freq: 640, tags: ['things']);
  b.noun('het', 'cadeau', ['present', 'gift'], gender: 'n', plural: 'cadeaus', freq: 980, tags: ['things'],
      variants: ['kado']);
  b.noun('de', 'brief', ['letter'], gender: 'm', plural: 'brieven', freq: 590, tags: ['things']);
  b.noun('de', 'auto', ['car'], gender: 'm', plural: "auto's", freq: 280, tags: ['things']);
  b.noun('de', 'dag', ['day'], gender: 'm', plural: 'dagen', freq: 60, tags: ['time']);
  b.noun('het', 'werk', ['work', 'job'], gender: 'n', freq: 140, tags: ['work']);
  b.word('thuis', 'adv', en: ['at home', 'home'], freq: 330);
  b.word('groot', 'adj', en: ['big', 'large'], freq: 95);
  b.word('klein', 'adj', en: ['small', 'little'], freq: 160);
  b.word('mooi', 'adj', en: ['beautiful', 'pretty'], freq: 190);
  b.word('goed', 'adj', en: ['good', 'well'], freq: 50);
  b.word('moe', 'adj', en: ['tired'], freq: 900);
  b.word('blij', 'adj', en: ['happy', 'glad'], freq: 700);
  b.word('koud', 'adj', en: ['cold'], freq: 760);
  b.word('vandaag', 'adv', en: ['today'], freq: 140);
  b.word('gisteren', 'adv', en: ['yesterday'], freq: 360);
  b.word('altijd', 'adv', en: ['always'], freq: 80);
  b.word('vaak', 'adv', en: ['often'], freq: 210);
  b.word('veel', 'adv', en: ['a lot', 'much', 'many'], freq: 45);
  b.word('hier', 'adv', en: ['here'], freq: 55);

  b.verbSkill('perfectum', 0, 'Present perfect', 'Voltooid tegenwoordige tijd', _pf,
      ['werken', 'maken', 'spelen', 'eten', 'drinken', 'lezen', 'schrijven', 'komen', 'gaan', 'zijn', 'hebben', 'zwemmen',
       'lopen', 'kopen'],
      requires: ['tt-regelmatig', 'tt-onregelmatig']);
  b.articleSkill('de-het', 1, 'De or het', 'De of het',
      ['man', 'vrouw', 'kind', 'jongen', 'meisje', 'huis', 'stad', 'brood', 'water', 'koffie', 'boek', 'krant', 'school',
       'kat', 'hond', 'fiets', 'cadeau', 'werk'],
      requires: ['mensen']);
  b.vocabSkill('dingen', 2, 'Things', 'Dingen',
      ['huis', 'stad', 'boek', 'krant', 'school', 'kat', 'hond', 'fiets', 'cadeau', 'auto', 'dag', 'werk'],
      requires: ['mensen']);
  b.vocabSkill('bijwoorden', 3, 'Adjectives and adverbs', 'Bijvoeglijke naamwoorden en bijwoorden',
      ['groot', 'klein', 'mooi', 'goed', 'moe', 'blij', 'vandaag', 'gisteren', 'altijd', 'vaak', 'hier'],
      requires: ['mensen']);

  // ------------------------------------------------------------ sentences
  const t = _tt;
  const pf = _pf;
  b.sentence('s:nl1', 'Ik werk vandaag.', en: 'I am working today.',
      align: ['Ik=ik', 'werk=werken@$t.ik', 'vandaag=vandaag']);
  b.sentence('s:nl2', 'Werk jij morgen?', en: 'Are you working tomorrow?',
      align: ['Werk=werken@$t.jij', 'jij=jij']);
  b.sentence('s:nl3', 'Zij werkt thuis.', en: 'She works at home.',
      align: ['Zij=zij', 'werkt=werken@$t.hij/zij', 'thuis=thuis']);
  b.sentence('s:nl4', 'Zij werken in de stad.', en: 'They work in the city.',
      align: ['Zij=zij', 'werken=werken@$t.zij', 'in=in', 'de=de', 'stad=stad']);
  b.sentence('s:nl5', 'Wij hebben gewerkt.', en: 'We have worked.',
      align: ['Wij=wij', 'hebben=werken@$pf.wij', 'gewerkt=werken@$pf.wij']);
  b.sentence('s:nl6', 'Ik heb brood gegeten.', en: 'I have eaten bread.',
      align: ['Ik=ik', 'heb=eten@$pf.ik', 'brood=brood', 'gegeten=eten@$pf.ik']);
  b.sentence('s:nl7', 'Hij eet een appel.', en: 'He is eating an apple.',
      align: ['Hij=hij', 'eet=eten@$t.hij/zij', 'een=een', 'appel=appel']);
  b.sentence('s:nl8', 'Het kind drinkt water.', en: 'The child drinks water.',
      align: ['Het=het', 'kind=kind', 'drinkt=drinken@$t.hij/zij', 'water=water']);
  b.sentence('s:nl9', 'De man leest de krant.', en: 'The man reads the newspaper.',
      align: ['De=de', 'man=man', 'leest=lezen@$t.hij/zij', 'de=de', 'krant=krant']);
  b.sentence('s:nl10', 'Gisteren heb ik een boek gelezen.', en: 'Yesterday I read a book.',
      align: ['Gisteren=gisteren', 'heb=lezen@$pf.ik', 'ik=ik', 'een=een', 'boek=boek', 'gelezen=lezen@$pf.ik']);
  b.sentence('s:nl11', 'Heb jij gegeten?', en: 'Have you eaten?',
      align: ['Heb=eten@$pf.jij', 'jij=jij', 'gegeten=eten@$pf.jij']);
  b.sentence('s:nl12', 'Ik weet dat hij brood gegeten heeft.', en: 'I know that he has eaten bread.',
      align: ['Ik=ik', 'dat=dat', 'hij=hij', 'brood=brood', 'gegeten=eten@$pf.hij/zij', 'heeft=eten@$pf.hij/zij']);
  b.sentence('s:nl13', 'Wij wonen in een groot huis.', en: 'We live in a big house.',
      align: ['Wij=wij', 'wonen=wonen@$t.wij', 'in=in', 'een=een', 'groot=groot', 'huis=huis']);
  b.sentence('s:nl14', 'Jullie spelen buiten.', en: 'You play outside.',
      align: ['Jullie=jullie', 'spelen=spelen@$t.jullie']);
  b.sentence('s:nl15', 'Ik ben naar school gegaan.', en: 'I went to school.',
      align: ['Ik=ik', 'ben=gaan@$pf.ik', 'naar=naar', 'school=school', 'gegaan=gaan@$pf.ik']);
  b.sentence('s:nl16', 'Zij is gisteren gekomen.', en: 'She came yesterday.',
      align: ['Zij=zij', 'is=komen@$pf.hij/zij', 'gisteren=gisteren', 'gekomen=komen@$pf.hij/zij']);
  b.sentence('s:nl17', 'Wij gaan naar huis.', en: 'We are going home.',
      align: ['Wij=wij', 'gaan=gaan@$t.wij', 'naar=naar', 'huis=huis']);
  b.sentence('s:nl18', 'Ik ben moe.', en: 'I am tired.', align: ['Ik=ik', 'ben=zijn@$t.ik', 'moe=moe']);
  b.sentence('s:nl19', 'Jij bent mijn vriend.', en: 'You are my friend.',
      align: ['Jij=jij', 'bent=zijn@$t.jij', 'vriend=vriend']);
  b.sentence('s:nl20', 'Zij hebben een hond.', en: 'They have a dog.',
      align: ['Zij=zij', 'hebben=hebben@$t.zij', 'een=een', 'hond=hond']);
  b.sentence('s:nl21', 'Hij heeft een kat gehad.', en: 'He has had a cat.',
      align: ['Hij=hij', 'heeft=hebben@$pf.hij/zij', 'een=een', 'kat=kat', 'gehad=hebben@$pf.hij/zij']);
  b.sentence('s:nl22', 'Wij zijn in de stad geweest.', en: 'We have been in the city.',
      align: ['Wij=wij', 'zijn=zijn@$pf.wij', 'in=in', 'de=de', 'stad=stad', 'geweest=zijn@$pf.wij']);
  b.sentence('s:nl23', 'Het meisje maakt een cadeau.', en: 'The girl is making a present.',
      align: ['Het=het', 'meisje=meisje', 'maakt=maken@$t.hij/zij', 'een=een', 'cadeau=cadeau']);
  b.sentence('s:nl24', 'Ik heb een brief geschreven.', en: 'I have written a letter.',
      align: ['Ik=ik', 'heb=schrijven@$pf.ik', 'een=een', 'brief=brief', 'geschreven=schrijven@$pf.ik']);
  b.sentence('s:nl25', 'Schrijf jij een brief?', en: 'Are you writing a letter?',
      align: ['Schrijf=schrijven@$t.jij', 'jij=jij', 'een=een', 'brief=brief']);
  b.sentence('s:nl26', 'Hij schrijft een brief.', en: 'He writes a letter.',
      align: ['Hij=hij', 'schrijft=schrijven@$t.hij/zij', 'een=een', 'brief=brief']);
  b.sentence('s:nl27', 'Wij praten met de jongen.', en: 'We talk with the boy.',
      align: ['Wij=wij', 'praten=praten@$t.wij', 'met=met', 'de=de', 'jongen=jongen']);
  b.sentence('s:nl28', 'Jij praat te veel.', en: 'You talk too much.',
      align: ['Jij=jij', 'praat=praten@$t.jij', 'veel=veel']);
  b.sentence('s:nl29', 'Ik spreek Nederlands.', en: 'I speak Dutch.', align: ['Ik=ik', 'spreek=spreken@$t.ik']);
  b.sentence('s:nl30', 'Zij leert Italiaans.', en: 'She is learning Italian.',
      align: ['Zij=zij', 'leert=leren@$t.hij/zij']);
  b.sentence('s:nl31', 'Ik heb gezwommen.', en: 'I have swum.',
      align: ['Ik=ik', 'heb=zwemmen@$pf.ik', 'gezwommen=zwemmen@$pf.ik']);
  b.sentence('s:nl32', 'Wij hebben in de stad gelopen.', en: 'We have walked in the city.',
      align: ['Wij=wij', 'hebben=lopen@$pf.wij', 'in=in', 'de=de', 'stad=stad', 'gelopen=lopen@$pf.wij']);
  b.sentence('s:nl33', 'Hij koopt een fiets.', en: 'He is buying a bike.',
      align: ['Hij=hij', 'koopt=kopen@$t.hij/zij', 'een=een', 'fiets=fiets']);
  b.sentence('s:nl34', 'Ik heb een auto gekocht.', en: 'I have bought a car.',
      align: ['Ik=ik', 'heb=kopen@$pf.ik', 'een=een', 'auto=auto', 'gekocht=kopen@$pf.ik']);
  b.sentence('s:nl35', 'De vrouw drinkt koffie.', en: 'The woman drinks coffee.',
      align: ['De=de', 'vrouw=vrouw', 'drinkt=drinken@$t.hij/zij', 'koffie=koffie']);
  b.sentence('s:nl36', 'Het huis is groot.', en: 'The house is big.',
      align: ['Het=het', 'huis=huis', 'is=zijn@$t.hij/zij', 'groot=groot']);
  b.sentence('s:nl37', 'Hallo, hoe gaat het?', en: 'Hello, how are you?',
      align: ['Hallo=hallo', 'gaat=gaan@$t.hij/zij']);
  b.sentence('s:nl38', 'Dank je, tot ziens!', en: 'Thank you, goodbye!',
      align: ['Dank=dank_je', 'je=dank_je', 'tot=tot_ziens', 'ziens=tot_ziens']);
  b.sentence('s:nl39', 'Goedemorgen, de koffie is klaar.', en: 'Good morning, the coffee is ready.',
      align: ['Goedemorgen=goedemorgen', 'de=de', 'koffie=koffie', 'is=zijn@$t.hij/zij']);
  b.sentence('s:nl40', 'Zij komen vandaag.', en: 'They are coming today.',
      align: ['Zij=zij', 'komen=komen@$t.zij', 'vandaag=vandaag']);
  b.sentence('s:nl41', 'Ik heb gisteren gewerkt.', en: 'I worked yesterday.',
      align: ['Ik=ik', 'heb=werken@$pf.ik', 'gisteren=gisteren', 'gewerkt=werken@$pf.ik']);
  b.sentence('s:nl42', 'Hij werkt altijd.', en: 'He always works.',
      align: ['Hij=hij', 'werkt=werken@$t.hij/zij', 'altijd=altijd']);
  b.sentence('s:nl43', 'De jongen speelt met de hond.', en: 'The boy plays with the dog.',
      align: ['De=de', 'jongen=jongen', 'speelt=spelen@$t.hij/zij', 'met=met', 'de=de', 'hond=hond']);
  b.sentence('s:nl44', 'Het water is koud.', en: 'The water is cold.',
      align: ['Het=het', 'water=water', 'is=zijn@$t.hij/zij', 'koud=koud']);
  b.sentence('s:nl45', 'Zij komen.', en: 'They are coming.', align: ['Zij=zij', 'komen=komen@$t.zij']);
  b.sentence('s:nl46', 'Ik lees.', en: 'I am reading.', align: ['Ik=ik', 'lees=lezen@$t.ik']);
  b.sentence('s:nl47', 'Hoi, ik ben het meisje van hiernaast.', en: "Hi, I'm the girl from next door.",
      align: ['Hoi=hoi', 'ik=ik', 'ben=zijn@$t.ik', 'het=het', 'meisje=meisje']);
  b.sentence('s:nl48', 'Dag, tot morgen!', en: 'Bye, see you tomorrow!', align: ['Dag=dag.2']);
  b.sentence('s:nl49', 'Het is een mooie dag.', en: 'It is a beautiful day.',
      align: ['is=zijn@$t.hij/zij', 'een=een', 'mooie=mooi', 'dag=dag']);
  b.sentence('s:nl50', 'Alsjeblieft, hier is de thee.', en: 'Here you go, here is the tea.',
      align: ['Alsjeblieft=alsjeblieft', 'hier=hier', 'is=zijn@$t.hij/zij', 'de=de', 'thee=thee']);
  b.sentence('s:nl51', 'Sorry, ik ben vaak moe.', en: 'Sorry, I am often tired.',
      align: ['Sorry=sorry', 'ik=ik', 'ben=zijn@$t.ik', 'vaak=vaak', 'moe=moe']);
  b.sentence('s:nl52', 'Het werk is klaar.', en: 'The work is done.',
      align: ['Het=het', 'werk=werk', 'is=zijn@$t.hij/zij']);
  b.sentence('s:nl53', 'Wij drinken melk en eten brood.', en: 'We drink milk and eat bread.',
      align: ['Wij=wij', 'drinken=drinken@$t.wij', 'melk=melk', 'en=en', 'eten=eten@$t.wij', 'brood=brood']);

  // ------------------------------------------------------------ notes
  b.note('tt-regelmatig',
      '## Present tense\n\n**ik** = stem, **jij/hij** = stem + **t**, plural = infinitive. In questions with *jij* after the verb, '
          'the -t drops: *werk jij?*',
      '## Tegenwoordige tijd\n\n**ik** = stam, **jij/hij** = stam + **t**, meervoud = infinitief. *Werk jij?* (zonder t).');
  b.note('tt-onregelmatig', '## Irregular verbs\n\n*zijn*: ben, bent, is, zijn. *hebben*: heb, hebt, heeft, hebben.',
      '## Onregelmatige werkwoorden\n\n*zijn*: ben, bent, is, zijn. *hebben*: heb, hebt, heeft, hebben.');
  b.note('perfectum',
      '## Present perfect\n\n**hebben/zijn** + past participle at the end of the clause: *Ik heb brood gegeten.*',
      '## Voltooid tegenwoordige tijd\n\n**hebben/zijn** + voltooid deelwoord achteraan: *Ik heb brood gegeten.*');
  b.note('de-het',
      '## De or het\n\nMost nouns take **de**; diminutives (*-je*) and many others take **het**.',
      '## De of het\n\nDe meeste woorden krijgen **de**; verkleinwoorden (*-je*) krijgen **het**.');
  return b.build();
}
