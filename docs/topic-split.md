# The topic structure of the courses

*Applied 21 October 2026 in tosk-data: Italian pack 1.5.0, Dutch 1.4.0, Spanish 1.1.0 (owner decisions of 21 October). It replaces the strict split of the same day (it 1.4.0, nl 1.3.0: only Italian `crime` and Dutch `clothes` moved, because a skill moved only when nothing below it needed it; that version is in this file's git history). Built-in topics are described in [extensions.md](extensions.md) and [pack-format.md](pack-format.md) 3.3.*

## The structure and the fairness rule

- **A slim main tree.** The main tree keeps the grammar and the **core vocabulary** that the grammar needs: greetings and little words, people and family, numbers, time, home, everyday verbs, adjectives and adverbs, colours, basic food, the city and travel, work and school, and the general vocabulary of the later units (more verbs, ideas, connectors, abstract nouns). **Grammar skills require only main-tree skills.**
- **Themed vocabulary becomes topics** that branch off where their needs are met: weather, animals and nature, clothes and shopping, the kitchen and cooking, the body and health, feelings and character, free time and media, services and directions, society and money, reading. A topic's **anchor is its entry point** (the last main-tree skill its first skill requires); later skills of a topic may require later main-tree skills and wait for them (*late requirements*, with a "needs … · unit N" note).
- **The fairness rule: never unknown grammar; some unknown words are fine.** Grammar gating stays strict everywhere. The words of a topic the learner skipped count as unknown vocabulary: they may appear in main-tree lessons within the existing cap (one per sentence in a grammar lesson, two otherwise) and in main-tree stories (at most three per story, glossed before it). Every main-tree grammar skill keeps its sentence floor without topic words beyond that allowance; where the restructure made a pool thin, validated generated sentences from core vocabulary (`src: claude-gen`) top it up. The mechanics are in [extensions.md](extensions.md) ("The fairness rule"); the build enforces the floor (pack-format 16, rule 14c).
- **Stories**: a story mainly about a theme moved into that topic's units (ids kept, so reading progress is kept); every main-tree unit keeps two stories (new ones were written from core vocabulary where needed); topic units have 0–3.
- **Ids are unchanged** (items, skills, facets), so progress is kept. Requirements were re-pointed, skills and their words moved: the moved skills' words carry their topic unit in the lexicon, and the sentences touching them carry it too (records moved between `sentences/*.jsonl` files, content unchanged; the importer's rule: an item's unit is the first unit in course order that selects it, main tree first).

### How it was decided and checked

For each course a scratch script moved the candidate skills in memory, re-pointed the grammar requirements and compared every main-tree grammar skill's *easy* sentences (gaps.py: grammar allowed, at most one word taught later or in a topic) and verb × person slots before and after; another ran the story checker under the new rule. Core versus themed follows the owner's list, adjusted per course where a skill is general rather than themed (Italian `opinions`, `abstract`, `connectors`; Spanish `travel`, which also holds *fiesta*, *música*, *fútbol*, stays as the travel basics). The re-pointed grammar skills keep the same prerequisite closure of grammar, so no sentence's allowed grammar shrank. After the move, `python -m pipeline build it nl es` (which now runs the fairness check) and the real-pack tests pass.

## The anchor model

- **The anchor is the topic's entry point**: the last main-tree skill its **first skill** requires (`anchor` defaults to the deepest of those). The branch on the main tree grows there, and the topic opens once it is started.
- **Late requirements.** A later skill of a topic may require later main-tree skills, each on its own. It stays locked until those are started. Its node shows a lock and "needs The conditional · unit 12" in place of the days chip, and a tap goes to that skill in the main tree. Its sheet says "Needs … of the main tree. It opens once you have started that skill." and has a "Go to unit 12" button. The same note shows on a topic's first skill while the topic's anchor isn't started.
- **Kept rules:** the main tree never requires a topic skill, and a topic never requires another topic's skill.
- **Stories in topics:** a story may belong to a topic unit. It may then use the topic's words up to its unit, and the main tree's words and grammar up to the last main-tree unit that the topic's skills require, plus up to three words of other topics.
- Where it lives: `pipeline/pipeline/topics.py` (`default_anchor`, `late_requirements`, `validate_topics`), `stories.py` (topic-unit stories, `MAX_TOPIC_WORDS`), `gaps.py` (`fairness_report`), pack-format.md 3.3, 9 and 16 (rules 14b, 14c); in the app, `CourseTrees.mainRequirements` / `mainUnitNumber`, `topicSkillNeed` (`ui/map/tree_selector.dart`), `SkillNode` (the note), `SkillSheet`, `mapFocusProvider` / `MapScreen` (going there). See docs/ui.md "Topic trees".
- To spread the branches over the map, some topics' first skills require a slightly later main-tree skill than before (each topic then has its own anchor): Italian `kitchen` requires `prepositions` (its story uses *nella*, *sul*), `feelings` requires `passato-prossimo`, `body` requires `adjectives` (its story uses unit-4 words), `weather`/`animals` require `imperfetto` (their stories are told in it), `leisure` requires `futuro`; Dutch `body` requires `adjectives`, `weather`/`animals` require `verleden-tijd-strong`, `leisure` requires `more-verbs` and `ideas`; Spanish `body` requires `gustar` (*me duele*), `kitchen` requires `city`, `weather`/`animals` require `indefinido-irregular`, `leisure` requires `indefinido`. Requirements only widen what a topic's sentences may use; they never touch the main tree.

## Italian (it 1.5.0)

**Main tree: 15 units, 57 skills (35 grammar, 22 vocab)**; before: 15 units, 77 skills (35 grammar, 42 vocab) plus the topic *Crime*.

| Unit | Skills |
| --- | --- |
| u1 Basics | greetings, little-words, people, essere-avere |
| u2 The present tense | food, numbers, present-are, articles, present-ere, present-ire |
| u3 Everyday life | time, home, family, everyday-verbs, irregular-present, pronouns, modal-verbs, plurals |
| u4 Describing things | adjectives, adverbs, colours, possessives |
| u5 Around town | city, travel, prepositions |
| u6 The past | work, passato-prossimo, passato-prossimo-essere |
| u7 Memories | imperfetto |
| u8 Plans for the future | futuro, futuro-irregular |
| u9 Talking about life | more-verbs, ideas |
| u10 Daily routine | little-words-2, reflexive-present, reflexive-past |
| u11 Do it! | imperative, imperative-irregular, imperative-pronouns |
| u12 I would like... | ci-ne, combined-pronouns, condizionale, condizionale-irregular, opinions, verbs-three |
| u13 More or less | comparatives, adjectives-more, progressive, impersonal-si, abstract |
| u14 Hopes and doubts | congiuntivo, congiuntivo-irregular, connectors, congiuntivo-imperfetto |
| u15 Reading Italian | passato-remoto, passato-remoto-irregular, relatives |

**Re-pointed:** `imperative` requires `reflexive-past` (was also `health`, `routine`); `ci-ne` requires `imperative-pronouns` (was also `media`, `directions`, `food-more`); `comparatives` drops `emotions`; `congiuntivo` requires `adjectives-more`, `abstract` (was also `nature`, `society`); `passato-remoto` requires `connectors`, `congiuntivo-imperfetto` (was `character`, `connectors`, `money`).

**Topics (10, in tree-menu order):**

| Topic | Title (short) | Anchor | Skills (unit, own words; late requirements) | Stories |
| --- | --- | --- | --- | --- |
| `salute` | Body and health (Health) | `adjectives` (u4) | `body` (salute-u1, 28 words); `routine` (salute-u2, 42 words; needs `reflexive-present` u10); `health` (salute-u2, 39 words; needs `reflexive-present` u10) | `u4-malata`, `u10-mattina` |
| `cucina` | Food and cooking (Cooking) | `prepositions` (u5) | `kitchen` (cucina-u1, 29 words); `food-more` (cucina-u2, 40 words; needs `imperative` u11) | `u5-zuppa`, `u11-ricetta` |
| `emozioni` | Feelings and character (Feelings) | `passato-prossimo` (u6) | `feelings` (emozioni-u1, 23 words); `emotions` (emozioni-u2, 38 words; needs `ci-ne` u12); `character` (emozioni-u3, 37 words; needs `congiuntivo` u14) | none |
| `moda` | Clothes and shopping (Shopping) | `passato-prossimo-essere` (u6) | `clothes` (moda-u1, 22 words); `shopping` (moda-u1, 20 words; needs `futuro` u8) | `u8-spesa` |
| `natura` | Weather, animals and nature (Nature) | `imperfetto` (u7) | `weather` (natura-u1, 26 words); `animals` (natura-u1, 21 words); `nature` (natura-u2, 38 words; needs `progressive` u13) | `u7-bambino`, `u7-pioggia`, `u13-gita` |
| `tempo-libero` | Free time and media (Free time) | `futuro` (u8) | `leisure` (tempo-libero-u1, 23 words); `media` (tempo-libero-u2, 37 words; needs `imperative-irregular` u11) | `u8-concerto` |
| `servizi` | In town: services and directions (In town) | `reflexive-past` (u10) | `services` (servizi-u1, 39 words); `directions` (servizi-u2, 39 words; needs `imperative` u11) | `u10-banca`, `u11-stazione` |
| `societa` | Society and the economy (Society) | `impersonal-si` (u13) | `society` (societa-u1, 41 words); `money` (societa-u2, 37 words; needs `congiuntivo-imperfetto` u14) | `u13-citta`, `u14-colloquio` |
| `crimine` | Crime and investigation (Crime) | `passato-remoto` (u15) | `crime` (crimine-u1, 38 words) | `u15-commissario` |
| `letture` | Books and stories (Books) | `passato-remoto-irregular` (u15) | `reading` (letture-u1, 38 words) | `u15-favola` |

**Why these are themed and the rest core.** The body, the kitchen, weather, animals, clothes, shopping, hobbies, media, health, services, money, society, character, emotions and reading are each a self-contained field of words that no grammar point needs. `directions` (*destra, semaforo, rotonda*) moved with the services into *In town*: the city and travel basics (*strada, stazione, piazza, biglietto*) stay in the main tree. `feelings` (*paura, amore, tranquillo, orgoglioso*) is themed; the mood adjectives the grammar uses (*felice, triste, contento, stanco*) are in `adjectives`. Kept as core although they look like topics: `work` (school and work words: *domanda, risposta, lezione, soldi*), `opinions` (*secondo me, d'accordo*, the language of the subjunctive), `abstract`, `connectors`, `verbs-three`, `adjectives-more`.

**Stories.** 14 moved into topics (table above; `u15-commissario` was already in *Crime*). Four were edited to stay within three words of other topics: `u7-bambino` and `u7-pioggia` ask about the clothes in English options, `u13-citta` lost "in periferia", `u14-colloquio` says "gentile" for "simpatico". **15 new main-tree stories** from core vocabulary: `u4-paolo`, `u5-centro`, `u7-nonna`, `u7-primo-lavoro`, `u8-milano`, `u8-sabato`, `u10-lunedi`, `u10-matrimonio`, `u11-consigli`, `u11-ospite`, `u13-sorelle`, `u13-milano`, `u14-partenza`, `u15-ponte`, `u15-quaderno`. Every main unit now has two (u15 had one since the strict split). Main-tree stories that use topic words within the allowance: `u5-treno` (*piede*), `u6-primo-giorno` (3 feelings words), `u6-esame`, `u9-sogno` (*fiume, uccello, voce*), `u10-matrimonio` (*vestito*), `u11-consigli` (*tranquilla, abbraccia*), `u11-ospite` (*giacca*), `u12-regalo`, `u12-mare`.

**Sentence floor.** 196 generated sentences, all from core vocabulary, for 134 verb × person slots (passato prossimo, imperfetto, futuro, reflexives, imperative, conditional, subjunctive, passato remoto) that fell under 8 easy sentences once topic words count as unknown. Now no main-tree grammar skill is under its floor because of topic words; the easy sentences per grammar skill for a learner who skipped every topic range from 83 (`combined-pronouns`, unchanged) and 121 (`ci-ne`) to 26 326 (`congiuntivo-imperfetto`). Thin spots that were there before and are not caused by topics: one slot each in `present-ire` and `imperative-pronouns` (*preoccupati*), one item each in `pronouns` and `ci-ne`.

## Dutch (nl 1.4.0)

**Main tree: 8 units, 29 skills (13 grammar, 16 vocab)**; before: 8 units, 36 skills plus the topic *Clothes*.

| Unit | Skills |
| --- | --- |
| u1 Basics | greetings, little-words, people, present-regular |
| u2 | food, numbers, present-irregular, home, de-het |
| u3 | time, family, everyday-verbs, pronouns, separable, plurals |
| u4 The perfect tense | work, perfectum-hebben, perfectum-zijn |
| u5 Describing things | adjectives, adverbs, colours, possessives, diminutives |
| u6 Around town | city, travel |
| u7 The simple past | verleden-tijd-weak, verleden-tijd-strong |
| u8 Free time and ideas | more-verbs, ideas |

**Re-pointed:** `verleden-tijd-weak` requires `city`, `travel` (was `shopping`, `travel`).

**Topics (6):**

| Topic | Title (short) | Anchor | Skills (unit, own words) | Stories |
| --- | --- | --- | --- | --- |
| `gevoelens` | Feelings (Feelings) | `separable` (u3) | `feelings` (gevoelens-u1, 22 words) | none |
| `gezondheid` | Body and health (Health) | `adjectives` (u5) | `body` (gezondheid-u1, 23 words) | `u5-dokter` |
| `eten` | Food and cooking (Cooking) | `possessives` (u5) | `kitchen` (eten-u1, 29 words) | none |
| `kleding` | Clothes and shopping (Shopping) | `city` (u6) | `shopping` (kleding-u1, 18 words); `clothes` (kleding-u1, 22 words) | `u6-markt` |
| `natuur` | Weather and animals (Nature) | `verleden-tijd-strong` (u7) | `weather` (natuur-u1, 25 words); `animals` (natuur-u1, 21 words) | `u7-storm`, `u7-dieren` |
| `vrije-tijd` | Free time (Free time) | `ideas` (u8) | `leisure` (vrije-tijd-u1, 22 words) | `u8-concert` |

The topic `kleding` (pack 1.3, *Clothes*) is kept and now also holds `shopping` (*Clothes and shopping*). **The body:** four body nouns that the main-tree `diminutives` skill trains (its query is unchanged, so its facets are unchanged) stay main-tree words, shared with the topic (one item, one progress), like Italian *uccidere* with *Crime*.

**Stories.** Five moved into topics (table). `u7-storm` passes the allowance with three words but is about the weather, so it moved too. `u4-examen` and `u8-droom` ask in English options now (they used four topic words). **Five new main-tree stories:** `u5-nieuw-huis`, `u6-stad`, `u7-opa`, `u7-trein`, `u8-keuze`.

**Sentence floor.** 50 generated sentences for 39 slots (present irregular, perfectum, the simple past). No main-tree grammar skill is under its floor because of topic words; easy sentences per grammar skill range from 391 (`separable`) to 10 769. Earlier gaps that remain: present-regular 2 slots, present-irregular 2, perfectum-hebben 4, perfectum-zijn 12, verleden-tijd-weak 7, verleden-tijd-strong 5 (none caused by topics). **Fixed in passing:** *ouders* (parents) was aligned to the adjective *oud* (Wiktionary lists the rare partitive *iets ouders*) in 60 sentences, glossed "old"; the form is dropped from *oud* and the tokens point at *ouder*.

## Spanish (es 1.1.0)

**Main tree: 9 units, 38 skills (22 grammar, 16 vocab)**; before: 9 units, 46 skills, no topics.

| Unit | Skills |
| --- | --- |
| u1 | greetings, little-words, people, ser, estar |
| u2 | food, numbers, present-ar, articles, present-er-ir |
| u3 | time, home, prepositions, stem-changing, irregular-present |
| u4 | everyday-verbs, adverbs, verb-phrases, object-pronouns, gustar |
| u5 | family, adjectives, plurals, colours, possessives |
| u6 | city, travel, reflexive |
| u7 The recent past | work, preterito-perfecto, participles-irregular |
| u8 | indefinido, indefinido-irregular |
| u9 | imperfecto, futuro, futuro-irregular, more-verbs, ideas |

**Re-pointed:** `work` and `preterito-perfecto` require `reflexive` (were `clothes`, `kitchen`); `imperfecto` requires `indefinido-irregular` (was also `weather`, `animals`, `leisure`).

**Topics (6):**

| Topic | Title (short) | Anchor | Skills (unit, own words; late requirements) | Stories |
| --- | --- | --- | --- | --- |
| `salud` | Body and health (Health) | `gustar` (u4) | `body` (salud-u1, 41 words) | `u4-medico` |
| `compras` | Shopping and clothes (Shopping) | `possessives` (u5) | `shopping` (compras-u1, 24 words); `clothes` (compras-u1, 31 words; needs `reflexive` u6) | `u6-tienda` |
| `cocina` | Cooking and eating out (Cooking) | `city` (u6) | `kitchen` (cocina-u1, 30 words) | none |
| `sentimientos` | Feelings (Feelings) | `preterito-perfecto` (u7) | `feelings` (sentimientos-u1, 34 words) | `u7-dia-largo` |
| `naturaleza` | Weather and animals (Nature) | `indefinido-irregular` (u8) | `weather` (naturaleza-u1, 36 words); `animals` (naturaleza-u1, 35 words) | `u8-tormenta`, `u8-gato` |
| `ocio` | Hobbies and culture (Free time) | `indefinido` (u8) | `leisure` (ocio-u1, 29 words) | none |

`feelings` holds some frequent words (*verdad, solo, feliz, triste*); it moved like the other courses' feelings skills, and those words now count as unknown for a learner who skipped it (the floor check covers the cost). **Stories:** five moved into topics (`u8-gato` is about a cat); **five new:** `u4-sabado`, `u6-barrio`, `u7-primer-dia`, `u8-valencia`, `u8-carta`. **Sentence floor:** 96 generated sentences for 74 slots (reflexive, perfect, indefinido, imperfecto, future); none under the floor because of topic words; easy sentences per grammar skill from 320 (`estar`) to 11 514; earlier gaps remain in `reflexive` (2, *sentar yo*), `indefinido` (2), `imperfecto` (1). **Fixed in passing (unknown grammar):** 10 Tatoeba sentences with the subjunctive *fuera* (read as the adverb) or *te sientas* (read as *sentar*), dropped and listed in `seed.yaml` `exclude_sentences`.

## On the map

Renders with real fonts at phone width, colour, dark and black & white (and the pressed look of a branch), are in `docs/screenshots/topics-restructured/` (`app/test/qa/topics_restructured_preview.dart`): each course's main tree where several branches grow (`it-main-a`…`d`, `nl-main-a`/`b`, `es-main-a`…`c`; a learner at the imperfetto, the weak simple past, the indefinido: earlier branches open, later ones locked), one topic tree each (`it-topic-natura` with the late requirement of *Landscapes*, `nl-topic-kleding`, `es-topic-compras`) and the tree menu (Italian: the main tree and ten topics fit on a phone screen). Each topic has its own anchor, so at most one branch leaves a stone; neighbouring stones may both have one (Italian `passato-prossimo` and `passato-prossimo-essere`, Dutch `adjectives` and `possessives`), which the lanes keep apart. One crowding problem was fixed: Tosk sat over the "Go to …" button of a branch growing right above the learner's next stone (Spanish `reflexive` under *Cooking*, Italian `possessives` under *Health*, and others in every course); the marker now keeps clear of branch carvings (the button is gone since 24 October: the branch itself opens its topic; docs/ui.md "Topic trees").

## Versions and old apps

The packs are it 1.5.0, nl 1.4.0 and es 1.1.0 (schema minor 3; Spanish had no topics before), with **`min_app_version` 0.7.4** (was it 0.7.3, nl and es 0.4.0). An app from before topics ignores the topic tables and shows the topic units as further units at the end of the main tree, with a bough from each topic skill up to the main-tree skill it requires. After the restructure those boughs run across most of the map (Italian `kitchen` from unit 5 to the end: 4 500 px), and the bough painter of apps 0.7.1–0.7.3 fails on them (Skia's path intersection throws, the map paints broken); the strict split's two topics hung from the last units and stayed short. So apps before 0.7.4 keep their bundled packs and the catalog offers these as "needs app 0.7.4 or newer". The current app paints the main tree and each topic as their own maps (no such bough), and its bough painter now falls back to the uncut hatching where path ops fail, so the flattened view (the map tests draw it) paints too. Otherwise an old app would play the restructured packs safely: the main tree requires no topic skill and the moved stories keep their ids. Stories now list up to three topic words in `new_words`, which every app glosses before the story. The topic icons `health`, `heart`, `music`, `money` and `society` are new in the app; older apps show the default icon.

## Open issues

- A re-import (`python -m pipeline import nl`) would bring back *ouders* as a form of *oud*: the seed can add inflections but not drop them.
- Spanish *fue/fueron* (ser and ir share the indefinido) are aligned to *ser*, so "fue al pueblo" glosses "to be"; the new stories avoid it.
- The Italian u7 unit (*Memories*) has one skill, the imperfetto; u8 and u9 have two.
- `min_app_version` 0.7.4 assumes no build numbered 0.7.4 without topics reached a device (the version was set a few hours before topics were merged); if one did, the packs need the next app version as their minimum.
- Fixed in the app on the way: a Dutch word with an apostrophe and one consonant (*foto's*, *m'n*) was split like an Italian elision in answer diffs, so one swapped tile counted as two errors.
