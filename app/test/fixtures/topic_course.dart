/// A small Italian course with two built-in topic trees (schema minor 3) for
/// the topic tests and renders: a main tree of 3 units and 9 skills, the
/// topic "Food and cooking" anchored mid-tree (at `food-basics`, unit 2) with
/// 2 units and 4 skills, and "Travel and holidays" anchored at the main
/// tree's last skill (`city-life`) with 1 unit and 3 skills. Topic skills
/// share some words with the main tree (`pane`, `vino`, `treno`), so "already
/// known" counts have something to count. The real it/nl/es content is not
/// split yet (docs/topic-split-proposal.md).
library;

import 'package:tosk/core/core.dart';
import 'package:tosk/ui/course_catalog.dart';

import '../engine/fixtures/course_builder.dart';

const topicCourseMeta = CourseMeta(
  id: 'it',
  version: '1.3.0',
  title: {'en': 'Italian', 'nl': 'Italiaans'},
  target: 'it',
  translations: ['en', 'nl'],
  persons: ['io', 'tu', 'lui/lei', 'noi', 'voi', 'loro'],
  tenses: ['presente'],
  schemaMinor: 3,
);

InMemoryCourseData topicCourse() {
  final b = CourseBuilder(topicCourseMeta);
  void words(List<(String, String, String)> ws) {
    for (final (it, en, nl) in ws) {
      b.word(it, 'noun', en: [en], nl: [nl]);
    }
  }

  // ---- main tree
  b.unit('u1', 0, 'Basics', 'Basis');
  words([('ciao', 'hi', 'hoi'), ('grazie', 'thanks', 'bedankt'), ('prego', "you're welcome", 'graag gedaan'),
    ('sì', 'yes', 'ja'), ('no', 'no', 'nee')]);
  b.vocabSkill('greetings', 0, 'Greetings', 'Begroetingen', ['ciao', 'grazie', 'prego', 'sì', 'no']);
  words([('uomo', 'man', 'man'), ('donna', 'woman', 'vrouw'), ('ragazzo', 'boy', 'jongen'), ('amico', 'friend', 'vriend')]);
  b.vocabSkill('people', 1, 'People', 'Mensen', ['uomo', 'donna', 'ragazzo', 'amico'], requires: ['greetings']);
  words([('uno', 'one', 'een'), ('due', 'two', 'twee'), ('tre', 'three', 'drie'), ('quattro', 'four', 'vier')]);
  b.vocabSkill('numbers', 2, 'Numbers', 'Getallen', ['uno', 'due', 'tre', 'quattro'], requires: ['greetings']);

  b.unit('u2', 1, 'Everyday life', 'Dagelijks leven');
  words([('pane', 'bread', 'brood'), ('vino', 'wine', 'wijn'), ('acqua', 'water', 'water'), ('latte', 'milk', 'melk')]);
  b.vocabSkill('food-basics', 0, 'Food basics', 'Eten: de basis', ['pane', 'vino', 'acqua', 'latte'], requires: ['people']);
  words([('casa', 'house', 'huis'), ('porta', 'door', 'deur'), ('letto', 'bed', 'bed'), ('tavolo', 'table', 'tafel')]);
  b.vocabSkill('home', 1, 'At home', 'Thuis', ['casa', 'porta', 'letto', 'tavolo'], requires: ['people', 'numbers']);
  words([('oggi', 'today', 'vandaag'), ('domani', 'tomorrow', 'morgen'), ('ora', 'hour', 'uur'), ('giorno', 'day', 'dag')]);
  b.vocabSkill('time', 2, 'Time', 'Tijd', ['oggi', 'domani', 'ora', 'giorno'], requires: ['numbers']);

  b.unit('u3', 2, 'Out and about', 'Op pad');
  words([('città', 'city', 'stad'), ('strada', 'street', 'straat'), ('treno', 'train', 'trein'), ('piazza', 'square', 'plein')]);
  b.vocabSkill('city', 0, 'The city', 'De stad', ['città', 'strada', 'treno', 'piazza'], requires: ['food-basics', 'home']);
  words([('lavoro', 'work', 'werk'), ('ufficio', 'office', 'kantoor'), ('capo', 'boss', 'baas')]);
  b.vocabSkill('work', 1, 'Work', 'Werk', ['lavoro', 'ufficio', 'capo'], requires: ['time']);
  words([('negozio', 'shop', 'winkel'), ('banca', 'bank', 'bank'), ('chiesa', 'church', 'kerk')]);
  b.vocabSkill('city-life', 2, 'City life', 'Stadsleven', ['negozio', 'banca', 'chiesa'], requires: ['city', 'work']);

  // ---- topic: Food and cooking (anchored mid-tree)
  b.topic('cucina', 0, 'Food and cooking', 'Eten en koken', anchor: 'food-basics', shortEn: 'Food', icon: 'food');
  b.unit('cucina-u1', 3, 'In the kitchen', 'In de keuken', topic: 'cucina');
  words([('pentola', 'pot', 'pan'), ('forno', 'oven', 'oven'), ('cuocere', 'to cook', 'koken'), ('sale', 'salt', 'zout')]);
  b.vocabSkill('cooking', 0, 'Cooking', 'Koken', ['pentola', 'forno', 'cuocere', 'sale', 'pane'], requires: ['food-basics']);
  words([('mercato', 'market', 'markt'), ('mela', 'apple', 'appel'), ('pomodoro', 'tomato', 'tomaat'), ('formaggio', 'cheese', 'kaas')]);
  b.vocabSkill('market', 1, 'At the market', 'Op de markt', ['mercato', 'mela', 'pomodoro', 'formaggio'], requires: ['food-basics']);
  b.unit('cucina-u2', 4, 'Eating out', 'Uit eten', topic: 'cucina');
  words([('cameriere', 'waiter', 'ober'), ('conto', 'bill', 'rekening'), ('menù', 'menu', 'menukaart')]);
  b.vocabSkill('restaurant', 0, 'At the restaurant', 'In het restaurant', ['cameriere', 'conto', 'menù', 'vino', 'acqua'],
      requires: ['cooking', 'market']);
  words([('ricetta', 'recipe', 'recept'), ('olio', 'oil', 'olie'), ('aglio', 'garlic', 'knoflook')]);
  b.vocabSkill('recipes', 1, 'Recipes', 'Recepten', ['ricetta', 'olio', 'aglio', 'sale'], requires: ['restaurant']);

  // ---- topic: Travel and holidays (anchored at the main tree's last skill)
  b.topic('viaggi', 1, 'Travel and holidays', 'Reizen en vakantie', anchor: 'city-life', shortEn: 'Travel', icon: 'travel');
  b.unit('viaggi-u1', 5, 'On the road', 'Onderweg', topic: 'viaggi');
  words([('stazione', 'station', 'station'), ('biglietto', 'ticket', 'kaartje'), ('binario', 'platform', 'perron')]);
  b.vocabSkill('station', 0, 'At the station', 'Op het station', ['stazione', 'biglietto', 'binario', 'treno'],
      requires: ['city-life']);
  words([('albergo', 'hotel', 'hotel'), ('camera', 'room', 'kamer'), ('chiave', 'key', 'sleutel')]);
  b.vocabSkill('hotel', 1, 'The hotel', 'Het hotel', ['albergo', 'camera', 'chiave'], requires: ['station']);
  words([('museo', 'museum', 'museum'), ('spiaggia', 'beach', 'strand'), ('mare', 'sea', 'zee')]);
  b.vocabSkill('sights', 2, 'Sightseeing', 'Bezienswaardigheden', ['museo', 'spiaggia', 'mare'], requires: ['station']);
  return b.build();
}

/// A catalog with only [topicCourse].
class TopicCourseCatalog implements CourseCatalog {
  TopicCourseCatalog([CourseData? course]) : course = course ?? topicCourse();
  final CourseData course;
  @override
  Future<List<CourseMeta>> listCourses() async => [course.meta];
  @override
  Future<CourseData> open(String courseId) async => course;
  @override
  bool isDemo(String courseId) => false;
}
