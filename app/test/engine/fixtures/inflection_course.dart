/// Small hand-built courses with inflection tables (`#infl` facets): Italian
/// noun number and adjective/possessive agreement, Dutch adjective -e and
/// diminutives. Token forms follow the pipeline convention
/// `infl:{table}.{cell}` (only where the agreement is determined).
library;

import 'package:tosk/core/core.dart';

import 'course_builder.dart';

const _number = InflectionTable(
  name: 'number',
  cells: ['sg', 'pl'],
  pos: ['noun'],
  base: 'sg',
  title: {'en': 'singular and plural', 'nl': 'enkelvoud en meervoud'},
  labels: {
    'sg': {'en': 'singular', 'nl': 'enkelvoud'},
    'pl': {'en': 'plural', 'nl': 'meervoud'},
  },
);

InMemoryCourseData italianInflectionCourse() {
  final b = CourseBuilder(const CourseMeta(
    id: 'it',
    version: '0.1.0',
    title: {'en': 'Italian'},
    target: 'it',
    translations: ['en'],
    persons: ['io', 'tu', 'lui/lei', 'noi', 'voi', 'loro'],
    tenses: ['presente'],
    articles: ['il', 'lo', 'la', "l'"],
    inflectionTables: {
      'number': _number,
      'agreement': InflectionTable(
        name: 'agreement',
        cells: ['m.sg', 'f.sg', 'm.pl', 'f.pl'],
        pos: ['adj', 'det'],
        base: 'm.sg',
        agreement: true,
        title: {'en': 'gender and number'},
        labels: {
          'm.sg': {'en': 'masculine singular'},
          'f.sg': {'en': 'feminine singular'},
          'm.pl': {'en': 'masculine plural'},
          'f.pl': {'en': 'feminine plural'},
        },
      ),
    },
  ));
  b.unit('u1', 0, 'Basics', 'Basis');
  b.noun('il', 'ragazzo', ['boy'], gender: 'm', plural: 'ragazzi', freq: 10, tags: ['people']);
  b.noun('la', 'ragazza', ['girl'], gender: 'f', plural: 'ragazze', freq: 11, tags: ['people']);
  b.noun('la', 'casa', ['house'], gender: 'f', plural: 'case', freq: 12, tags: ['things']);
  b.noun('il', 'libro', ['book'], gender: 'm', plural: 'libri', freq: 13, tags: ['things']);
  b.noun("l'", 'uomo', ['man'], gender: 'm', plural: 'uomini', freq: 14, tags: ['people']);
  b.noun("l'", 'amico', ['friend'], gender: 'm', plural: 'amici', freq: 15, tags: ['people']);
  b.noun('la', 'città', ['city'], gender: 'f', plural: 'città', freq: 16, tags: ['things']);
  b.word('piccolo', 'adj', en: ['small'], freq: 20, tags: ['adjectives']);
  b.word('bello', 'adj', en: ['beautiful'], freq: 21, tags: ['adjectives']);
  b.word('stanco', 'adj', en: ['tired'], freq: 22, tags: ['adjectives']);
  b.word('grande', 'adj', en: ['big'], freq: 23, tags: ['adjectives']);
  b.word('nuovo', 'adj', en: ['new'], freq: 24, tags: ['adjectives']);
  b.word('mio', 'det', en: ['my'], freq: 30, tags: ['possessives']);
  b.word('tuo', 'det', en: ['your'], freq: 31, tags: ['possessives']);
  b.word('il', 'det', en: ['the'], freq: 1);
  b.word('è', 'verb', en: ['is'], freq: 2);
  b.word('sono', 'verb', en: ['are'], freq: 3);

  b.inflection('ragazzo', 'number', {'sg': 'ragazz|o', 'pl': 'ragazz|i'}, wrong: {'pl': ['ragazzoi']});
  b.inflection('ragazza', 'number', {'sg': 'ragazz|a', 'pl': 'ragazz|e'}, wrong: {'pl': ['ragazzae']});
  b.inflection('casa', 'number', {'sg': 'cas|a', 'pl': 'cas|e'}, wrong: {'pl': ['casi', 'caso']});
  b.inflection('libro', 'number', {'sg': 'libr|o', 'pl': 'libr|i'}, wrong: {'pl': ['libre', 'libra']});
  b.inflection('uomo', 'number', {'sg': 'uom|o', 'pl': 'uom|ini'}, wrong: {'pl': ['uomi', 'uome']});
  b.inflection('amico', 'number', {'sg': 'amic|o', 'pl': 'amic|i'}, wrong: {'pl': ['amichi', 'amice']});
  b.inflection('città', 'number', {'sg': 'citt|à', 'pl': 'citt|à'}, wrong: {'pl': ['citte']});
  const agr = ['m.sg', 'f.sg', 'm.pl', 'f.pl'];
  void adj(String lemma, List<String> forms, List<String> wrong) => b.inflection(
      lemma, 'agreement', {for (var i = 0; i < 4; i++) agr[i]: forms[i]}, wrong: {for (final c in agr) c: wrong});
  adj('piccolo', ['piccol|o', 'piccol|a', 'piccol|i', 'piccol|e'], []);
  adj('bello', ['bell|o;bel', 'bell|a', 'bell|i;bei;begli', 'bell|e'], []);
  adj('stanco', ['stanc|o', 'stanc|a', 'stanc|hi', 'stanc|he'], ['stanci', 'stance']);
  adj('grande', ['grand|e', 'grand|e', 'grand|i', 'grand|i'], ['grando']);
  adj('nuovo', ['nuov|o', 'nuov|a', 'nuov|i', 'nuov|e'], []);
  adj('mio', ['mi|o', 'mi|a', 'mi|ei', 'mi|e'], ['mii']);
  adj('tuo', ['tu|o', 'tu|a', 'tu|oi', 'tu|e'], ['tui']);

  b.vocabSkill('parole', 0, 'Words', 'Woorden',
      ['ragazzo', 'ragazza', 'casa', 'libro', 'uomo', 'amico', 'città']);
  b.inflSkill('plurali', 1, 'Plurals', 'Meervoud', 'number', ['ragazzo', 'ragazza', 'casa', 'libro', 'uomo', 'amico'],
      requires: ['parole']);
  b.inflSkill('aggettivi', 2, 'Adjectives', 'Bijvoeglijke naamwoorden', 'agreement',
      ['piccolo', 'bello', 'stanco', 'grande', 'nuovo'],
      requires: ['parole'], withVocab: true);
  b.inflSkill('possessivi', 3, 'Possessives', 'Bezittelijke voornaamwoorden', 'agreement', ['mio', 'tuo'],
      requires: ['aggettivi']);

  const n = 'infl:number';
  const a = 'infl:agreement';
  void s(String sid, String text, String en, List<String> align) => b.sentence(sid, text, en: en, align: align);
  s('s:1', 'I ragazzi sono stanchi.', 'The boys are tired.',
      ['ragazzi=ragazzo@$n.pl', 'sono=sono', 'stanchi=stanco@$a.m.pl']);
  s('s:2', 'Le ragazze sono stanche.', 'The girls are tired.',
      ['ragazze=ragazza@$n.pl', 'sono=sono', 'stanche=stanco@$a.f.pl']);
  s('s:3', 'La casa è piccola.', 'The house is small.', ['casa=casa@$n.sg', 'è=è', 'piccola=piccolo@$a.f.sg']);
  s('s:4', 'Le case sono piccole.', 'The houses are small.',
      ['case=casa@$n.pl', 'sono=sono', 'piccole=piccolo@$a.f.pl']);
  s('s:5', 'Il libro è nuovo.', 'The book is new.', ['Il=il', 'libro=libro@$n.sg', 'è=è', 'nuovo=nuovo@$a.m.sg']);
  s('s:6', 'I libri sono nuovi.', 'The books are new.', ['libri=libro@$n.pl', 'sono=sono', 'nuovi=nuovo@$a.m.pl']);
  s('s:7', 'Gli uomini sono stanchi.', 'The men are tired.',
      ['uomini=uomo@$n.pl', 'sono=sono', 'stanchi=stanco@$a.m.pl']);
  s('s:8', 'Una casa grande.', 'A big house.', ['casa=casa@$n.sg', 'grande=grande@$a.f.sg']);
  s('s:9', 'Due case grandi.', 'Two big houses.', ['case=casa@$n.pl', 'grandi=grande@$a.f.pl']);
  s('s:10', 'Gli amici sono belli.', 'The friends are handsome.',
      ['amici=amico@$n.pl', 'sono=sono', 'belli=bello@$a.m.pl']);
  s('s:11', 'Il mio libro è bello.', 'My book is beautiful.',
      ['Il=il', 'mio=mio@$a.m.sg', 'libro=libro@$n.sg', 'è=è', 'bello=bello@$a.m.sg']);
  s('s:12', 'La mia casa è bella.', 'My house is beautiful.',
      ['mia=mio@$a.f.sg', 'casa=casa@$n.sg', 'è=è', 'bella=bello@$a.f.sg']);
  s('s:13', 'I miei amici sono grandi.', 'My friends are big.',
      ['miei=mio@$a.m.pl', 'amici=amico@$n.pl', 'sono=sono', 'grandi=grande@$a.m.pl']);
  s('s:14', 'Le tue case sono nuove.', 'Your houses are new.',
      ['tue=tuo@$a.f.pl', 'case=casa@$n.pl', 'sono=sono', 'nuove=nuovo@$a.f.pl']);
  s('s:15', 'Il tuo amico è piccolo.', 'Your friend is small.',
      ['Il=il', 'tuo=tuo@$a.m.sg', 'amico=amico@$n.sg', 'è=è', 'piccolo=piccolo@$a.m.sg']);
  s('s:16', 'Le mie ragazze sono belle.', 'My girls are beautiful.',
      ['mie=mio@$a.f.pl', 'ragazze=ragazza@$n.pl', 'sono=sono', 'belle=bello@$a.f.pl']);
  s('s:17', 'I tuoi libri sono piccoli.', 'Your books are small.',
      ['tuoi=tuo@$a.m.pl', 'libri=libro@$n.pl', 'sono=sono', 'piccoli=piccolo@$a.m.pl']);
  s('s:18', 'La tua ragazza è stanca.', 'Your girlfriend is tired.',
      ['tua=tuo@$a.f.sg', 'ragazza=ragazza@$n.sg', 'è=è', 'stanca=stanco@$a.f.sg']);
  // Invariable 'città' and a predicative adjective without a noun: no forms.
  s('s:19', 'Le città sono grandi.', 'The cities are big.', ['città=città', 'sono=sono', 'grandi=grande']);
  s('s:20', 'Sono stanco.', 'I am tired.', ['Sono=sono', 'stanco=stanco']);
  for (final sk in ['plurali', 'aggettivi', 'possessivi']) {
    b.note(sk, 'Note', 'Notitie');
  }
  return b.build();
}

