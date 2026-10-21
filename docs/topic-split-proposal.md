# Proposal: moving vocabulary clusters into built-in topics

*For the owner's review, 21 October 2026. Nothing in tosk-data has changed. This applies the rule from [extensions.md](extensions.md), "Tidying the existing courses", to the it, nl and es courses.*

**The rule.** A main-tree vocab skill moves into a topic when no later grammar skill needs its words and its theme forms a coherent group (food, animals, clothes, weather, hobbies, travel, work, home, health and so on). The topic is anchored at its last main-tree requirement.

**Ids stay the same**, so existing progress is kept: facets are keyed by item id, and a moved skill keeps its skill id.

## How this was checked

The check used the compiled packs (`app/assets/courses/{it,nl,es}.sqlite`) and the sources in tosk-data. For every main-tree vocab skill it asked five questions:

1. **Required by:** which skills list it in `requires`. Moving it means re-pointing them, see below.
2. **Later selected:** whether a later skill selects its words. If one does, the skill can't move, because a main-tree skill may not use a topic's words.
3. **Grammar sentences:** how many sentences contain its words and have a later grammar skill as their home. These sentences don't break. But a learner who skips the topic meets their words as unknown vocabulary (the gating cap), so grammar lessons get a little less variety. Fewer is better: under about 300 is fine, and `food` (1431) or `time` (3106) clearly stay.
4. **Stories:** which graded stories use its words. A story in a main-tree unit may only use words taught by then. A topic is outside that order, so such a story fails validation until it is changed.
5. **Validator:** every proposal below was applied in memory to the real sources (skills moved, item units moved, dependants re-pointed, nothing written) and run through `pack validate` with the topic rules.

The trial also changed one rule in the pipeline. A sentence that touches skills of several trees gets one home skill per tree, and it is valid when one of them allows its grammar (`features.SkillGraph.problems`). The app only shows such a sentence once the learner has started every skill it touches.

With a single home in course order, the moved skill came last. It then had to allow every later tense of the main tree, which produced about 1,600 false errors per course.

**Re-pointing.** A main-tree skill that required a moved skill now requires that skill's own main-tree requirements instead. So the chain of prerequisites stays as it was, minus the topic.

## Summary

| Course | Skills moved | Topics | Re-pointed main skills | Validator after the move | Stories to change |
| --- | --- | --- | --- | --- | --- |
| it | 16 of 43 vocab skills | 9 | 5 (`imperative`, `ci-ne`, `comparatives`, `congiuntivo`, `passato-remoto`) | 0 errors except stories | 16 stories |
| nl | 6 of 24 | 4 | 1 (`verleden-tijd-weak`) | 0 errors except stories | 5 stories |
| es | 6 of 24 | 4 | 4 (`work`, `feelings`, `preterito-perfecto`, `imperfecto`) | 0 errors except stories | 4 stories |

What stays in the main trees:

- the core vocabulary: greetings, little words, people, food and drink, numbers, time, home, family, everyday verbs;
- everything later grammar leans on heavily: the body, adverbs, colours, city, travel, work, feelings;
- the general vocabulary that doesn't form a theme: more verbs, ideas, opinions, adjectives, connectors, abstract words.

## Italian (it)

| Topic id | Title | Skills (unit now) | Anchor (default) | Grammar sentences | Notes |
| --- | --- | --- | --- | --- | --- |
| `cucina` | Food and cooking | `kitchen` (u5), `food-more` (u11) | `imperative` (u11) | 262 + 22 | `food` (u2) stays: 1431 grammar sentences, and `articles` requires it. `food-more` needs the imperative (recipes), so the branch grows at u11; see "Decisions" 1 |
| `natura` | Animals, weather and nature | `weather` (u7), `animals` (u7) | `passato-prossimo-essere` (u6) | 196 + 192 | `nature` (u13, 22 sentences) could join as a second unit, but it would move the anchor to `progressive` (u13) |
| `negozi` | Shopping and clothes | `clothes` (u7), `shopping` (u8) | `imperfetto` (u7) | 150 + 145 | |
| `tempo-libero` | Free time and media | `leisure` (u8), `media` (u11) | `imperative-irregular` (u11) | 371 + 72 | `leisure` is the most used of the moved skills |
| `servizi` | Health and services | `health` (u10), `services` (u10) | `reflexive-past` (u10) | 60 + 95 | `body` (u4, 502) stays. `imperative` no longer requires `health` |
| `in-giro` | Finding the way | `directions` (u11) | `imperative` (u11) | 98 | `city` (710) and `travel` (942) stay, and `prepositions` requires both |
| `societa` | Work, money and society | `society` (u13), `money` (u14) | `congiuntivo-imperfetto` (u14) | 29 + 34 | `work` (u6, 790) stays |
| `carattere` | Emotions and character | `emotions` (u12), `character` (u14) | `congiuntivo` (u14) | 102 + 34 | `feelings` (u6, 276) stays; it is borderline |
| `lettura` | Books and stories | `reading` (u15) | `passato-remoto-irregular` (u15) | 0 | Suits the coming book model |

**Can't move as is:**

- `crime` (u15): `passato-remoto-irregular` trains some of its verbs. It could move if those verbs get a main-tree unit.
- `routine` (u10): it belongs with the reflexive verbs, and `imperative` requires it.

**Re-pointed:**

