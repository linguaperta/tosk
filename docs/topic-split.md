# The topic split of the courses

*Applied 21 October 2026 in tosk-data: Italian pack 1.4.0, Dutch pack 1.3.0; Spanish unchanged (1.0.1). It replaces the earlier proposal (in this file's git history), which moved 28 skills with story rewrites and re-pointed main-tree skills; the owner chose a strict rule instead (20–21 October). Built-in topics are described in [extensions.md](extensions.md) and [pack-format.md](pack-format.md) 3.3.*

## The rule

A skill moves into a topic **only if the rest of the main tree below it can skip it**: no later main-tree skill depends on it. If anything further down needs it, it stays in the main tree. Concretely, a main-tree vocabulary skill stays when any of these holds:

1. **Prerequisite.** A main-tree skill lists it in `requires`. (No main-tree skill is re-pointed to make room.)
2. **Lesson words.** A later main-tree skill selects one of the words it introduces (its own words: those it is the first skill to select).
3. **Stories.** A main-tree story uses one of its words, other than as the story's one declared new word. (No story is rewritten.)
4. **Sentences, after gating.** A later main-tree skill would be left with no sentence for one of its words without this skill's words: every sentence containing that word also contains one of the skill's words.
5. **Grammar.** It introduces a grammar feature or trains verb forms (no themed vocabulary skill does).

It must also be a themed cluster (food, clothes, crime…): general vocabulary that passes the rule (`ideas` in Dutch, `adverbs` and `more-verbs` in Spanish) stays.

**Sentences.** A sentence that contains a moved skill's word and has its home in a later main-tree skill stays valid (pack format 1.2: one home skill per tree). The app counts such a word as unknown vocabulary for a learner who hasn't started the topic, exactly like a word of any main-tree skill they skipped, so it may appear within the gating cap (1 unknown word for grammar, 2 for vocabulary). That costs a little variety but no lesson depends on it; rule 4 catches the cases where a lesson would depend on it. The counts are in the tables below ("later main-tree sentences").

**How it was checked.** A scratch script ran these five checks over the sources (it uses the pipeline's `query`, `features.SkillGraph` and `stories.StoryChecker`) for every main-tree vocabulary skill: 43 in Italian, 24 in Dutch and 24 in Spanish. After the move, `python -m pipeline validate it nl` and the build passed. The validator enforces rules 1–3 by itself: a main-tree skill may not require a topic skill or select a topic's words, and a main-tree story may not use a topic's words.

## The anchor model (changed with the split)

- **The anchor is the topic's entry point**: the last main-tree skill its **first skill** requires (`anchor` defaults to the deepest of those). The branch on the main tree grows there, and the topic opens once it is started.
- **Late requirements.** A later skill of a topic may require later main-tree skills, each on its own. It stays locked until those are started. Its node shows a lock and "needs The conditional · unit 12" in place of the days chip, and a tap goes to that skill in the main tree. Its sheet says "Needs … of the main tree. It opens once you have started that skill." and has a "Go to unit 12" button. The same note shows on a topic's first skill while the topic's anchor isn't started.
- **Kept rules:** the main tree never requires a topic skill, and a topic never requires another topic's skill.
- **Stories in topics:** a story may belong to a topic unit. It may then use the topic's words up to its unit, and the main tree's words and grammar up to the last main-tree unit that the topic's skills require.
- Where it lives: `pipeline/pipeline/topics.py` (`default_anchor`, `late_requirements`, `validate_topics`), `stories.py` (topic-unit stories), pack-format.md 3.3, 9 and 16 (rule 14b); in the app, `CourseTrees.mainRequirements` / `mainUnitNumber`, `topicSkillNeed` (`ui/map/tree_selector.dart`), `SkillNode` (the note), `SkillSheet`, `mapFocusProvider` / `MapScreen` (going there). See docs/ui.md "Topic trees".

## What moved

| Course | Skill (unit before) | Topic | Anchor | Late requirements | Words | Later main-tree sentences with its words |
| --- | --- | --- | --- | --- | --- | --- |
| it | `crime` (u15) | `crimine`, *Crime and investigation* (short: *Crime*), unit `crimine-u1` *The inspector* | `passato-remoto` (u15) | none | 38 own + `uccidere` shared | 77 |
| nl | `clothes` (u7) | `kleding`, *Clothes*, unit `kleding-u1` *What to wear* | `shopping` (u6; `clothes` also requires `travel`, a sibling) | none | 22 | 87 |
| es | nothing | | | | | |

Skill, item and facet ids are unchanged, so progress is kept. The moved skills' words now have the topic unit as their `unit` in the lexicon (as the importer resolves units: the first skill in course order, main tree first). Sentences touching them have it too: 54 generated + 843 Tatoeba sentences in Italian, 5 + 556 in Dutch. Those are records moved between `sentences/*.jsonl` files, with their content unchanged.

**Italian `crime` and the passato remoto** (owner decision 3). The topic is connected where the passato remoto is taught: its skill requires `passato-remoto`, and that is its anchor. The connection validated as is, so **the main passato remoto skills were not extended**. The one crime word a main-tree skill trains, `uccidere` (in `passato-remoto-irregular`'s verb list), simply stays a main-tree word introduced by that skill, and `crime` shares it (same id, one progress). The crime story **`u15-commissario` ("La lettera senza firma") moved into the topic** (`stories/crimine.yaml`, unit `crimine-u1`, text unchanged, id kept). It is the topic's own story: it uses six crime words, and the rule would otherwise have kept `crime` in the main tree. Its irregular passato remoto forms (lesse, vide) are allowed because the topic's main-tree reach is unit 15. Unit 15 keeps `u15-favola`.

**Versions and old apps.** The packs are it 1.4.0 and nl 1.3.0 (schema minor 3). `min_app_version` is unchanged: it 0.7.3 (moods), nl 0.4.0. An app from before topics (0.7.3 and older) ignores the topic tables and shows the topic unit as one more unit at the end of the main tree. There the skill is locked until its prerequisites are started, and the Italian story sits in that unit, with the same ids and progress. The owner accepted this. Spanish has no change, so it was not bumped (the lead had planned 1.1.0).

## What stayed, and why

Main-tree vocabulary skills checked, and how many each rule keeps (a skill can be kept by several rules):

| Course | Checked | Moved | Required by a main-tree skill | Words selected later | Used by main-tree stories | Kept by stories alone | Sentence coverage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| it | 43 | 1 | 28 | 9 | 41 | 12 | 10 |
| nl | 24 | 1 | 12 | 8 | 22 | 9 | 2 |
| es | 24 | 0 | 17 | 2 | 20 | 5 | 1 |

The top reasons:

- **Stories.** Almost every themed skill is used by a main-tree story, often a story of a later unit. Italian `weather`, `animals` and `clothes` share the two u7 stories and appear in u8–u13 stories. `kitchen` has `u5-zuppa` and `u11-ricetta`. `leisure` and `shopping` share `u8-spesa`. `services` has `u10-banca`, and `reading` has `u15-favola`. Dutch `kitchen` (*aardbei* in `u6-markt`, *banaan* in `u7-dieren`), `weather`, `animals` and `leisure`; Spanish `body`, `work` and `feelings`.
- **Prerequisites.** Italian u10–u14 vocabulary feeds the next grammar skill: `routine` and `health` for `imperative`, `directions`, `food-more` and `media` for `ci-ne`, `emotions`, `opinions` and `verbs-three` for `comparatives`, `nature`, `society` and `abstract` for `congiuntivo`, and `character`, `connectors` and `money` for `passato-remoto`. In Dutch, `shopping` and `travel` are required by u7. In Spanish, `kitchen` and `clothes` are required by `work`, `feelings` and `preterito-perfecto`, and `weather`, `animals` and `leisure` by `imperfecto`.
- **Words selected later**: the core skills (greetings, people, food, home, family) feed the article, plural and diminutive skills; Dutch `body` feeds `diminutives`.
- **Moving one skill can free another, but the rule stays strict.** Once `crime` moved, its story no longer kept `services` in the main tree, but `u10-banca` still does. Moving `u10-banca` too would have freed `services`. It would also have made the crime story use a word of another topic (*lettera*), and topics may not depend on each other. So `services` stays. The same goes for `reading`: its only story is `u15-favola`, and moving that would leave unit 15 without a story.

### Per-skill check (sources before the split)

"Kept by" lists every rule that keeps the skill. The last column counts sentences with one of its words whose main-tree home is a later skill (variety, not dependency).

#### Italian (it)

| Skill (unit) | Words | Kept by | Later main-tree sentences with its words |
| --- | --- | --- | --- |
| `greetings` (u1) | 19 | required by `little-words`, `people`; its words are selected by `people`, `articles`, `plurals`; 9 main-tree stories use its words (`u1-piacere`, `u4-malata`, `u4-casa-nuova`, `u6-primo-giorno`, …); 1 later word(s) have sentences only with its words (`opinions`) | 2619 |
| `little-words` (u1) | 31 | required by `essere-avere`; its words are selected by `numbers`; 30 main-tree stories use its words (`u1-piacere`, `u1-famiglia`, `u2-pizza`, `u2-colazione`, …); 333 later word(s) have sentences only with its words (`abstract`, `adjectives`, `adjectives-more`, …) | 40324 |
| `people` (u1) | 31 | required by `essere-avere`; its words are selected by `articles`, `plurals`; 18 main-tree stories use its words (`u1-piacere`, `u1-famiglia`, `u2-pizza`, `u2-colazione`, …); 1 later word(s) have sentences only with its words (`connectors`) | 14557 |
| `food` (u2) | 30 | required by `articles`; its words are selected by `articles`, `plurals`; 13 main-tree stories use its words (`u2-pizza`, `u2-colazione`, `u3-compleanno`, `u4-malata`, …); 1 later word(s) have sentences only with its words (`connectors`) | 2760 |
| `numbers` (u2) | 22 | 14 main-tree stories use its words (`u2-pizza`, `u2-colazione`, `u5-treno`, `u5-zuppa`, …) | 1256 |
| `time` (u3) | 30 | required by `family`; 23 main-tree stories use its words (`u3-compleanno`, `u3-chiavi`, `u4-malata`, `u4-casa-nuova`, …); 1 later word(s) have sentences only with its words (`connectors`) | 5425 |
| `home` (u3) | 29 | required by `everyday-verbs`, `plurals`; its words are selected by `plurals`; 18 main-tree stories use its words (`u3-compleanno`, `u3-chiavi`, `u4-malata`, `u4-casa-nuova`, …) | 2946 |
| `family` (u3) | 16 | required by `plurals`; its words are selected by `plurals`; 6 main-tree stories use its words (`u3-compleanno`, `u4-malata`, `u5-zuppa`, `u9-sogno`, …) | 770 |
| `everyday-verbs` (u3) | 28 | its words are selected by `imperative`; 17 main-tree stories use its words (`u3-compleanno`, `u4-malata`, `u5-treno`, `u5-zuppa`, …); 1 later word(s) have sentences only with its words (`services`) | 2672 |
| `body` (u4) | 28 | 5 main-tree stories use its words (`u4-malata`, `u5-treno`, `u9-sogno`, `u10-mattina`, …) | 1149 |
| `adverbs` (u4) | 18 | 12 main-tree stories use its words (`u4-malata`, `u4-casa-nuova`, `u5-zuppa`, `u6-primo-giorno`, …) | 2556 |
| `colours` (u4) | 13 | required by `city`, `travel`, `kitchen`; 2 main-tree stories use its words (`u4-casa-nuova`, `u7-bambino`) | 418 |
| `city` (u5) | 28 | required by `prepositions`; 16 main-tree stories use its words (`u5-treno`, `u6-primo-giorno`, `u6-esame`, `u7-bambino`, …) | 1631 |
| `travel` (u5) | 23 | required by `prepositions`; 8 main-tree stories use its words (`u5-treno`, `u7-bambino`, `u8-concerto`, `u8-spesa`, …); 1 later word(s) have sentences only with its words (`connectors`) | 1382 |
| `kitchen` (u5) | 29 | 2 main-tree stories use its words (`u5-zuppa`, `u11-ricetta`) | 603 |
| `work` (u6) | 28 | 6 main-tree stories use its words (`u6-primo-giorno`, `u6-esame`, `u9-scelta`, `u10-mattina`, …); 2 later word(s) have sentences only with its words (`connectors`) | 1498 |
| `feelings` (u6) | 23 | 3 main-tree stories use its words (`u6-primo-giorno`, `u6-esame`, `u14-colloquio`) | 766 |
| `weather` (u7) | 26 | 5 main-tree stories use its words (`u7-bambino`, `u7-pioggia`, `u9-sogno`, `u12-mare`, …) | 694 |
| `animals` (u7) | 21 | 4 main-tree stories use its words (`u7-bambino`, `u7-pioggia`, `u9-sogno`, `u13-gita`) | 538 |
| `clothes` (u7) | 22 | 3 main-tree stories use its words (`u7-bambino`, `u7-pioggia`, `u8-spesa`) | 496 |
| `leisure` (u8) | 23 | 2 main-tree stories use its words (`u8-concerto`, `u8-spesa`) | 825 |
| `shopping` (u8) | 20 | 3 main-tree stories use its words (`u8-concerto`, `u8-spesa`, `u12-regalo`) | 462 |
| `more-verbs` (u9) | 30 | required by `little-words-2`; its words are selected by `imperative`, `imperative-irregular`; 8 main-tree stories use its words (`u9-scelta`, `u9-sogno`, `u10-banca`, `u12-regalo`, …) | 898 |
| `ideas` (u9) | 28 | required by `little-words-2`; 4 main-tree stories use its words (`u9-scelta`, `u9-sogno`, `u12-mare`, `u13-citta`) | 1389 |
| `little-words-2` (u10) | 24 | required by `reflexive-present`; 6 main-tree stories use its words (`u12-mare`, `u13-gita`, `u13-citta`, `u14-colloquio`, …); 2 later word(s) have sentences only with its words (`connectors`) | 3878 |
| `routine` (u10) | 42 | required by `imperative`; 2 main-tree stories use its words (`u10-mattina`, `u11-stazione`) | 366 |
| `health` (u10) | 39 | required by `imperative`; 1 main-tree story uses its words (`u10-mattina`) | 235 |
| `services` (u10) | 39 | 2 main-tree stories use its words (`u10-banca`, `u15-commissario`) | 245 |
| `directions` (u11) | 39 | required by `ci-ne`; 3 main-tree stories use its words (`u11-stazione`, `u13-citta`, `u15-commissario`) | 243 |
| `food-more` (u11) | 40 | required by `ci-ne`; 1 main-tree story uses its words (`u11-ricetta`) | 101 |
| `media` (u11) | 37 | required by `ci-ne` | 277 |
| `emotions` (u12) | 38 | required by `comparatives`; 1 main-tree story uses its words (`u12-regalo`) | 343 |
| `opinions` (u12) | 36 | required by `comparatives`; 1 main-tree story uses its words (`u12-mare`) | 309 |
| `verbs-three` (u12) | 43 | required by `comparatives`; 1 main-tree story uses its words (`u14-lotteria`) | 527 |
| `adjectives-more` (u13) | 40 | required by `congiuntivo`; 2 later word(s) have sentences only with its words (`connectors`) | 375 |
| `nature` (u13) | 38 | required by `congiuntivo`; 3 main-tree stories use its words (`u13-gita`, `u13-citta`, `u15-favola`) | 102 |
| `society` (u13) | 41 | required by `congiuntivo`; 1 main-tree story uses its words (`u13-citta`) | 132 |
| `abstract` (u13) | 37 | required by `congiuntivo`; 2 main-tree stories use its words (`u15-commissario`, `u15-favola`) | 212 |
| `character` (u14) | 37 | required by `passato-remoto`; 2 main-tree stories use its words (`u14-colloquio`, `u15-favola`) | 75 |
| `connectors` (u14) | 34 | required by `passato-remoto`; 2 main-tree stories use its words (`u14-colloquio`, `u14-lotteria`) | 45 |
| `money` (u14) | 37 | required by `passato-remoto`; 1 main-tree story uses its words (`u14-colloquio`) | 41 |
| `crime` (u15) | 39 | **moved**: `passato-remoto-irregular` selects `uccidere` (kept as a main-tree word); `u15-commissario` moved with it | 77 |
| `reading` (u15) | 38 | 1 main-tree story uses its words (`u15-favola`) | 0 |

#### Dutch (nl)

| Skill (unit) | Words | Kept by | Later main-tree sentences with its words |
| --- | --- | --- | --- |
| `greetings` (u1) | 20 | required by `little-words`, `people`; 8 main-tree stories use its words (`u1-tom-helpt`, `u2-huis`, `u3-oma`, `u3-te-laat`, …) | 1272 |
| `little-words` (u1) | 39 | required by `present-regular`; its words are selected by `numbers`; 16 main-tree stories use its words (`u1-familie`, `u1-tom-helpt`, `u2-ontbijt`, `u2-huis`, …); 100 later word(s) have sentences only with its words (`adjectives`, `animals`, `body`, …) | 13792 |
| `people` (u1) | 29 | required by `present-regular`; its words are selected by `de-het`, `plurals`, `diminutives`; 16 main-tree stories use its words (`u1-familie`, `u1-tom-helpt`, `u2-ontbijt`, `u2-huis`, …); 5 later word(s) have sentences only with its words (`everyday-verbs`, `leisure`, `more-verbs`, …) | 11814 |
| `food` (u2) | 23 | required by `home`; its words are selected by `de-het`, `plurals`; 9 main-tree stories use its words (`u2-ontbijt`, `u3-oma`, `u3-te-laat`, `u4-eerste-werkdag`, …) | 895 |
| `numbers` (u2) | 24 | 11 main-tree stories use its words (`u2-huis`, `u3-oma`, `u3-te-laat`, `u4-eerste-werkdag`, …) | 667 |
| `home` (u2) | 28 | required by `de-het`; its words are selected by `de-het`, `plurals`, `diminutives`; 10 main-tree stories use its words (`u2-ontbijt`, `u2-huis`, `u3-oma`, `u3-te-laat`, …) | 1036 |
| `time` (u3) | 32 | required by `work`, `feelings`, `perfectum-hebben`; its words are selected by `diminutives`; 11 main-tree stories use its words (`u3-oma`, `u3-te-laat`, `u4-eerste-werkdag`, `u4-examen`, …) | 1533 |
| `family` (u3) | 17 | required by `plurals`; its words are selected by `plurals`; 3 main-tree stories use its words (`u3-oma`, `u8-concert`, `u8-droom`) | 335 |
| `everyday-verbs` (u3) | 30 | required by `separable`; its words are selected by `verleden-tijd-weak`; 10 main-tree stories use its words (`u3-oma`, `u3-te-laat`, `u4-eerste-werkdag`, `u4-examen`, …) | 1474 |
| `work` (u4) | 27 | 3 main-tree stories use its words (`u4-eerste-werkdag`, `u4-examen`, `u5-dokter`) | 576 |
| `feelings` (u4) | 22 | 5 main-tree stories use its words (`u4-eerste-werkdag`, `u4-examen`, `u5-zusje`, `u7-dieren`, …) | 311 |
| `body` (u5) | 27 | its words are selected by `diminutives`; 4 main-tree stories use its words (`u5-dokter`, `u5-zusje`, `u8-concert`, `u8-droom`) | 343 |
| `adverbs` (u5) | 21 | 5 main-tree stories use its words (`u5-dokter`, `u5-zusje`, `u6-markt`, `u7-storm`, …) | 558 |
| `colours` (u5) | 12 | required by `city`, `travel`, `kitchen`; 1 main-tree story uses its words (`u5-zusje`) | 257 |
| `city` (u6) | 26 | required by `shopping`; 4 main-tree stories use its words (`u6-markt`, `u6-eiland`, `u7-dieren`, `u8-droom`) | 231 |
| `travel` (u6) | 22 | required by `weather`, `animals`, `clothes`, `verleden-tijd-weak`; 2 main-tree stories use its words (`u6-eiland`, `u8-droom`) | 227 |
| `kitchen` (u6) | 29 | 2 main-tree stories use its words (`u6-markt`, `u7-dieren`) | 110 |
| `shopping` (u6) | 18 | required by `weather`, `animals`, `clothes`, `verleden-tijd-weak`; 1 main-tree story uses its words (`u6-markt`) | 159 |
| `weather` (u7) | 25 | 2 main-tree stories use its words (`u7-storm`, `u8-droom`) | 142 |
| `animals` (u7) | 21 | 3 main-tree stories use its words (`u7-storm`, `u7-dieren`, `u8-droom`) | 142 |
| `clothes` (u7) | 22 | **moved** | 87 |
| `leisure` (u8) | 22 | 1 main-tree story uses its words (`u8-concert`) | 66 |
| `more-verbs` (u8) | 30 | 2 main-tree stories use its words (`u8-concert`, `u8-droom`) | 40 |
| `ideas` (u8) | 27 | nothing: movable | 0 |

#### Spanish (es)

| Skill (unit) | Words | Kept by | Later main-tree sentences with its words |
| --- | --- | --- | --- |
| `greetings` (u1) | 23 | required by `little-words`, `people`; 13 main-tree stories use its words (`u1-encantado`, `u1-donde-estan`, `u2-desayuno`, `u3-un-dia`, …) | 4549 |
| `little-words` (u1) | 45 | required by `ser`; 18 main-tree stories use its words (`u1-encantado`, `u1-donde-estan`, `u2-desayuno`, `u2-la-cena`, …); 148 later word(s) have sentences only with its words (`adjectives`, `adverbs`, `animals`, …) | 20829 |
| `people` (u1) | 32 | required by `ser`; its words are selected by `articles`; 10 main-tree stories use its words (`u1-encantado`, `u1-donde-estan`, `u2-la-cena`, `u3-la-llave`, …) | 5520 |
| `food` (u2) | 37 | required by `articles`; its words are selected by `articles`; 5 main-tree stories use its words (`u2-desayuno`, `u2-la-cena`, `u3-un-dia`, `u4-me-gusta`, …) | 1652 |
| `numbers` (u2) | 41 | 5 main-tree stories use its words (`u2-desayuno`, `u2-la-cena`, `u3-un-dia`, `u5-mi-familia`, …) | 1200 |
| `time` (u3) | 52 | required by `prepositions`; 10 main-tree stories use its words (`u3-un-dia`, `u4-medico`, `u6-sevilla`, `u6-tienda`, …) | 3801 |
| `home` (u3) | 51 | required by `prepositions`; 8 main-tree stories use its words (`u3-un-dia`, `u3-la-llave`, `u4-medico`, `u5-mi-familia`, …) | 2117 |
| `everyday-verbs` (u4) | 4 | required by `family`, `adjectives`; 1 main-tree story uses its words (`u6-tienda`) | 272 |
| `body` (u4) | 41 | 2 main-tree stories use its words (`u4-medico`, `u7-dia-largo`) | 936 |
| `adverbs` (u4) | 27 | nothing: movable | 972 |
| `family` (u5) | 26 | required by `possessives`; 4 main-tree stories use its words (`u5-mi-familia`, `u6-tienda`, `u9-de-nino`, `u9-planes`) | 588 |
| `colours` (u5) | 13 | required by `city`, `travel`, `shopping`, `kitchen`; 3 main-tree stories use its words (`u5-mi-familia`, `u5-colores`, `u6-tienda`) | 344 |
| `city` (u6) | 40 | required by `reflexive`; 5 main-tree stories use its words (`u6-sevilla`, `u6-tienda`, `u8-tormenta`, `u8-gato`, …) | 597 |
| `travel` (u6) | 40 | required by `reflexive`; 4 main-tree stories use its words (`u6-sevilla`, `u8-tormenta`, `u9-de-nino`, `u9-planes`) | 749 |
| `shopping` (u6) | 24 | required by `clothes`; 1 main-tree story uses its words (`u6-tienda`) | 344 |
| `kitchen` (u6) | 30 | required by `work`, `feelings`, `preterito-perfecto` | 131 |
| `clothes` (u6) | 31 | required by `work`, `feelings`, `preterito-perfecto`; 1 main-tree story uses its words (`u6-tienda`) | 204 |
| `work` (u7) | 41 | 2 main-tree stories use its words (`u7-dia-largo`, `u7-examen`) | 607 |
| `feelings` (u7) | 34 | 5 main-tree stories use its words (`u7-dia-largo`, `u7-examen`, `u8-tormenta`, `u8-gato`, …) | 511 |
| `weather` (u8) | 36 | required by `imperfecto`; 2 main-tree stories use its words (`u8-tormenta`, `u9-planes`) | 248 |
| `animals` (u8) | 35 | required by `imperfecto`; 2 main-tree stories use its words (`u8-tormenta`, `u8-gato`) | 142 |
| `leisure` (u8) | 29 | required by `imperfecto` | 124 |
| `more-verbs` (u9) | 30 | nothing: movable | 93 |
| `ideas` (u9) | 43 | 1 main-tree story uses its words (`u9-de-nino`) | 0 |
