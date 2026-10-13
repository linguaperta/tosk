/// A mini Italian course: 3 units, 10 skills, 20 verbs with full presente and
/// passato prossimo tables, nouns with il/lo/la/l', 50+ aligned sentences.
///
/// Tricky cases on purpose:
/// * homographs: essere `sono` (io and loro); `sono stato` (essere and stare);
///   `lavoro` (noun and lavorare io); `lo` (article and pronoun)
/// * overlapping glosses: ragazzo/bambino ("kid"), amico/amica ("friend"),
///   cominciare/iniziare ("to begin/to start"), ciao/salve ("hi/hello"),
///   essere/stare ("to be")
/// * elision: `l'acqua` split into two tokens, and `l’acqua` as one token
///   (typographic apostrophe)
/// * multi-word forms (`ho mangiato`), a split form (`non ho mai visto`),
///   gendered alternatives (`sono partito;sono partita`), a variant participle
///   (`ho visto;ho veduto`), a variant noun spelling (obiettivo/obbiettivo)
library;

import 'package:tosk/core/core.dart';

import 'course_builder.dart';

const _pres = 'presente';
const _pp = 'passato_prossimo';

/// Passato prossimo with avere.
List<String> _avere(String participle) =>
    ['ho', 'hai', 'ha', 'abbiamo', 'avete', 'hanno'].map((a) => '$a $participle').toList();

/// Passato prossimo with essere (masculine canonical, feminine alternative).
List<String> _essere(String stem) {
  const sg = ['sono', 'sei', 'è'];
  const pl = ['siamo', 'siete', 'sono'];
  return [
    for (final a in sg) '$a ${stem}o;$a ${stem}a',
    for (final a in pl) '$a ${stem}i;$a ${stem}e',
  ];
}

/// Regular presente from a stem and six endings.
List<String> _reg(String stem, List<String> endings) => [for (final e in endings) '$stem|$e'];

const _are = ['o', 'i', 'a', 'iamo', 'ate', 'ano'];
const _iare = ['io', 'i', 'ia', 'iamo', 'iate', 'iano'];
const _ere = ['o', 'i', 'e', 'iamo', 'ete', 'ono'];
const _ire = ['o', 'i', 'e', 'iamo', 'ite', 'ono'];