InMemoryCourseData dutchInflectionCourse() {
  final b = CourseBuilder(const CourseMeta(
    id: 'nl',
    version: '0.1.0',
    title: {'en': 'Dutch'},
    target: 'nl',
    translations: ['en'],
    persons: ['ik', 'jij', 'hij/zij', 'wij', 'jullie', 'zij'],
    tenses: ['tegenwoordige_tijd'],
    articles: ['de', 'het'],
    inflectionTables: {
      'number': _number,
      'agreement': InflectionTable(
        name: 'agreement',
        cells: ['base', 'infl'],
        pos: ['adj'],
        base: 'base',
        agreement: true,
        title: {'en': 'adjective ending'},
        labels: {
          'base': {'en': 'without -e'},
          'infl': {'en': 'with -e'},
        },
      ),
      'diminutive': InflectionTable(
        name: 'diminutive',
        cells: ['sg', 'dim'],
        pos: ['noun'],
        base: 'sg',
        title: {'en': 'diminutive'},
        labels: {
          'sg': {'en': 'noun'},
          'dim': {'en': 'diminutive'},
        },
      ),
    },
  ));
  b.unit('u1', 0, 'Basics', 'Basis');
  b.noun('het', 'huis', ['house'], gender: 'n', plural: 'huizen', freq: 10);
  b.noun('de', 'kat', ['cat'], gender: 'f', plural: 'katten', freq: 11);
  b.noun('de', 'boom', ['tree'], gender: 'm', plural: 'bomen', freq: 12);
  b.noun('de', 'man', ['man'], gender: 'm', plural: 'mannen', freq: 13);
  b.noun('het', 'boek', ['book'], gender: 'n', plural: 'boeken', freq: 14);
  b.word('groot', 'adj', en: ['big'], freq: 20);
  b.word('wit', 'adj', en: ['white'], freq: 21);
  b.word('mooi', 'adj', en: ['beautiful'], freq: 22);
  b.word('oud', 'adj', en: ['old'], freq: 23);
  b.word('een', 'det', en: ['a'], freq: 1);
  b.word('het', 'det', en: ['the'], freq: 2);
  b.word('is', 'verb', en: ['is'], freq: 3);

  b.inflection('huis', 'number', {'sg': 'hui|s', 'pl': 'hui|zen'}, wrong: {'pl': ['huisen', 'huissen']});
  b.inflection('kat', 'number', {'sg': 'kat|', 'pl': 'kat|ten'}, wrong: {'pl': ['katen', 'kats']});
  b.inflection('boom', 'number', {'sg': 'bo|om', 'pl': 'bo|men'}, wrong: {'pl': ['boomen', 'booms']});
  b.inflection('man', 'number', {'sg': 'man|', 'pl': 'man|nen'}, wrong: {'pl': ['manen', 'mans']});
  b.inflection('boek', 'number', {'sg': 'boek|', 'pl': 'boek|en'}, wrong: {'pl': ['boekken', 'boeks']});
  b.inflection('huis', 'diminutive', {'sg': 'huis|', 'dim': 'huis|je'}, wrong: {'dim': ['huistje', 'huisetje']});
  b.inflection('kat', 'diminutive', {'sg': 'kat|', 'dim': 'kat|je'}, wrong: {'dim': ['kattetje', 'katetje']});
  b.inflection('boom', 'diminutive', {'sg': 'boom|', 'dim': 'boom|pje'}, wrong: {'dim': ['boomtje', 'boometje']});
  b.inflection('man', 'diminutive', {'sg': 'man|', 'dim': 'man|netje'}, wrong: {'dim': ['manetje', 'mantje']});
  b.inflection('boek', 'diminutive', {'sg': 'boek|', 'dim': 'boek|je'}, wrong: {'dim': ['boektje', 'boeketje']});
  b.inflection('groot', 'agreement', {'base': 'gro|ot', 'infl': 'gro|te'}, wrong: {'infl': ['groote']});
  b.inflection('wit', 'agreement', {'base': 'wit|', 'infl': 'wit|te'}, wrong: {'infl': ['wite']});
  b.inflection('mooi', 'agreement', {'base': 'mooi|', 'infl': 'mooi|e'}, wrong: {'infl': ['mooiee']});
  b.inflection('oud', 'agreement', {'base': 'oud|', 'infl': 'oud|e'}, wrong: {'infl': ['oudde']});

  b.vocabSkill('woorden', 0, 'Words', 'Woorden', ['huis', 'kat', 'boom', 'man', 'boek']);
  b.inflSkill('meervoud', 1, 'Plurals', 'Meervoud', 'number', ['huis', 'kat', 'boom', 'man', 'boek'],
      requires: ['woorden']);
  b.inflSkill('bijvoeglijk', 2, 'Adjectives', 'Bijvoeglijke naamwoorden', 'agreement', ['groot', 'wit', 'mooi', 'oud'],
      requires: ['woorden'], withVocab: true);
  b.inflSkill('verkleinwoorden', 3, 'Diminutives', 'Verkleinwoorden', 'diminutive',
      ['huis', 'kat', 'boom', 'man', 'boek'], requires: ['woorden']);

  const n = 'infl:number';
  const a = 'infl:agreement';
  const d = 'infl:diminutive';
  void s(String sid, String text, String en, List<String> align) => b.sentence(sid, text, en: en, align: align);
  s('s:1', 'Een groot huis.', 'A big house.', ['Een=een', 'groot=groot@$a.base', 'huis=huis@$n.sg']);
  s('s:2', 'Het grote huis.', 'The big house.', ['Het=het', 'grote=groot@$a.infl', 'huis=huis@$n.sg']);
  s('s:3', 'Twee grote huizen.', 'Two big houses.', ['grote=groot@$a.infl', 'huizen=huis@$n.pl']);
  s('s:4', 'Een witte kat.', 'A white cat.', ['Een=een', 'witte=wit@$a.infl', 'kat=kat@$n.sg']);
  s('s:5', 'De katten zijn wit.', 'The cats are white.', ['katten=kat@$n.pl', 'wit=wit@$a.base']);
  s('s:6', 'Een mooie boom.', 'A beautiful tree.', ['Een=een', 'mooie=mooi@$a.infl', 'boom=boom@$n.sg']);
  s('s:7', 'De bomen zijn mooi.', 'The trees are beautiful.', ['bomen=boom@$n.pl', 'mooi=mooi@$a.base']);
  s('s:8', 'Een oude man.', 'An old man.', ['Een=een', 'oude=oud@$a.infl', 'man=man@$n.sg']);
  s('s:9', 'De mannen zijn oud.', 'The men are old.', ['mannen=man@$n.pl', 'oud=oud@$a.base']);
  s('s:10', 'Een oud boek.', 'An old book.', ['Een=een', 'oud=oud@$a.base', 'boek=boek@$n.sg']);
  s('s:11', 'Ik lees boeken.', 'I read books.', ['boeken=boek@$n.pl']);
  s('s:12', 'Een klein huisje.', 'A little house.', ['Een=een', 'huisje=huis@$d.dim']);
  s('s:13', 'Het katje slaapt.', 'The kitten is sleeping.', ['Het=het', 'katje=kat@$d.dim']);
  s('s:14', 'Een boompje in de tuin.', 'A little tree in the garden.', ['Een=een', 'boompje=boom@$d.dim']);
  s('s:15', 'Een mannetje en een vrouwtje.', 'A male and a female.', ['Een=een', 'mannetje=man@$d.dim']);
  s('s:16', 'Een boekje lezen.', 'To read a booklet.', ['Een=een', 'boekje=boek@$d.dim']);
  s('s:17', 'Het huis is groot.', 'The house is big.', ['Het=het', 'huis=huis@$n.sg', 'is=is', 'groot=groot@$a.base']);
  for (final sk in ['meervoud', 'bijvoeglijk', 'verkleinwoorden']) {
    b.note(sk, 'Note', 'Notitie');
  }
  return b.build();
}