- `imperative` → `[reflexive-past, reflexive-present, routine]`
- `ci-ne` → `[imperative-pronouns, imperative-irregular, imperative]`
- `comparatives` → `[combined-pronouns, condizionale-irregular, ci-ne, opinions, verbs-three]`
- `congiuntivo` → `[adjectives-more, nature, impersonal-si, abstract]`
- `passato-remoto` → `[congiuntivo, connectors, congiuntivo-imperfetto]`

**Stories that use moved words** (main-tree units):

- `u5-zuppa`: aglio, carote, cipolla, olio, pentola, zuppa…
- `u7-bambino` and `u7-pioggia`: clothes, weather and animals mixed
- `u8-concerto`, `u8-spesa`
- `u9-sogno`
- `u10-mattina` ("mal"), `u10-banca`
- `u11-stazione`, `u11-ricetta`
- `u12-regalo`, `u12-mare` ("estate")
- `u13-gita`, `u13-citta`
- `u14-colloquio`
- `u15-commissario`, `u15-favola`

Many need one or two words swapped, or declared as the story's single `new_words` entry. A few belong in the topic itself: `u5-zuppa` and `u11-ricetta` in `cucina`, `u10-banca` in `servizi`, `u15-favola` in `lettura`. See "Decisions" 3.

## Dutch (nl)

| Topic id | Title | Skills (unit now) | Anchor (default) | Grammar sentences | Notes |
| --- | --- | --- | --- | --- | --- |
| `keuken` | Food and cooking | `kitchen` (u6) | `possessives` (u5) | 63 | `food` (u2, 502) stays: `home` requires it, and `de-het` and `plurals` select its words |
| `winkelen` | Shopping and clothes | `shopping` (u6), `clothes` (u7) | `travel` (u6) | 53 + 28 | `verleden-tijd-weak` no longer requires `shopping` |
| `natuur` | Animals, weather and nature | `weather` (u7), `animals` (u7) | `travel` (u6) | 77 + 89 | Shares its anchor with `winkelen`, so the two branches alternate sides |
| `vrije-tijd` | Free time | `leisure` (u8) | `verleden-tijd-strong` (u7) | 0 | |

**Stay:**

- `body`: `diminutives` selects its words.
- `work` (424) and `feelings` (126): kept for now. `feelings` could join a later "people and feelings" topic.
- `city` and `travel`: they are the anchors, and the past tenses use them.

**Re-pointed:** `verleden-tijd-weak` → `[city, travel]`.

**Stories that use moved words:** `u6-markt`, `u7-storm`, `u7-dieren` (could move into `natuur`), `u8-concert`, `u8-droom`.

## Spanish (es)

| Topic id | Title | Skills (unit now) | Anchor (default) | Grammar sentences | Notes |
| --- | --- | --- | --- | --- | --- |
| `cocina` | Cooking and eating out | `kitchen` (u6) | `possessives` (u5) | 23 | `food` (u2, 1132) stays |
| `compras` | Shopping and clothes | `shopping` (u6), `clothes` (u6) | `reflexive` (u6) | 115 + 59 | |
| `naturaleza` | Animals, weather and nature | `weather` (u8), `animals` (u8) | `participles-irregular` (u7) | 103 + 73 | |
| `ocio` | Hobbies and culture | `leisure` (u8) | `participles-irregular` (u7) | 43 | Same anchor as `naturaleza`: one branch on each side |

**Re-pointed:**

- `work`, `feelings` and `preterito-perfecto` → `[reflexive, plurals, colours, possessives]`. These three used to require `clothes` and `kitchen`.
- `imperfecto` → `[indefinido-irregular, participles-irregular]`

**Stories that use moved words:** `u6-tienda`, `u8-tormenta`, `u8-gato`, `u9-planes` ("verano").

## Decisions for the owner

1. **Anchors that sit deep.** A topic whose skills come from different levels is anchored at the deepest requirement. Italian `cucina` would grow at u11 (`imperative`, because of `food-more`), although `kitchen` alone fits after u4. There are three options:
   - (a) accept a late branch; the topic can still be opened from the tree menu, and `kitchen` is available as soon as its own prerequisites are practised;
   - (b) split into two topics ("In the kitchen", "Cooking");
   - (c) a later format addition: per-unit anchors, so one topic shows two branches.

   (a) is what the format does today.
2. **Borderline skills.** Should these move: `leisure` (it, 371 grammar sentences), `feelings` (it 276, nl 126) and `work` (nl 424)? This proposal keeps `feelings` and `work`, and moves `leisure`.
3. **Stories.** A story can move into a topic unit when all its new words come from that one topic, for example `u7-dieren` (nl), `u5-zuppa` and `u11-ricetta` (it). The others need small rewrites. This is the main work of the split, and it needs `python -m pipeline stories <course>` to pass.
4. **`crime` (it).** Should the passato remoto verbs it introduces get a main-tree unit, so that crime can become a topic? It would pair naturally with a Montalbano book pack.

## How to apply it (once approved)

The split happens in tosk-data's `course.yaml` for each course:

1. Move the skills under `topics:`. The skill ids and their `requires` stay as they are.
2. Re-point the dependants listed above.
3. Point the lexicon `unit` of the moved skills' own words at the topic units. The importer does this when it re-resolves units (`importer.py` uses `all_units`).
4. Fix or move the stories listed above.
5. Bump the minor version of each pack (it 1.4.0 and so on).

The app needs no change for any of this.