InMemoryCourseData italianCourse() {
  final b = CourseBuilder(const CourseMeta(
    id: 'it',
    version: '0.1.0',
    title: {'en': 'Italian', 'nl': 'Italiaans'},
    target: 'it',
    translations: ['en', 'nl'],
    persons: ['io', 'tu', 'lui/lei', 'noi', 'voi', 'loro'],
    tenses: [_pres, _pp],
    tenseLabels: {
      _pres: {'en': 'present', 'nl': 'tegenwoordige tijd'},
      _pp: {'en': 'present perfect', 'nl': 'voltooid tegenwoordige tijd'},
    },
    articles: ['il', 'lo', 'la', "l'", 'i', 'gli', 'le'],
    attribution: 'Hand-written test fixture.',
  ));

  // ------------------------------------------------------------ unit 1
  b.unit('u1', 0, 'Basics', 'Basis');
  b.word('ciao', 'intj', en: ['hi', 'hello', 'bye'], nl: ['hoi', 'dag'], freq: 40, tags: ['greetings']);
  b.word('salve', 'intj', en: ['hello', 'hi'], nl: ['hallo'], freq: 900, tags: ['greetings']);
  b.word('buongiorno', 'intj', en: ['good morning', 'good day'], nl: ['goedemorgen', 'goedendag'], freq: 500, tags: ['greetings']);
  b.word('buonasera', 'intj', en: ['good evening'], nl: ['goedenavond'], freq: 700, tags: ['greetings']);
  b.word('grazie', 'intj', en: ['thank you', 'thanks'], nl: ['dank je', 'bedankt'], freq: 60, tags: ['greetings']);
  b.word('prego', 'intj', en: ["you're welcome"], nl: ['graag gedaan'], freq: 400, tags: ['greetings']);
  b.word('arrivederci', 'intj', en: ['goodbye'], nl: ['tot ziens'], freq: 600, tags: ['greetings']);
  b.word('scusa', 'intj', en: ['sorry', 'excuse me'], nl: ['sorry', 'pardon'], freq: 300, tags: ['greetings']);

  b.noun('il', 'ragazzo', ['boy', 'kid'], nl: ['jongen'], gender: 'm', plural: 'ragazzi', freq: 150, tags: ['people']);
  b.noun('la', 'ragazza', ['girl'], nl: ['meisje'], gender: 'f', plural: 'ragazze', freq: 160, tags: ['people']);
  b.noun('il', 'bambino', ['child', 'kid'], nl: ['kind'], gender: 'm', plural: 'bambini', freq: 200, tags: ['people']);
  b.noun("l'", 'uomo', ['man'], nl: ['man'], gender: 'm', plural: 'uomini', freq: 90, tags: ['people']);
  b.noun('la', 'donna', ['woman'], nl: ['vrouw'], gender: 'f', plural: 'donne', freq: 110, tags: ['people']);
  b.noun("l'", 'amico', ['friend'], nl: ['vriend'], gender: 'm', plural: 'amici', freq: 130, tags: ['people']);
  b.noun("l'", 'amica', ['friend (female)'], nl: ['vriendin'], gender: 'f', plural: 'amiche', freq: 260, tags: ['people']);
  b.noun('lo', 'studente', ['student'], nl: ['student'], gender: 'm', plural: 'studenti', freq: 350, tags: ['people']);
  b.noun('lo', 'zio', ['uncle'], nl: ['oom'], gender: 'm', plural: 'zii', freq: 800, tags: ['people', 'family']);

  b.noun('il', 'pane', ['bread'], nl: ['brood'], gender: 'm', freq: 420, tags: ['food']);
  b.noun('la', 'pizza', ['pizza'], nl: ['pizza'], gender: 'f', plural: 'pizze', freq: 450, tags: ['food']);
  b.noun("l'", 'acqua', ['water'], nl: ['water'], gender: 'f', freq: 220, tags: ['food']);
  b.noun('il', 'caffè', ['coffee'], nl: ['koffie'], gender: 'm', plural: 'caffè', freq: 380, tags: ['food']);
  b.noun('il', 'vino', ['wine'], nl: ['wijn'], gender: 'm', plural: 'vini', freq: 520, tags: ['food']);
  b.noun('la', 'mela', ['apple'], nl: ['appel'], gender: 'f', plural: 'mele', freq: 950, tags: ['food']);
  b.noun('il', 'tè', ['tea'], nl: ['thee'], gender: 'm', freq: 990, tags: ['food']);

  b.word('il', 'det', en: ['the'], nl: ['de', 'het'], freq: 1);
  b.word('un', 'det', en: ['a', 'an'], nl: ['een'], freq: 5);
  b.word('io', 'pron', en: ['I'], nl: ['ik'], freq: 20);
  b.word('tu', 'pron', en: ['you'], nl: ['jij'], freq: 25);
  b.word('lui', 'pron', en: ['he'], nl: ['hij'], freq: 30);
  b.word('lei', 'pron', en: ['she'], nl: ['zij'], freq: 31);
  b.word('noi', 'pron', en: ['we'], nl: ['wij'], freq: 35);
  b.word('voi', 'pron', en: ['you (plural)'], nl: ['jullie'], freq: 45);
  b.word('loro', 'pron', en: ['they'], nl: ['zij'], freq: 50);
  b.word('lo', 'pron', itemId: 'lo.2', en: ['it', 'him'], nl: ['het', 'hem'], freq: 28);
  b.word('e', 'conj', en: ['and'], nl: ['en'], freq: 2);
  b.word('a', 'prep', en: ['to', 'at'], nl: ['naar', 'om'], freq: 3);
  b.word('in', 'prep', en: ['in'], nl: ['in'], freq: 6);
  b.word('con', 'prep', en: ['with'], nl: ['met'], freq: 15);
  b.word('non', 'adv', en: ['not'], nl: ['niet'], freq: 8);

  b.vocabSkill('saluti', 0, 'Greetings', 'Groeten',
      ['ciao', 'salve', 'buongiorno', 'buonasera', 'grazie', 'prego', 'arrivederci', 'scusa']);
  b.vocabSkill('persone', 1, 'People', 'Mensen',
      ['ragazzo', 'ragazza', 'bambino', 'uomo', 'donna', 'amico', 'amica', 'studente', 'zio'],
      requires: ['saluti']);
  b.vocabSkill('cibo', 2, 'Food', 'Eten', ['pane', 'pizza', 'acqua', 'caffè', 'vino', 'mela', 'tè'],
      requires: ['saluti']);

  // ------------------------------------------------------------ unit 2
  b.unit('u2', 1, 'Verbs', 'Werkwoorden');
  b.verb('parlare', ['to speak', 'to talk'], nl: ['spreken', 'praten'],
      cls: 'are', aux: 'avere', freq: 120, tags: ['communication'],
      tables: {_pres: _reg('parl', _are), _pp: _avere('parlato')});
  b.verb('mangiare', ['to eat'], nl: ['eten'],
      cls: 'are', aux: 'avere', freq: 300, tags: ['food'], tables: {_pres: _reg('mang', _iare), _pp: _avere('mangiato')});
  b.verb('cantare', ['to sing'], nl: ['zingen'],
      cls: 'are', aux: 'avere', freq: 900, tables: {_pres: _reg('cant', _are), _pp: _avere('cantato')});
  b.verb('lavorare', ['to work'], nl: ['werken'],
      cls: 'are', aux: 'avere', freq: 210, tags: ['work'], tables: {_pres: _reg('lavor', _are), _pp: _avere('lavorato')});
  b.verb('abitare', ['to live', 'to reside'], nl: ['wonen'],
      cls: 'are', aux: 'avere', freq: 640, tables: {_pres: _reg('abit', _are), _pp: _avere('abitato')});
  b.verb('cominciare', ['to begin', 'to start'], nl: ['beginnen'],
      cls: 'are', aux: 'avere', freq: 330, tables: {_pres: _reg('cominc', _iare), _pp: _avere('cominciato')});
  b.verb('iniziare', ['to start', 'to begin'], nl: ['beginnen', 'starten'],
      cls: 'are', aux: 'avere', freq: 340, tables: {_pres: _reg('iniz', _iare), _pp: _avere('iniziato')});
  b.verb('vedere', ['to see'], nl: ['zien'],
      cls: 'ere', aux: 'avere', freq: 70,
      tables: {_pres: _reg('ved', _ere), _pp: [for (final f in _avere('visto')) '$f;${f.replaceAll('visto', 'veduto')}']});
  b.verb('prendere', ['to take'], nl: ['nemen', 'pakken'],
      cls: 'ere', aux: 'avere', freq: 140, tables: {_pres: _reg('prend', _ere), _pp: _avere('preso')});
  b.verb('leggere', ['to read'], nl: ['lezen'],
      cls: 'ere', aux: 'avere', freq: 230, tags: ['communication'], tables: {_pres: _reg('legg', _ere), _pp: _avere('letto')});
  b.verb('scrivere', ['to write'], nl: ['schrijven'],
      cls: 'ere', aux: 'avere', freq: 250, tags: ['communication'],
      tables: {_pres: _reg('scriv', _ere), _pp: _avere('scritto')});
  b.verb('dormire', ['to sleep'], nl: ['slapen'],
      cls: 'ire', aux: 'avere', freq: 480, tables: {_pres: _reg('dorm', _ire), _pp: _avere('dormito')});
  b.verb('partire', ['to leave', 'to depart'], nl: ['vertrekken'],
      cls: 'ire', aux: 'essere', freq: 260, tables: {_pres: _reg('part', _ire), _pp: _essere('partit')});
  b.verb('sentire', ['to hear', 'to feel'], nl: ['horen', 'voelen'],
      cls: 'ire', aux: 'avere', freq: 180, tables: {_pres: _reg('sent', _ire), _pp: _avere('sentito')});
  b.verb('finire', ['to finish'], nl: ['eindigen', 'afmaken'],
      cls: 'isc', aux: 'avere', freq: 290,
      tables: {_pres: _reg('fin', ['isco', 'isci', 'isce', 'iamo', 'ite', 'iscono']), _pp: _avere('finito')});
  b.verb('essere', ['to be'], nl: ['zijn'],
      aux: 'essere', irregular: true, freq: 4,
      tables: {_pres: ['sono', 'sei', 'è', 'siamo', 'siete', 'sono'], _pp: _essere('stat')});
  b.verb('stare', ['to stay', 'to be'], nl: ['blijven', 'zijn'],
      aux: 'essere', irregular: true, freq: 60,
      tables: {_pres: ['sto', 'stai', 'sta', 'stiamo', 'state', 'stanno'], _pp: _essere('stat')});
  b.verb('avere', ['to have'], nl: ['hebben'],
      aux: 'avere', irregular: true, freq: 7,
      tables: {_pres: ['ho', 'hai', 'ha', 'abbiamo', 'avete', 'hanno'], _pp: _avere('avuto')});
  b.verb('andare', ['to go'], nl: ['gaan'],
      aux: 'essere', irregular: true, cls: 'are', freq: 35,
      tables: {_pres: ['vado', 'vai', 'va', 'and|iamo', 'and|ate', 'vanno'], _pp: _essere('andat')});
  b.verb('fare', ['to do', 'to make'], nl: ['doen', 'maken'],
      aux: 'avere', irregular: true, freq: 25,
      tables: {_pres: ['faccio', 'fai', 'fa', 'facciamo', 'fate', 'fanno'], _pp: _avere('fatto')});

  b.vocabSkill('verbi', 0, 'Verbs', 'Werkwoorden',
      ['parlare', 'mangiare', 'vedere', 'leggere', 'scrivere', 'dormire', 'essere', 'avere', 'andare', 'fare', 'lavorare'],
      requires: ['saluti']);
  b.verbSkill('presente-are', 1, 'Present: -are', 'Tegenwoordige tijd: -are', _pres,
      ['parlare', 'mangiare', 'cantare', 'lavorare', 'abitare', 'cominciare', 'iniziare'],
      requires: ['saluti']);
  b.verbSkill('presente-ere-ire', 2, 'Present: -ere/-ire', 'Tegenwoordige tijd: -ere/-ire', _pres,
      ['vedere', 'prendere', 'leggere', 'scrivere', 'dormire', 'partire', 'sentire', 'finire'],
      requires: ['presente-are']);
  b.verbSkill('essere-avere', 3, 'Essere and avere', 'Essere en avere', _pres,
      ['essere', 'avere', 'andare', 'fare', 'stare'],
      requires: ['presente-are'], exercises: ['conj_pick', 'conj_grid', 'cloze', 'spot_error']);

  // ------------------------------------------------------------ unit 3
  b.unit('u3', 2, 'Past and things', 'Verleden en dingen');
  b.noun('lo', 'zaino', ['backpack'], nl: ['rugzak'], gender: 'm', plural: 'zaini', freq: 1500, tags: ['things']);
  b.noun('il', 'libro', ['book'], nl: ['boek'], gender: 'm', plural: 'libri', freq: 240, tags: ['things']);
  b.noun('la', 'casa', ['house', 'home'], nl: ['huis', 'thuis'], gender: 'f', plural: 'case', freq: 80, tags: ['places']);
  b.noun('la', 'città', ['city', 'town'], nl: ['stad'], gender: 'f', plural: 'città', freq: 190, tags: ['places']);
  b.noun('la', 'scuola', ['school'], nl: ['school'], gender: 'f', plural: 'scuole', freq: 310, tags: ['places']);
  b.noun('la', 'lettera', ['letter'], nl: ['brief'], gender: 'f', plural: 'lettere', freq: 560, tags: ['things']);
  b.noun('il', 'giornale', ['newspaper'], nl: ['krant'], gender: 'm', plural: 'giornali', freq: 610, tags: ['things']);
  b.noun('il', 'gatto', ['cat'], nl: ['kat'], gender: 'm', plural: 'gatti', freq: 870, tags: ['animals']);
  b.noun('il', 'cane', ['dog'], nl: ['hond'], gender: 'm', plural: 'cani', freq: 720, tags: ['animals']);
  b.noun("l'", 'obiettivo', ['goal', 'aim'], nl: ['doel'], gender: 'm', plural: 'obiettivi', freq: 1100, tags: ['things'],
      variants: ['obbiettivo']);
  b.noun('il', 'lavoro', ['work', 'job'], nl: ['werk', 'baan'], gender: 'm', plural: 'lavori', freq: 100, tags: ['work']);
  b.word('grande', 'adj', en: ['big', 'large'], nl: ['groot'], freq: 95);
  b.word('piccolo', 'adj', en: ['small', 'little'], nl: ['klein'], freq: 170);
  b.word('bello', 'adj', en: ['beautiful', 'nice'], nl: ['mooi'], freq: 125);
  b.word('buono', 'adj', en: ['good'], nl: ['goed', 'lekker'], freq: 105);
  b.word('stanco', 'adj', en: ['tired'], nl: ['moe'], freq: 830);
  b.word('felice', 'adj', en: ['happy'], nl: ['blij', 'gelukkig'], freq: 540);
  b.word('oggi', 'adv', en: ['today'], nl: ['vandaag'], freq: 85);
  b.word('ieri', 'adv', en: ['yesterday'], nl: ['gisteren'], freq: 280);
  b.word('sempre', 'adv', en: ['always'], nl: ['altijd'], freq: 55);
  b.word('spesso', 'adv', en: ['often'], nl: ['vaak'], freq: 270);
  b.word('molto', 'adv', en: ['very', 'a lot'], nl: ['heel', 'veel'], freq: 38);
  b.word('già', 'adv', en: ['already'], nl: ['al'], freq: 75);
  b.word('mai', 'adv', en: ['never', 'ever'], nl: ['nooit', 'ooit'], freq: 65);

  b.verbSkill('passato-prossimo', 0, 'Present perfect', 'Voltooid tegenwoordige tijd', _pp,
      ['parlare', 'mangiare', 'lavorare', 'vedere', 'leggere', 'scrivere', 'partire', 'andare', 'essere', 'avere', 'fare',
       'dormire'],
      requires: ['presente-are', 'essere-avere']);
  b.articleSkill('articoli', 1, 'Articles', 'Lidwoorden',
      ['ragazzo', 'ragazza', 'studente', 'zaino', 'acqua', 'amico', 'uomo', 'libro', 'casa', 'città', 'scuola', 'zio',
       'caffè', 'obiettivo', 'giornale', 'lavoro'],
      requires: ['persone']);
  b.vocabSkill('cose', 2, 'Things', 'Dingen',
      ['zaino', 'libro', 'casa', 'città', 'scuola', 'lettera', 'giornale', 'gatto', 'cane', 'obiettivo', 'lavoro'],
      requires: ['persone']);
  b.vocabSkill('aggettivi', 3, 'Adjectives and adverbs', 'Bijvoeglijke naamwoorden en bijwoorden',
      ['grande', 'piccolo', 'bello', 'buono', 'stanco', 'felice', 'oggi', 'ieri', 'sempre', 'spesso', 'già'],
      requires: ['persone']);

  // ------------------------------------------------------------ sentences
  const p = _pres;
  const pp = _pp;
  b.sentence('s:it1', 'Io parlo italiano.', en: 'I speak Italian.', nl: 'Ik spreek Italiaans.',
      align: ['Io=io', 'parlo=parlare@$p.io']);
  b.sentence('s:it2', 'Parliamo con il ragazzo.', en: 'We talk with the boy.', nl: 'We praten met de jongen.',
      align: ['Parliamo=parlare@$p.noi', 'con=con', 'il=il', 'ragazzo=ragazzo']);
  b.sentence('s:it3', 'Mangiamo la pizza alle otto.', en: 'We eat pizza at eight.', nl: 'We eten om acht uur pizza.',
      align: ['Mangiamo=mangiare@$p.noi', 'la=il', 'pizza=pizza']);
  b.sentence('s:it4', 'Il ragazzo mangia una mela.', en: 'The boy eats an apple.', nl: 'De jongen eet een appel.',
      align: ['Il=il', 'ragazzo=ragazzo', 'mangia=mangiare@$p.lui/lei', 'una=un', 'mela=mela']);
  b.sentence('s:it5', "La ragazza beve l'acqua.", en: 'The girl drinks the water.', nl: 'Het meisje drinkt het water.',
      align: ['La=il', 'ragazza=ragazza', "l'=il", 'acqua=acqua']);
  b.sentence('s:it6', 'Ho mangiato il pane.', en: 'I have eaten the bread.', nl: 'Ik heb het brood gegeten.',
      align: ['Ho=mangiare@$pp.io', 'mangiato=mangiare@$pp.io', 'il=il', 'pane=pane']);
  b.sentence('s:it7', 'Abbiamo parlato con lo studente.', en: 'We talked with the student.',
      nl: 'We hebben met de student gepraat.',
      align: ['Abbiamo=parlare@$pp.noi', 'parlato=parlare@$pp.noi', 'con=con', 'lo=il', 'studente=studente']);
  b.sentence('s:it8', 'Lo zio legge il giornale.', en: 'The uncle reads the newspaper.', nl: 'De oom leest de krant.',
      align: ['Lo=il', 'zio=zio', 'legge=leggere@$p.lui/lei', 'il=il', 'giornale=giornale']);
  b.sentence('s:it9', 'Leggete un libro?', en: 'Are you reading a book?', nl: 'Lezen jullie een boek?',
      align: ['Leggete=leggere@$p.voi', 'un=un', 'libro=libro']);
  b.sentence('s:it10', 'Scrivo una lettera.', en: 'I am writing a letter.', nl: 'Ik schrijf een brief.',
      align: ['Scrivo=scrivere@$p.io', 'una=un', 'lettera=lettera']);
  b.sentence('s:it11', 'Ho scritto una lettera.', en: 'I have written a letter.', nl: 'Ik heb een brief geschreven.',
      align: ['Ho=scrivere@$pp.io', 'scritto=scrivere@$pp.io', 'una=un', 'lettera=lettera']);
  b.sentence('s:it12', 'Loro dormono molto.', en: 'They sleep a lot.', nl: 'Zij slapen veel.',
      align: ['Loro=loro', 'dormono=dormire@$p.loro', 'molto=molto']);
  b.sentence('s:it13', 'Dormite sempre a casa?', en: 'Do you always sleep at home?', nl: 'Slapen jullie altijd thuis?',
      align: ['Dormite=dormire@$p.voi', 'sempre=sempre', 'a=a', 'casa=casa']);
  b.sentence('s:it14', 'Partiamo oggi.', en: 'We leave today.', nl: 'We vertrekken vandaag.',
      align: ['Partiamo=partire@$p.noi', 'oggi=oggi']);
  b.sentence('s:it15', 'Sono partita ieri.', en: 'I left yesterday.', nl: 'Ik ben gisteren vertrokken.',
      align: ['Sono=partire@$pp.io', 'partita=partire@$pp.io', 'ieri=ieri']);
  b.sentence('s:it16', 'Sono stanco.', en: 'I am tired.', nl: 'Ik ben moe.',
      align: ['Sono=essere@$p.io', 'stanco=stanco']);
  b.sentence('s:it17', 'Siamo a casa.', en: 'We are at home.', nl: 'We zijn thuis.',
      align: ['Siamo=essere@$p.noi', 'a=a', 'casa=casa']);
  b.sentence('s:it18', 'Loro sono felici.', en: 'They are happy.', nl: 'Zij zijn blij.',
      align: ['Loro=loro', 'sono=essere@$p.loro', 'felici=felice']);
  b.sentence('s:it19', 'Ho un gatto e un cane.', en: 'I have a cat and a dog.', nl: 'Ik heb een kat en een hond.',
      align: ['Ho=avere@$p.io', 'un=un', 'gatto=gatto', 'e=e', 'un=un', 'cane=cane']);
  b.sentence('s:it20', 'Hanno una casa grande.', en: 'They have a big house.', nl: 'Ze hebben een groot huis.',
      align: ['Hanno=avere@$p.loro', 'una=un', 'casa=casa', 'grande=grande']);
  b.sentence('s:it21', 'Abbiamo avuto un cane.', en: 'We have had a dog.', nl: 'We hebben een hond gehad.',
      align: ['Abbiamo=avere@$pp.noi', 'avuto=avere@$pp.noi', 'un=un', 'cane=cane']);
  b.sentence('s:it22', 'Vado a scuola.', en: 'I go to school.', nl: 'Ik ga naar school.',
      align: ['Vado=andare@$p.io', 'a=a', 'scuola=scuola']);
  b.sentence('s:it23', 'Andiamo in città.', en: 'We are going to the city.', nl: 'We gaan naar de stad.',
      align: ['Andiamo=andare@$p.noi', 'in=in', 'città=città']);
  b.sentence('s:it24', 'Siamo andati in città.', en: 'We went to the city.', nl: 'We zijn naar de stad gegaan.',
      align: ['Siamo=andare@$pp.noi', 'andati=andare@$pp.noi', 'in=in', 'città=città']);
  b.sentence('s:it25', 'Che cosa fai oggi?', en: 'What are you doing today?', nl: 'Wat doe je vandaag?',
      align: ['fai=fare@$p.tu', 'oggi=oggi']);
  b.sentence('s:it26', 'Ho fatto una pizza.', en: 'I have made a pizza.', nl: 'Ik heb een pizza gemaakt.',
      align: ['Ho=fare@$pp.io', 'fatto=fare@$pp.io', 'una=un', 'pizza=pizza']);
  b.sentence('s:it27', 'Vedo il gatto.', en: 'I see the cat.', nl: 'Ik zie de kat.',
      align: ['Vedo=vedere@$p.io', 'il=il', 'gatto=gatto']);
  b.sentence('s:it28', 'Hai visto il cane?', en: 'Have you seen the dog?', nl: 'Heb je de hond gezien?',
      align: ['Hai=vedere@$pp.tu', 'visto=vedere@$pp.tu', 'il=il', 'cane=cane']);
  // Split form: only the participle is aligned; "ho" is found nearby.
  b.sentence('s:it29', 'Non ho mai visto la città.', en: 'I have never seen the city.', nl: 'Ik heb de stad nooit gezien.',
      align: ['Non=non', 'mai=mai', 'visto=vedere@$pp.io', 'la=il', 'città=città']);
  b.sentence('s:it30', 'Lavoro in città.', en: 'I work in the city.', nl: 'Ik werk in de stad.',
      align: ['Lavoro=lavorare@$p.io', 'in=in', 'città=città']);
  b.sentence('s:it31', 'Hanno lavorato molto.', en: 'They have worked a lot.', nl: 'Zij hebben veel gewerkt.',
      align: ['Hanno=lavorare@$pp.loro', 'lavorato=lavorare@$pp.loro', 'molto=molto']);
  b.sentence('s:it32', 'Abitiamo in una casa piccola.', en: 'We live in a small house.', nl: 'We wonen in een klein huis.',
      align: ['Abitiamo=abitare@$p.noi', 'in=in', 'una=un', 'casa=casa', 'piccola=piccolo']);
  b.sentence('s:it33', 'Cantate bene!', en: 'You sing well!', nl: 'Jullie zingen goed!',
      align: ['Cantate=cantare@$p.voi']);
  b.sentence('s:it34', 'Il bambino dorme.', en: 'The child is sleeping.', nl: 'Het kind slaapt.',
      align: ['Il=il', 'bambino=bambino', 'dorme=dormire@$p.lui/lei']);
  b.sentence('s:it35', 'Ho dormito bene.', en: 'I slept well.', nl: 'Ik heb goed geslapen.',
      align: ['Ho=dormire@$pp.io', 'dormito=dormire@$pp.io']);
  b.sentence('s:it36', 'Prendo un caffè.', en: "I'll have a coffee.", nl: 'Ik neem een koffie.',
      align: ['Prendo=prendere@$p.io', 'un=un', 'caffè=caffè']);
  b.sentence('s:it37', 'Sento la musica.', en: 'I hear the music.', nl: 'Ik hoor de muziek.',
      align: ['Sento=sentire@$p.io', 'la=il']);
  b.sentence('s:it38', 'Finisco il lavoro alle cinque.', en: 'I finish work at five.', nl: 'Ik ben om vijf uur klaar met werken.',
      align: ['Finisco=finire@$p.io', 'il=il', 'lavoro=lavoro']);
  b.sentence('s:it39', 'Cominciamo oggi.', en: 'We start today.', nl: 'We beginnen vandaag.',
      align: ['Cominciamo=cominciare@$p.noi', 'oggi=oggi']);
  b.sentence('s:it40', 'Iniziano a lavorare.', en: 'They begin to work.', nl: 'Ze beginnen te werken.',
      align: ['Iniziano=iniziare@$p.loro', 'a=a', 'lavorare=lavorare']);
  b.sentence('s:it41', 'La donna è italiana.', en: 'The woman is Italian.', nl: 'De vrouw is Italiaans.',
      align: ['La=il', 'donna=donna', 'è=essere@$p.lui/lei']);
  b.sentence('s:it42', "L'uomo ha un libro.", en: 'The man has a book.', nl: 'De man heeft een boek.',
      align: ["L'=il", 'uomo=uomo', 'ha=avere@$p.lui/lei', 'un=un', 'libro=libro']);
  // One token with a typographic apostrophe.
  b.sentence('s:it43', 'Bevo l’acqua.', en: 'I drink the water.', nl: 'Ik drink het water.',
      align: ['l’acqua=acqua'], splitElision: false);
  b.sentence('s:it44', 'Ciao, come stai?', en: 'Hi, how are you?', nl: 'Hoi, hoe gaat het?',
      align: ['Ciao=ciao', 'stai=stare@$p.tu']);
  b.sentence('s:it45', 'Grazie, sto bene.', en: "Thanks, I'm fine.", nl: 'Bedankt, het gaat goed.',
      align: ['Grazie=grazie', 'sto=stare@$p.io']);
  b.sentence('s:it46', 'Buongiorno, signora!', en: 'Good morning, madam!', nl: 'Goedemorgen, mevrouw!',
      align: ['Buongiorno=buongiorno']);
  b.sentence('s:it47', 'Arrivederci e grazie!', en: 'Goodbye and thank you!', nl: 'Tot ziens en bedankt!',
      align: ['Arrivederci=arrivederci', 'e=e', 'grazie=grazie']);
  b.sentence('s:it48', 'Sei stato a Roma?', en: 'Have you been to Rome?', nl: 'Ben je in Rome geweest?',
      align: ['Sei=essere@$pp.tu', 'stato=essere@$pp.tu', 'a=a']);
  b.sentence('s:it49', 'Il caffè è buono.', en: 'The coffee is good.', nl: 'De koffie is lekker.',
      align: ['Il=il', 'caffè=caffè', 'è=essere@$p.lui/lei', 'buono=buono']);
  b.sentence('s:it50', 'Gli studenti leggono il libro.', en: 'The students read the book.', nl: 'De studenten lezen het boek.',
      align: ['Gli=il', 'studenti=studente', 'leggono=leggere@$p.loro', 'il=il', 'libro=libro']);
  b.sentence('s:it51', 'Ho letto il giornale.', en: 'I have read the newspaper.', nl: 'Ik heb de krant gelezen.',
      align: ['Ho=leggere@$pp.io', 'letto=leggere@$pp.io', 'il=il', 'giornale=giornale']);
  b.sentence('s:it52', 'Parlano sempre.', en: 'They always talk.', nl: 'Ze praten altijd.',
      align: ['Parlano=parlare@$p.loro', 'sempre=sempre']);
  b.sentence('s:it53', 'Mangiate già?', en: 'Are you eating already?', nl: 'Eten jullie al?',
      align: ['Mangiate=mangiare@$p.voi', 'già=già']);
  b.sentence('s:it54', 'Salve, ragazzi!', en: 'Hello, guys!', nl: 'Hallo, jongens!',
      align: ['Salve=salve', 'ragazzi=ragazzo']);
  b.sentence('s:it55', 'Prego, signore.', en: "You're welcome, sir.", nl: 'Graag gedaan, meneer.',
      align: ['Prego=prego']);
  b.sentence('s:it56', 'Scusa, sono in ritardo.', en: "Sorry, I'm late.", nl: 'Sorry, ik ben te laat.',
      align: ['Scusa=scusa', 'sono=essere@$p.io', 'in=in']);
  b.sentence('s:it57', 'Buonasera, come sta?', en: 'Good evening, how are you?', nl: 'Goedenavond, hoe gaat het met u?',
      align: ['Buonasera=buonasera', 'sta=stare@$p.lui/lei']);
  b.sentence('s:it58', 'Il vino è buono e il tè è grande.', en: 'The wine is good and the tea is big.',
      nl: 'De wijn is lekker en de thee is groot.',
      align: ['Il=il', 'vino=vino', 'è=essere@$p.lui/lei', 'buono=buono', 'e=e', 'il=il', 'tè=tè',
              'è=essere@$p.lui/lei', 'grande=grande']);
  b.sentence('s:it59', "L'amico di Marco è uno studente.", en: "Marco's friend is a student.", nl: 'De vriend van Marco is student.',
      align: ["L'=il", 'amico=amico', 'è=essere@$p.lui/lei', 'uno=un', 'studente=studente']);
  b.sentence('s:it60', "L'amica di Anna lavora spesso.", en: "Anna's friend often works.", nl: 'De vriendin van Anna werkt vaak.',
      align: ["L'=il", 'amica=amica', 'lavora=lavorare@$p.lui/lei', 'spesso=spesso']);
  b.sentence('s:it61', 'Lo zaino è piccolo.', en: 'The backpack is small.', nl: 'De rugzak is klein.',
      align: ['Lo=il', 'zaino=zaino', 'è=essere@$p.lui/lei', 'piccolo=piccolo']);
  b.sentence('s:it62', "L'obiettivo è bello.", en: 'The goal is beautiful.', nl: 'Het doel is mooi.',
      align: ["L'=il", 'obiettivo=obiettivo', 'è=essere@$p.lui/lei', 'bello=bello']);
  b.sentence('s:it63', 'La città è grande.', en: 'The city is big.', nl: 'De stad is groot.',
      align: ['La=il', 'città=città', 'è=essere@$p.lui/lei', 'grande=grande']);
  b.sentence('s:it64', 'La scuola è piccola.', en: 'The school is small.', nl: 'De school is klein.',
      align: ['La=il', 'scuola=scuola', 'è=essere@$p.lui/lei', 'piccola=piccolo']);

  // ------------------------------------------------------------ notes
  b.note('presente-are',
      '## Present tense of -are verbs\n\nDrop **-are** and add **-o, -i, -a, -iamo, -ate, -ano**: '
          '*parlo, parli, parla, parliamo, parlate, parlano*.',
      '## Tegenwoordige tijd van -are-werkwoorden\n\nHaal **-are** weg en voeg **-o, -i, -a, -iamo, -ate, -ano** toe.');
  b.note('presente-ere-ire',
      '## Present tense of -ere and -ire verbs\n\n-ere: *-o, -i, -e, -iamo, -ete, -ono*; -ire: *-o, -i, -e, -iamo, -ite, -ono*. '
          'Some -ire verbs insert **-isc-** (*finisco*).',
      '## Tegenwoordige tijd van -ere en -ire\n\n-ere: *-o, -i, -e, -iamo, -ete, -ono*; -ire: *-o, -i, -e, -iamo, -ite, -ono*.');
  b.note('essere-avere',
      '## Essere and avere\n\n*sono, sei, è, siamo, siete, sono* — note that **sono** is both "I am" and "they are".',
      '## Essere en avere\n\n*sono, sei, è, siamo, siete, sono* — **sono** is zowel "ik ben" als "zij zijn".');
  b.note('passato-prossimo',
      '## Present perfect\n\n**avere/essere + participle**. With essere the participle agrees: *sono partito/partita*.',
      '## Voltooid tegenwoordige tijd\n\n**avere/essere + voltooid deelwoord**. Bij essere past het deelwoord zich aan.');
  b.note('articoli',
      '## Definite articles\n\n**il** (m), **lo** (m before s+consonant, z), **la** (f), **l\'** (before a vowel).',
      '## Bepaalde lidwoorden\n\n**il** (m), **lo** (m voor s+medeklinker, z), **la** (v), **l\'** (voor een klinker).');
  return b.build();
}
