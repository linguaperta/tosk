# Pack format 1.2

*Status: **1.2**, 21 October 2026 (1.2 adds built-in topic trees, sections 3.3, 9, 13 and 16, amended before publication: a topic's anchor is its entry point and later topic skills may have late requirements; 1.1 added moods and recognition-only skills, sections 3, 12.5 and 15; everything of 1.0 is unchanged). Draft parts are marked **DRAFT**. Normative words (MUST, SHOULD, MAY) are used as in RFC 2119.*

A **language pack** is everything the app knows about one course: the words, their conjugation and inflection tables, example sentences with translations, grammar notes, the course structure (units, skills and their prerequisites), graded stories, and credits. The app is a player for packs; it contains no knowledge of any language. This document specifies the format so that anyone can make a pack, build it, and host it without reading the project's code.

There are three artefacts:

| Artefact | What it is | Specified in |
| --- | --- | --- |
| **Pack source** | a directory of YAML, JSON Lines and Markdown files that people edit | sections 2–11 |
| **Compiled pack** | one SQLite file, `{course_id}.sqlite`, that the app opens read-only | section 13 |
| **Catalog** | an `index.json` listing compiled packs and where to download them | section 14 |

The toolkit (`pack`, section 17) turns a source into a compiled pack (`pack build`), checks a source (`pack validate`), and writes catalogs (`pack index`). The normative machine-readable parts are `schema/course.schema.json`, `schema/lexicon.schema.json`, `schema/verbs.schema.json`, `schema/sentences.schema.json` (the source records) and `schema/course_db.sql` (the compiled pack). Where this document and those files disagree, the schema files win for structure and this document wins for meaning; disagreements are bugs and are listed in section 19.

Contents:

1. [Concepts](#1-concepts)
2. [Source layout](#2-source-layout)
3. [course.yaml](#3-courseyaml)
4. [Lexicon](#4-lexicon-lexiconjsonl)
5. [Verb tables](#5-verb-tables-verbsjsonl)
6. [Inflection tables](#6-inflection-tables)
7. [Sentences and tokens](#7-sentences-and-tokens-sentencesjsonl)
8. [Grammar notes](#8-grammar-notes-grammarmd)
9. [Stories](#9-stories-storiesyaml)
10. [Identifiers](#10-identifiers)
11. [Translations, provenance and credits](#11-translations-provenance-and-credits)
12. [Facets, skills and exercises; grammar gating](#12-facets-skills-and-exercises-grammar-gating)
13. [The compiled pack (course.sqlite)](#13-the-compiled-pack-coursesqlite)
14. [Catalogs (index.json)](#14-catalogs-indexjson)
15. [Versioning and compatibility](#15-versioning-and-compatibility)
16. [Validator rules](#16-validator-rules)
17. [Toolkit (`pack`) and what is generic](#17-toolkit-pack-and-what-is-generic)
18. [Worked example](#18-worked-example)
19. [Open issues](#19-open-issues)
20. [DRAFT: extension packs (v0.8)](#20-draft-extension-packs-v08)
- [Appendix A: source-specific importers](#appendix-a-source-specific-importers)

---

## 1. Concepts

- **Course id.** Identifies the pack. In format 1.0 it is the **target language code** (ISO 639-1 or 639-3, 2–3 lower-case letters: `it`, `nl`, `hns`) and MUST equal `target`. Two packs with the same id are versions of the same course.
- **Target language.** The language being learned (`target`).
- **Source languages** (`translations`). The learner's languages: every taught word has glosses, and every grammar note text exists, in these. The learner picks one; it is called the *source language* in the app.
- **Item.** One lexical unit (a word or a fixed phrase) with a part of speech, glosses, and optionally a verb table or inflection tables. Items with a `unit` are *taught*; items without one form the *distractor pool* (wrong options, alignment of sentence words).
- **Tree, topic.** (1.2) A course has a **main tree** (`units`) and optionally **topics** (`topics`): themed side trees, each with its own units and skills and drawn as its own map, attached to the main tree at an **anchor** skill (section 3.3).
- **Unit, skill.** A unit is a group of skills (a band on the course map). A skill is one node on the map: a lesson topic. Skills select their items with **queries**, resolved at build time.
- **Facet.** One thing a learner can know about an item, scheduled on its own by spaced repetition (FSRS): recognising a word, producing it, its forms in one tense, its article, one of its inflection tables. Progress is stored **per facet id**, so ids are permanent (section 10).
- **Feature.** A grammar construct a sentence uses (`tense:past`, `aux:essere`). Skills *introduce* features; the app only shows sentences whose features the learner has met (grammar gating, section 12.4).
- **Pack format version** (this document, 1.2), **compiled schema version** (`schema_version` 1, `schema_minor` 3), **catalog version** (`index_version` 1) and **pack version** (the content's own semver, `version`) are four different numbers; section 15.

## 2. Source layout

A pack source is one directory. Its name does not matter; the course id comes from `course.yaml`.

```
{pack}/
  course.yaml              REQUIRED  course definition (section 3)
  ids.tsv                  SHOULD    item id registry, append-only (section 10.2)
  lexicon/*.jsonl          REQUIRED  items, one JSON object per line (section 4)
  verbs/*.jsonl            optional  verb tables (section 5)
  sentences/*.jsonl        optional  example sentences with aligned tokens (section 7)
  grammar/{skill}.md       optional  grammar notes, English; grammar/{skill}.{lang}.md other languages (section 8)
  stories/*.yaml           optional  graded stories (section 9; needs pipeline language rules)
  sentence_ids.tsv         optional  registry of generated sentence ids (section 10.3)
  seed.yaml, README.md ... ignored   other top-level files: importer input, notes for the authors
```

- Every `*.jsonl` file directly in `lexicon/`, `verbs/` and `sentences/` is read, in file-name order. **File names carry no meaning**: the official packs group records by unit (`u1.jsonl`, `pool.jsonl`, `gen-u3.jsonl`) for readability only; the record's own `unit` field is what counts.
- JSONL files are UTF-8, one JSON object per non-empty line, `\n` line ends. Tools SHOULD write them with `", "` / `": "` separators and unescaped non-ASCII so diffs stay readable.
- `course.yaml` and story files are YAML 1.1 as read by PyYAML `safe_load` (quote `"no"`, `"yes"`, `"on"`, `"off"` when they are words).
- Other files (`seed.yaml`, `SOURCES.md`, a README) are ignored by the format. `seed.yaml` is the input of the project's own importers (pipeline/README.md), not part of the format.

## 3. course.yaml

Schema: `schema/course.schema.json` (unknown keys are errors). Top level:

| Key | Req. | Type | Meaning |
| --- | --- | --- | --- |
| `id` | yes | `^[a-z]{2,3}$` | course id (section 1) |
| `version` | yes | semver `X.Y.Z` | the pack's content version (section 15.3) |
| `title` | yes | i18n | course name, e.g. `{en: Italian, nl: Italiaans}` |
| `description` | no | i18n | one or two sentences for the course picker |
| `target` | yes | `^[a-z]{2,3}$` | target language code; MUST equal `id` in 1.0 |
| `translations` | yes | list of codes | source languages, in order of preference; at least one |
| `required_translations` | no | list of codes | (1.1) the `translations` every taught item, sentence, story and grammar check needs; the others are optional: used and checked where present, and the app falls back to English where one is missing. Default: all of `translations` |
| `unverified` | no | bool | true while no speaker has checked the content (the app says so); default false |
| `note_langs` | no | list of codes | languages every grammar skill needs a note in; default: see section 19 (intended: `translations`) |
| `min_app_version` | no | semver | oldest app that can use the pack (section 15.4) |
| `license` | no | string | licence of the content: an SPDX id (`CC-BY-SA-4.0`, `CC0-1.0`) or `LicenseRef-…` (section 11.3) |
| `authors` | no | list | names, or `{name, role?, url?, email?}` |
| `data_sources` | no | list | `{title, id?, author?, url?, license?, note?}` per source used |
| `attribution` | no | string | the attribution text shown in the app; default generated (section 11.3) |
| `persons` | yes | list of keys | person keys of verb tables in display order (`[io, tu, lui/lei, noi, voi, loro]`); no dots or spaces |
| `person_labels` | no | {person: i18n} | how to show a person key that is not self-explanatory |
| `tenses` | yes | list of keys | tense keys (`^[a-z][a-z0-9_]*$`) in display order |
| `tense_labels` | no | {tense: i18n} | names of the tenses in the source languages; SHOULD cover every tense |
| `tense_persons` | no | {tense: [person, …]} | (1.1) tenses whose tables have only some persons (an imperative without `io`); a table of such a tense is complete with these persons |
| `tense_person_labels` | no | {tense: {person: i18n}} | (1.1) person labels that differ in one tense (the Italian imperative's `lui/lei` row is the formal `Lei (you, formal)`). Persons whose labels in a tense share a word in parentheses (`tu (you)`, `Lei (you, formal)`) are interchangeable for the app's wrong options in that tense: an imperative names no subject |
| `tense_groups` | no | {tense: group} | (1.1) the transform exercise changes the tense only between tenses of one group (a mood); unlisted tenses form one default group. Put each mood whose tenses cannot replace each other in its own group (Italian: the indicative tenses unlisted, `condizionale`, each subjunctive tense and `imperativo` apart) |
| `articles` | no | list | the article strings offered in article exercises (`[il, lo, la, "l'"]`, `[de, het]`) |
| `inflection_tables` | no | {table: spec} | non-verb inflection tables (section 6) |
| `base_features` | no | list of features | grammar features allowed from the start; **declaring the key turns grammar gating on** (section 12.4) |
| `feature_detectors` | no | {feature: detector} | how the pipeline finds construct features in sentences (section 12.4) |
| `time_adverbs` | no | {adverb: [tense, …]} | adverbs (one or more words) and the tenses they fit; the transform exercise never moves a sentence containing one into another tense |
| `units` | yes | list of units | the course (its main tree), in order |
| `topics` | no | list of topics | (1.2) built-in topic trees (section 3.3) |

An **i18n** value is a mapping from language code to a non-empty string: `{en: "Greetings", nl: "Begroetingen"}`. Apps fall back to English, then to any language present.

### 3.1 Units

| Key | Req. | Meaning |
| --- | --- | --- |
| `id` | yes | `^[a-z0-9][a-z0-9_-]*$`, unique in the course (`u1`) |
| `title` | yes | i18n |
| `skills` | yes | list of skills, at least one, in map order |

### 3.2 Skills

| Key | Req. | Meaning |
| --- | --- | --- |
| `id` | yes | `^[a-z0-9][a-z0-9_-]*$`, unique in the course (not only the unit) |
| `kind` | yes | `vocab` or `grammar`. Grammar skills need grammar notes, get a stricter unknown-word cap in sentences, and are the only ones that may use `verbs` |
| `title` | yes | i18n |
| `icon` | no | icon key; unknown keys get a default icon. Known: `wave greetings hello food drink family people person home house city travel time clock calendar number numbers color colors animal animals work school body clothes weather nature shopping question search investigation verb verbs conjugation past future article articles grammar book star chat`; apps after 0.7.4 also know `health heart music money society` (older apps show the default icon) |
| `requires` | no | skill ids that are prerequisites (a DAG). A skill is *available* on the map once every prerequisite has at least one practised facet; prerequisites also widen what grammar the skill's sentences may use (section 12.4) |
| `introduces` | no | grammar features this skill teaches (a `verbs` skill also introduces `tense:{T}` by itself) |
| `items` | one of | an items query (below): the skill trains items |
| `verbs` | one of | a verbs query (below): the skill trains one tense of verbs; `kind` MUST be `grammar` |
| `facet` | no | `article`: train `#article` of the selected nouns instead of `#rec`/`#prod`; `infl`: train only `#infl:{table}` of `inflections`. SHOULD only be used with `kind: grammar` (section 19) |
| `inflections` | no | `{table: T}` or `{table: [T1, T2]}`: train `#infl:T` of the selected items that inflect (section 6) |
| `exercises` | no | allowed exercise type ids (section 12.3); empty or absent = all that apply |
| `pos` | no | `{x: int, y: int}`: a layout override for the map (column, row) |
| `note` | no | path of the English grammar note relative to the pack, instead of `grammar/{id}.md` (section 8) |
| `recognition` | no | (1.1) `true`: a **recognition-only** skill: the learner recognises its words or forms and is never asked to produce them (section 12.5). Not with `facet` |
| `equivalent_tense` | no | (1.1) a recognition verbs skill: the tense whose form of the same verb and person means the same (`passato_remoto` → `passato_prossimo`), offered as "which form means the same?" |

Exactly one of `items` and `verbs` is present.

**Items query** (`items:`), all keys optional, combined with AND:

| Key | Meaning |
| --- | --- |
| `tags` | tag or list: the item has any of these tags |
| `pos` | part of speech or list |
| `lemmas` | explicit lemmas or item ids; without `top`, the list's order is the introduction order |
| `exclude` | lemmas or ids to leave out |
| `top` | keep the N most frequent (after the order below) |
| `min` | the validator's minimum number of selected items (default `min(5, top)`) |

With `facet: article` only items with an `article` qualify; with `facet: infl` only items whose every listed table has at least two different forms.

**Verbs query** (`verbs:`): `tense` (required, one of `tenses`) selects verb items whose table for that tense is **complete** (a form for every person, or every person of `tense_persons`). Optional: `class` (verb class or list), `tags`, `regular` (true: the tense is not in the verb's `irregular_in`; false: it is), `aux` (the verb's primary auxiliary, the first of `auxiliary`), `lemmas`, `exclude`, `top`, `min` (default: `len(lemmas)`, else `min(15, top)`).

**Order.** Selected items are introduced by frequency rank (`freq` ascending, items without `freq` last, then by id), except an explicit `lemmas` list without `top`, which keeps its own order. The order becomes `skill_items.ord` and `skill_facets.ord`.

The query is resolved **at build time**: the compiled pack lists each skill's items and facets, and the app never interprets queries.

### 3.3 Topics (1.2)

A **topic** is a themed set of skills (food and cooking, travel, work, football) that is not part of the course's main line. It has its own units and skills and the app draws it as its own map; on the main tree a side branch grows off the topic's **anchor** skill with the topic's name carved into the bark and a "Go to …" button. Topics share everything with the main tree: item ids (one progress per word), grammar notes, gating, XP and level. Words the learner already knows from the main tree or another topic count as known (lessons don't introduce them again).

```yaml
topics:
  - id: cucina                       # ^[a-z0-9][a-z0-9_-]*$, unique among the topics
    title: {en: "Food and cooking", nl: "Eten en koken"}
    short_title: {en: "Food", nl: "Eten"}   # optional: for the carving when the title doesn't fit
    icon: food                       # optional, the skill icon keys
    anchor: food-basics              # optional: default the first skill's deepest main-tree requirement
    units:                           # units and skills exactly as in `units` (sections 3.1, 3.2)
      - id: cucina-u1
        title: {en: "In the kitchen"}
        skills:
          - id: cucina-1             # the first skill: where the topic starts
            kind: vocab
            title: {en: "Cooking"}
            requires: [food-basics]  # main-tree skills and earlier skills of this topic
            items: {tags: [cooking]}
          - id: cucina-2
            kind: vocab
            title: {en: "Recipes"}
            requires: [cucina-1, imperative]   # a later main-tree skill: a late requirement
            items: {tags: [recipes]}
```

| Key | Req. | Meaning |
| --- | --- | --- |
| `id` | yes | the topic id, unique among the course's topics |
| `title` | yes | i18n |
| `short_title` | no | i18n; the app carves it on the branch when `title` is too long (default: the title's first word) |
| `description` | no | i18n |
| `icon` | no | icon key (section 3.2) |
| `anchor` | no | the main-tree skill the topic's branch grows from: the topic's **entry point**, the last main-tree skill its **first skill** (the first unit's first skill) requires. Default: the deepest of the main-tree skills the first skill requires (longest prerequisite path; ties: the later in course order) |
| `units` | yes | the topic's units, at least one |

Rules:

- **Course order** is the main tree's units, then each topic's units in `topics` order. So a facet shared with the main tree is introduced by its main-tree skill, and unit and skill ids are unique over every tree.
- **Requirements.** A topic skill may require main-tree skills and skills of its own topic; never another topic's. A main-tree skill never requires a topic skill. Every main-tree skill the topic's first skill requires is the anchor, a prerequisite of it, or a sibling no deeper than it (the anchor is the last one: `kitchen` may require both `colours` and `possessives`).
- **Late requirements.** A later skill of the topic may require main-tree skills that come after the anchor (`cucina-2` needs the imperative: a recipe is written in it). The topic opens at its anchor, and such a skill stays locked until those main-tree skills are started; the app says so on its node and in its sheet ("needs The imperative · unit 11", which leads there).
- **Words.** A topic skill may select items of the main tree, of its own topic (a unit no later than the skill's) and of other topics (a word two topics share is one item with one progress). An item whose `unit` is a topic unit is introduced by that topic; **a main-tree skill MUST NOT select it** (the main tree cannot need words of a side tree). Moving a main-tree vocab skill into a topic keeps its ids, so progress is kept.
- **Unlocking.** A topic skill is available like any skill (every prerequisite started); the app shows the branch and the topic as locked until the anchor is started, and the topic can be browsed before. A locked topic skill names the main-tree skill it waits for (the anchor, or a late requirement).
- **Grammar** comes from the main tree: gating, the home-skill rule and notes work unchanged across trees (a topic skill's prerequisites include its main-tree requirements, late ones too).
- **Stories** (section 9) may belong to a topic unit. Such a story may use the words of its topic up to its unit and the main tree's words and grammar up to the last main-tree unit that the topic's skills up to its unit require (anchor and late requirements alike).
- **The fairness rule** (docs/extensions.md): never unknown grammar, some unknown words are fine. A learner may skip any topic, so a topic's words count as unknown vocabulary for them: they may appear in main-tree sentences (the app's unknown-word cap applies: one per sentence in a grammar lesson, two otherwise) and in stories of other trees, at most three distinct ones per story besides its one new word (glossed before the story with it). Grammar is gated strictly everywhere. The build checks that every main-tree grammar skill keeps its sentence floor for a learner who skipped every topic (section 16, rule 14c).
- **Separately installed topics** (an extension pack with `extends`) are not part of 1.2 (section 20); built-in and installed topics will behave the same in the app.

## 4. Lexicon (`lexicon/*.jsonl`)

One item per line. Schema: `schema/lexicon.schema.json`.

| Field | Req. | Compiled | Meaning |
| --- | --- | --- | --- |
| `id` | yes | `items.id` | `{course}:{lemma}` or `{course}:{lemma}.{n}`; permanent (section 10) |
| `lemma` | yes | yes | citation form (infinitive, singular, masculine singular, …) |
| `pos` | yes | yes | `noun verb adj adv pron det prep conj num intj phrase particle` |
| `tr` | yes | yes | glosses per source language, primary first: `{"en": ["to eat"], "nl": ["eten"]}` |
| `tr_src` | no | no | provenance of the glosses per language (section 11.2) |
| `unit` | no | `items.unit_id` | unit that introduces the item; absent or null = distractor pool |
| `freq` | no | yes | frequency rank, 1 = most frequent |
| `article` | no | yes | a noun's definite article (`il`, `l'`, `de`, `het`); used by article skills, flashcards (`il ragazzo`) and the article exercise |
| `gender` | no | yes | `m`, `f`, `n`, `c`, or two joined by `|` (`m|f`) |
| `plural` | no | yes | a noun's plural (shown, and used as a wrong option in cloze) |
| `tags` | no | yes | lower-case tags (`[a-z0-9_-]+`) used by skill queries |
| `variants` | no | yes | accepted alternative spellings of the lemma |
| `infl` | no | `inflections` | inflection tables (section 6) |
| `inflections` | no | no | inflected forms (plural, feminine, …) used only by the aligner |
| `uncountable` | no | no | a mass noun: no plural, no number table |
| `class` | no | no | the verb class (also in the verb record) |
| `src` | no | no | provenance of the word, `; `-separated tags (section 11.2) |

Every item with a `unit` MUST have glosses in every required translation language (`required_translations`, default all `translations`). Pool items SHOULD (where a gloss in the learner's language is missing, the app falls back to English, then to any language; wrong options of a multiple choice or match are then taken in the same language as the right one).

## 5. Verb tables (`verbs/*.jsonl`)

One record per verb item (an item with `pos: verb`). Schema: `schema/verbs.schema.json`.

| Field | Req. | Meaning |
| --- | --- | --- |
| `id` | yes | the verb's item id |
| `forms` | yes | `{tense: {person: form}}` |
| `class` | no | course-defined class (`are`, `ere`, `ire`, `isc`; `weak`, `strong`, `mixed`); used by queries and wrong options |
| `stem` | no | citation stem (`mang`) |
| `irregular` | no | bool |
| `irregular_in` | no | tenses whose forms deviate from the regular pattern (queries `regular:`, detector `irregular_tense`; not compiled) |
| `auxiliary` | no | perfect auxiliary lemma(s), primary first, joined with `|` (`avere`, `hebben|zijn`) |
| `src` | no | provenance of the table (not compiled) |

- Tenses are keys of `tenses`, or the non-finite `infinitive`, `participle`, `gerund`, which use the single person `_`.
- A form is a string, or an object `{form, stem?, ending?, alts?, src?}`: `stem` and `ending` are both set or both absent, and `stem + ending == form` (the ending may be empty: Dutch `ik werk` = `werk` + `''`). Only cells with a split can be asked in the *pick the ending* exercise. `alts` are accepted alternative forms, e.g. gendered ones: `{"form": "sono stato", "alts": ["sono stata"]}`.
- A **compound form** is written in full (`ho mangiato`, `heb gegeten`, `kare hai`).
- A grammar skill for tense T only selects verbs with a form for **every** person in T.

## 6. Inflection tables

Verbs have conjugation tables; any other part of speech can have **inflection tables**: a noun's number, an adjective's agreement, a diminutive, cases. Declare them in `course.yaml`:

```yaml
inflection_tables:
  number:                       # table name: [a-z][a-z0-9_]*
    title: {en: singular and plural}
    pos: [noun]                 # parts of speech that can have it
    cells: [sg, pl]             # cell keys in display order: [a-z0-9_]+ joined by dots (m.sg)
    base: sg                    # the cell equal to the lemma: given, never asked
    agreement: false            # true: the cell follows from the sentence (an adjective agreeing with its noun)
    labels: {sg: {en: singular}, pl: {en: plural}}
```

and fill them per item in the lexicon record:

```json
"infl": {"number": {"sg": {"form": "gatto", "stem": "gatt", "ending": "o"},
                    "pl": {"form": "gatti", "stem": "gatt", "ending": "i", "wrong": ["gattoi"]}}}
```

- An item's table has **exactly** the declared cells, and its `pos` is one of the table's `pos`.
- Per cell: `form` (required), `stem` + `ending` (both or neither, concatenating to `form`), `alts` (accepted alternatives, never repeating `form`), `wrong` (plausible learner errors that are **no word of the language**: `katen`, `huisen`, `gattoi`; never a form of the same table).
- **Meaning:** for a table with `agreement: true`, in an aligned sentence every other cell of the item is a wrong answer (the sentence decides). Otherwise the cells differ in meaning (`gatto` vs `gatti` can both be right against a sentence), so sentence exercises only offer the cell's `wrong` forms.
- An item **inflects** in a table when the table has at least two different forms; only those items get an `#infl` facet (invariable `città` does not).
- Train tables with a skill's `inflections: {table: T}`: with `facet: infl` the skill trains only `#infl:T`, otherwise `#rec` + `#prod` + `#infl:T`.

## 7. Sentences and tokens (`sentences/*.jsonl`)

One sentence per line. Schema: `schema/sentences.schema.json`.

| Field | Req. | Compiled | Meaning |
| --- | --- | --- | --- |
| `id` | yes | yes | `{prefix}:{rest}` (section 10.3) |
| `text` | yes | yes | the target-language sentence |
| `tr` | yes | yes | translations, `{lang: string}`, at least one; SHOULD cover every `translations` language |
| `tr_src` | no | no | provenance per translation (`tatoeba:1234`, `claude-gen`, `manual`) |
| `src` | no | `sentences.src` | provenance of the sentence (`tatoeba:4821`, `claude-gen (present-are: parlare)`) |
| `unit` | no | `sentences.unit_id` | the latest unit of the taught items it touches (informational) |
| `tokens` | yes | `tokens` | the tokenisation, below |

**Tokens.** A list of `{t, pre?, is_word?, lex?, form?}`:

- `t`: the surface text of the token. Words and punctuation are separate tokens. `pre`: the whitespace before it (default `''`). Concatenating `pre + t` over all tokens MUST give `text` exactly.
- `is_word`: false for punctuation (default true).
- `lex`: the item id the word belongs to (*alignment*). Optional, but unaligned words are treated as unknown vocabulary (two unknown words) unless they look like a name or a number, so a sentence with unaligned words is rarely shown.
- `form` (requires `lex`): which cell of the item the token is:
  - `'{tense}.{person}'` for a verb form, e.g. `presente.noi`, `participle._`. The cell MUST exist in the verb's table.
  - `'infl:{table}.{cell}'` for an inflected non-verb, e.g. `infl:number.pl`, `infl:agreement.f.sg` (the cell is everything after the first dot). The cell MUST exist and the token text MUST be one of its accepted forms (case-insensitive).
  - absent when unknown or ambiguous (a token whose person cannot be decided keeps its `lex` and gets no `form`).
- **Multi-word verb forms** are aligned in one of two ways, and the app understands both:
  1. *Auxiliary + participle* (Italian, Dutch): the participle token gets the compound cell (`mangiato` → `passato_prossimo.noi`, whose table form is `abbiamo mangiato`); the auxiliary token is aligned to the auxiliary verb's present (`abbiamo` → `avere`, `presente.noi`). The app treats such an auxiliary as part of the compound form, never as an occurrence of the auxiliary's own present.
  2. *Every word* of the form gets the same `lex` and `form` (Sarnami `kare hai`: both words → `kare`, `present.oe`; Italian pronominal verbs: `mi alzo` → `alzarsi`, `presente.io`, and all three words of `mi sono alzato` → `alzarsi`, `passato_prossimo.io`).
- A word whose text is no accepted form of its cell (a form with attached pronouns: Italian `dimmi` → `dire`, `imperativo.tu`; `parlarmi` → `parlare`, `infinitive._`) is valid: the app glosses it, tags its grammar, and never asks it in an exercise.

The app also derives which grammar features each sentence uses (section 12.4); the compiled pack stores them, the source does not.

## 8. Grammar notes (`grammar/*.md`)

Markdown, one file per (skill, language): `grammar/{skill}.md` is English, `grammar/{skill}.{lang}.md` is the note in `lang` (`present-are.nl.md`). A skill's `note:` key may instead point at the English file anywhere in the pack (its Dutch note is the same path ending in `.nl.md`; see section 19). Every **grammar** skill MUST have a non-empty note in every `note_langs` language. Vocab skills MAY have notes. The app shows the note in the learner's source language, falling back to English, then to any language. Notes SHOULD be short (one screen), use tables for paradigms, and give examples in the target language in *italics*.

## 9. Stories (`stories/*.yaml`)

Graded reading per unit: 2–3 short stories per unit that use only what the learner has met by the end of that unit, with comprehension questions. Each file holds a YAML list of stories (files are read in the order of the first number in their name, `u1.yaml`, `u2.yaml`, …; the story's `unit` decides).

```yaml
- id: u1-bar                      # permanent, unique in the course
  unit: u1                        # the unit whose vocabulary and grammar it uses (and that unlocks it)
  title: {it: "Al bar", en: "At the bar", nl: "In de bar"}   # target language + every required translation (1.1)
  new_words: [cameriere]          # at most one lemma taught after the unit, glossed in the reader
  names: [Bella]                  # extra names the story may use
  sentences:                      # 5-10 sentences of at most 14 words
    - {it: "Marco è al bar.", en: "Marco is at the bar.", nl: "Marco is in de bar."}
  questions:                      # 3-5 questions
    - q: {en: "Where is Marco?", nl: "Waar is Marco?"}   # the question in every source language
      prompt: "Dove è Marco?"                            # optional: the question in the target language
      options: ["al bar", "a casa", "a scuola"]          # 3-4 target-language strings, or i18n objects
      answer: 0                                          # index of the correct option
      why: {en: "Sentence 1.", nl: "Zin 1."}             # optional explanation
```

At build time every text is tokenised and aligned with the **pipeline's language rules** for the course; every word must be aligned to an item taught by the story's unit (or be its one new word, a name or a number), and its grammar features must be allowed at the unit. (1.2) A story of a topic unit counts as taught what its topic teaches up to its unit, plus the main tree up to the last main-tree unit the topic's skills so far require (section 3.3). Under the fairness rule (section 3.3) a story may also use up to three words of topics outside its own tree; they need no declaration and are compiled into `new_words` with the new word, so the app glosses them before the story. Story sentences are compiled into `sentences`/`tokens` with ids `st:{storyId}.{n}` and `src: claude-gen (story: {storyId})` (the build labels every story as Claude-written; open issue 20); the app keeps them out of the exercise pool. **Stories therefore need a language the pipeline supports** (section 17.2); a pack in another language cannot have stories yet (the validator says so).

## 10. Identifiers

### 10.1 Rules for all ids

- Ids are **permanent**. Progress (the review log, FSRS states, mistakes) is keyed by facet id, which contains the item id, so renaming an id loses the learner's progress on it. A new pack version MUST keep every item id of the previous version that still exists, MUST NOT give an id to a different word, and MUST NOT reuse the id of a removed word.
- Item ids, sentence ids and facet ids never contain whitespace or `#`. Unit and skill ids are `^[a-z0-9][a-z0-9_-]*$`.
- Ids starting with `{course}:story:` are reserved (the app's story pseudo-facets are `{course}:story:{storyId}#story`).

### 10.2 Item ids and `ids.tsv`

- Item id: `{course}:{lemma}` with spaces in the lemma replaced by `_` (`it:per_favore`). A homograph that needs its own entry (in practice: another part of speech) gets `{course}:{lemma}.{n}` with `n = 2, 3, …` (`it:arrivederci.2`). The suffix carries no meaning; which homograph gets the plain id is decided once (the official importers give it to the most frequent) and then never changes.
- `ids.tsv` is the registry: a header `id	lemma	pos	sense_key` and one tab-separated row per id ever assigned. `sense_key` distinguishes entries with the same lemma (in the official packs it is the POS). Tools assign ids through it: a (lemma, sense_key) pair always gets back the id it had, and **rows are never removed**, also after the word leaves the pack. When the file exists, every lexicon item MUST be listed with the same lemma and POS.
- Ids are unique within the pack and MUST start with `{course}:`.

### 10.3 Sentence ids

`{prefix}:{rest}` (`^[a-z]+:\S+$`). Registered prefixes:

| Prefix | Use |
| --- | --- |
| `s:{n}` | Tatoeba sentence n (`src: tatoeba:{n}`) |
| `g:{course}:{n}` | generated sentences, numbered through `sentence_ids.tsv` (`id	key`, key = the normalised text, append-only) |
| `st:{storyId}.{n}` | story sentences (written by the build, never in `sentences/`) |
| `ex:`, `x:`, or a source's own prefix (`gen:`, `{sourceId}:`) | other sources |

Sentence ids SHOULD be stable (the app remembers recently shown sentences and flagged exercises by id), but no progress depends on them.

### 10.4 Facet ids

| Facet id | Kind | Trains |
| --- | --- | --- |
| `{itemId}#rec` | `rec` | recognise: target → meaning |
| `{itemId}#prod` | `prod` | produce: meaning → target |
| `{itemId}#form:{tense}` | `form` | a verb's forms in one tense |
| `{itemId}#article` | `article` | a noun's article (gender) |
| `{itemId}#infl:{table}` | `infl` | one inflection table of a non-verb (schema minor 1) |

A facet may belong to several skills; practice counts everywhere. Skill-level progress records are keyed `{course}/{skillId}`.

## 11. Translations, provenance and credits

### 11.1 Translations and pivots

- `translations` lists the source languages the pack supports. Each taught item has at least one gloss per language; the first is the **primary gloss** (shown on flashcards and as the right answer); the others are accepted meanings and keep wrong options away (a meaning of any synonym is never offered as wrong).
- Sentences have at least one translation and SHOULD have one per source language.
- A **pivot** gloss is one obtained through a third language (Dutch glosses of an Italian word via the English Wiktionary translation tables). Pivots are less reliable and MUST be labelled in `tr_src` (`wiktionary-pivot`).
- Grammar notes exist per `note_langs`; the app falls back to English.

### 11.2 Provenance (`src`, `tr_src`)

Every record SHOULD say where it comes from. A provenance value is one or more **tags** joined by `; `; a tag is `{source}` optionally followed by `:{locator}` and/or ` ({detail})`: `tatoeba:4821`, `claude-gen (present-are: parlare)`, `my-dict:a.html#aan; my-wordlist`.

| Where | Field | Compiled |
| --- | --- | --- |
| lexicon | `src` (the word), `tr_src.{lang}` (the glosses) | no |
| verbs | `src` (the table), `forms.{t}.{p}.src` (a cell) | no |
| sentences | `src` (the sentence), `tr_src.{lang}` (each translation) | `sentences.src` only |
| stories | (implicit) | `stories.src`, story `sentences.src` |

Registered source tags:

| Tag | Meaning |
| --- | --- |
| `wiktionary`, `nlwiktionary` | English / Dutch Wiktionary via kaikki.org (CC BY-SA) |
| `wiktionary-pivot` | gloss through the English Wiktionary translation tables (a pivot) |
| `tatoeba:{n}` | Tatoeba sentence n (CC BY 2.0 FR) |
| `manual` | written by a person for this pack |
| `claude` | glosses curated by Claude (Anthropic) in the course's seed file (the oldest tag; means the same as `claude-draft`) |
| `claude-draft` | drafted by Claude to be checked: tables, glosses, notes, course structure |
| `claude-gen` | generated by Claude: example sentences, stories, their translations |
| `pack-template` | example content of the `pack new` starter (replace it) |
| others | a pack's own sources, listed in `data_sources` with the same `id` (e.g. `my-dict`, `my-grammar-1985`) |

**AI-made content MUST be labelled.** Anything written or drafted by an AI model carries a tag starting with `claude` (for Claude): `claude-gen` for generated text, `claude-draft` for drafts of data. The app ranks sentences whose `src` starts with `claude-gen` after real ones of the same difficulty. Other AI systems: section 19.

### 11.3 Licence, attribution and authors

`course.yaml` MAY declare (compiled into `meta`, shown with the course):

```yaml
license: CC-BY-SA-4.0                  # SPDX id of the content licence, or LicenseRef-personal-use etc.
authors:
  - {name: Ada Lovelace, role: author, url: "https://example.org"}
  - Charles Babbage                    # a plain name is fine
data_sources:
  - {id: tatoeba, title: Tatoeba, url: "https://tatoeba.org", license: CC-BY-2.0-FR}
  - {id: claude-gen, title: "Sentences generated with Claude (Anthropic)", license: CC-BY-SA-4.0}
attribution: |                         # optional; generated from the three keys above when absent
  ...
```

- `meta.license` is the string, `meta.authors` a JSON array of `{name, role?, url?, email?}` (plain names become `{name}`), `meta.data_sources` a JSON array. `meta.attribution` is always present: `attribution` from course.yaml, else generated from `license`/`authors`/`data_sources`, else (packs that declare none of them) the official tosk-data text.
- A pack without `license` has **no declared licence**; tools show "not declared" and nobody should redistribute it.
- The licence MUST permit what the content's sources permit: a pack built from CC BY-SA sources is CC BY-SA; one built from an all-rights-reserved book is for personal use only (`LicenseRef-personal-use`) and stays local.
- **Hosting policy** of the official catalog: only packs whose licence allows redistribution (open licences) are hosted. Anyone may host their own catalog (section 14) or share a file. What people build and load for personal use is their own business; the app plays packs and shows their licence, sources and authors, it does not police them.

## 12. Facets, skills and exercises; grammar gating

### 12.1 Which facets a skill trains

Decided at build time and stored in `skill_facets`:

| Skill | Facets of each selected item |
| --- | --- |
| `items:` (vocab or grammar), no `facet` | `#rec`, `#prod`; plus `#infl:T` for each `inflections` table T the item inflects in |
| `verbs: {tense: T}` | `#form:T` (recognition belongs to vocab skills; no `#rec` is added) |
| `items:` + `facet: article` | `#article` |
| `items:` + `facet: infl` + `inflections: {table: T}` | `#infl:T` |
| `items:` + `recognition: true` (1.1) | `#rec` only |

### 12.2 What the app needs for each facet

| Facet | Exercises (type ids) | Data they use |
| --- | --- | --- |
| `#rec` | `flashcard`, `multiple_choice` (word or sentence → meaning), `match_pairs`, `listen_pick` | glosses; other items of the same POS as wrong meanings; sentences aligned to the item; a TTS voice for `target` |
| `#prod` | `flashcard`, `multiple_choice` (meaning → word, translation → sentence), `sentence_builder`, `cloze` | lemma, `article`, `plural`, `variants`; aligned sentences |
| `#form:{T}` | `conj_pick`, `conj_grid`, `cloze`, `spot_error`, `transform` | the verb table (stem/ending splits for `conj_pick`), other verbs of the class, aligned sentences with `form`, `time_adverbs`, `person_labels`, `tense_labels` |
| `#article` | `multiple_choice` (`___ noun` over `meta.articles`), `cloze`, `spot_error` | `article`, `articles`, sentences with the aligned article |
| `#infl:{table}` | `conj_pick` (an ending), `conj_grid` (tables of 3+ cells), `cloze`, `spot_error` | the table (stem/ending, `wrong`), labels, sentences with `infl:` forms |

- A facet's stage (fresh, learning, stable) picks the type: fresh facets get flashcards, choices and picks; stable ones get the sentence builder, cloze, transform, spot the error. An exercise that has no data (no aligned sentence, no stem/ending split) is skipped and another type is used, so **facets work without sentences**: `#rec`/`#prod` need glosses, `#form` a complete table, `#article` the `articles` list, and `#infl` stem/ending splits on its non-base cells (a 2-cell table has no grid). Sentences make the exercises much richer.
- Wrong options never equal an accepted answer (case, punctuation and accents folded) and never repeat. The engine's full rules are in docs/engine.md.

### 12.3 Exercise type ids

`flashcard`, `multiple_choice`, `match_pairs`, `conj_pick`, `conj_grid`, `sentence_builder`, `cloze`, `spot_error`, `transform`, `listen_pick` (since app 0.5; generated only when the device has a voice for `target`). A skill's `exercises` list restricts lessons to those types (the lab ignores it).

### 12.4 Grammar gating

The rule: a learner never meets a grammar construct in exercises before starting the skill that teaches it.

- **Features** are strings `name` or `name:value` (`^[a-z][a-z0-9_]*(:[a-z][a-z0-9_]*)?$`). `tense:{T}` exists for every tense; constructs are declared by the course (`aux:essere`, `modal`, `prep:articulated`, `separable`, `irregular:futuro`).
- **Skills introduce** their `introduces` list, and a `verbs: {tense: T}` skill also `tense:T`. `base_features` are allowed from the start (an empty list gates everything). A pack without the `base_features` key is not gated.
- **Sentence features** are computed by the build from the tokens: `tense:{T}` for every verb token in tense T (a compound form tags its compound tense, and its auxiliary is not counted as present), plus the course's detectors:

  | Detector `type` | Keys | Tags a sentence that has |
  | --- | --- | --- |
  | `words` | `words: [...]` | any of these words (lower case), except tokens aligned to a verb form |
  | `irregular_tense` | `tense: T` | a form of tense T of a verb with T in `irregular_in` |
  | `compound_aux` | `aux: lemma` | a compound form whose auxiliary is that verb (language rules) |
  | `modal_infinitive` | `verbs: [...]`, `infinitive_pattern: regex` | a finite form of one of the verbs plus a later infinitive |
  | `separable` | `particles: [...]` | a separable verb (Dutch `sta op`, `komt … terug`) |
  | `reflexive` | `pronouns: {pron: person(s)}`, `clitics`, `enclitic_any`, `unbound`, `verbs` | a pronoun of the verb's own person in the clitic cluster before a finite verb (`me levanto`, `mi alzo`); `unbound: true` (1.1): only pronouns that are no part of the verb's own pronominal form (impersonal `si dice`); `verbs` (1.1): only these verbs (lemmas) |
  | `nonfinite` | `form`, `pattern` | a verb token in that non-finite form (`gerund`: `sto mangiando`), or a word matching the pattern |
  | `pattern` | `pattern: regex` | (1.1) the regex is found in the sentence text (lower case, apostrophes normalized): comparatives `più \w+ (di\|che)`, superlatives `\w+issimo` |
  | `enclitic` | `tense: T` | (1.1) a verb token aligned to a cell of tense T whose text is no spelling of the cell: a form with attached pronouns (`dimmi`, `fallo`) |

  `words` entries with spaces (1.1) match consecutive words (`me lo`, `ce l'`); a word aligned to a verb form never counts.

- **Home-skill rule** (validator and importers): a sentence's *home skill* is the last skill, in course order, among the skills that introduce one of its aligned items (the first skill selecting the item), the verb skills whose tense it shows for one of their verbs, and the first skill introducing each of its non-base features. The sentence is valid when every feature is introduced by the home skill, one of its prerequisites (transitively), or the base set; and every non-base feature MUST be introduced by some skill. (1.2) With topics, the main tree and each topic are not ordered against each other: a sentence touching skills of several trees has one home skill per tree, and it is valid when every feature is allowed by one of them (the app shows it only once all are started).
- **In the app**, at session start: known features = base ∪ the features of every started skill and of the current skill(s) ∪ those of their prerequisites (transitively). Sentence exercises only use sentences whose features are known, and at most 2 unknown words (1 for a grammar skill or grammar focus); wrong options never show a form of a tense the learner has not met.

The compiled pack stores the result in `sentence_features`, `skill_features` and `meta.base_features`, so the app needs no language knowledge for gating.

A skill counts as **started** when the learner has practised a facet that the skill *introduces* (the facet's first skill in course order). A later skill that only shares a facet with an earlier one (a progressive skill on `stare#form:presente`) is not started by practice in the earlier skill; otherwise its grammar, and that of all its prerequisites, would count as known long before the learner gets there.

### 12.5 Recognition-only skills (1.1)

Some grammar is only needed for reading: the Italian passato remoto of novels, a literary tense, archaic forms. A skill with `recognition: true` is **recognition-only**:

- An `items:` skill trains only `#rec` of its items (the learner understands the words, never produces them).
- A `verbs: {tense: T}` skill trains `#form:T` as usual, but the app serves these facets only with **recognition exercises**, in every mode (lessons, practice, the lab, assessments): multiple choice of three kinds:
  1. a sentence with a form of T → its translation;
  2. the form → the same person's form in `equivalent_tense` ("which form means the same?": `andò` → `è andato`), when the skill declares one;
  3. the form → its person.
  Wrong options never contain a right answer (persons that share the spelling count as right). A recognition facet is never asked in a grid, an ending picker, a cloze, spot the error or a transform; a transform may still *start* from a sentence in T and ask a production tense of the same `tense_groups` group (`Andò a Roma` → `È andato a Roma`).
- The tense T is gated like any other (`tense:T`), so its sentences appear only after the skill.

Compiled: `meta.recognition_skills` (schema minor 2) maps each recognition skill to `{"equivalent_tense": T}` or `{}`. Apps before minor 2 ignore the key and would ask the forms as production, so such packs carry `meta.min_app_version` 0.7.3.

## 13. The compiled pack (course.sqlite)

One SQLite 3 file per course. The DDL in `schema/course_db.sql` is normative; a builder MUST create the tables by executing it verbatim. The app opens the file **read-only**; progress lives in a separate database.

### 13.1 File and versions

- File name `{course_id}.sqlite` when shared, bundled, hosted or copied into the app's `courses/` folder (the app skips a misnamed file).
- `PRAGMA user_version = 1` and `meta.schema_version = '1'`: the **major** schema version. `meta.schema_minor` (absent = 0) is the additive revision: `1` = inflection tables (`inflections`, `meta.inflection_tables`, facet kind `infl`, token forms `infl:…`); `2` = moods and recognition-only skills (`meta.tense_persons`, `tense_person_labels`, `tense_groups`, `recognition_skills`; written only by packs that use them, others stay at minor 1); `3` = topic trees (`topics`, `topic_units`; written only by packs with topics, which also covers minor 2). The app refuses a pack whose major version it does not know; `'1.1'` style versions also parse (major 1).
- JSON columns hold UTF-8 JSON; list columns are JSON arrays and never NULL (`'[]'`, `'{}'`). Output is deterministic apart from `meta.built_at` (fixed row order, `VACUUM` at the end).

### 13.2 meta

| Key | Req. | App needs it | Value |
| --- | --- | --- | --- |
| `schema_version` | yes | yes | `'1'` |
| `schema_minor` | no | | `'1'` |
| `course_id` | yes | yes | course id |
| `version` | yes | yes | pack version (semver) |
| `title` | yes | yes | i18n JSON |
| `target` | yes | yes | target language code |
| `persons` | yes | yes | JSON array |
| `tenses` | yes | yes | JSON array |
| `translations` | yes | | JSON array of source languages |
| `tense_labels` | yes | | JSON `{tense: i18n}` (may be `{}`) |
| `articles` | yes | | JSON array (may be `[]`) |
| `unverified` | yes | | `'0'` or `'1'` |
| `built_at` | yes | | ISO-8601 UTC |
| `attribution` | yes | | text |
| `base_features` | no | | JSON array; present = gated |
| `person_labels`, `description`, `inflection_tables`, `time_adverbs` | no | | JSON (section 3) |
| `tense_persons`, `tense_person_labels`, `tense_groups` | no | | JSON (section 3; schema minor 2) |
| `recognition_skills` | no | | JSON `{skill: {equivalent_tense?}}` (section 12.5; schema minor 2) |
| `min_app_version` | no | | semver (section 15.4) |
| `license`, `authors`, `data_sources` | no | | credits (section 11.3) |

### 13.3 Tables

| Table | Rows |
| --- | --- |
| `units(id, ord, title)` | units in order |
| `skills(id, unit_id, ord, kind, title, icon, tense, exercises, pos_x, pos_y, query)` | `tense` = a verbs skill's tense; `query` = the course.yaml query, for reference only |
| `skill_requires(skill_id, requires_id)` | prerequisites |
| `notes(skill_id, lang, md)` | grammar notes |
| `items(id, pos, lemma, article, gender, plural, freq, unit_id, tr, variants, tags)` + `item_tags` | every item, taught and pool |
| `verbs(item_id, class, stem, irregular, auxiliary)`, `verb_forms(item_id, tense, person, form, stem, ending, alts)` | verb tables |
| `inflections(item_id, tbl, cell, form, stem, ending, alts, wrong)` | inflection tables (minor 1) |
| `sentences(id, text, tr, src, unit_id)`, `tokens(sentence_id, idx, t, pre, is_word, lex, form)` | sentences, story sentences included |
| `skill_items(skill_id, item_id, ord)`, `skill_facets(skill_id, facet_id, item_id, kind, tense, ord)` | resolved skills; for `infl` facets `tense` holds the table name |
| `sentence_features(sentence_id, feature)`, `skill_features(skill_id, feature)` | grammar gating |
| `stories(id, unit_id, ord, title, title_tr, src, new_words)`, `story_sentences`, `story_questions` | stories |
| `topics(id, ord, title, short_title, description, icon, anchor)`, `topic_units(unit_id, topic_id)` | topic trees (minor 3): the topics in order with their resolved anchor; which units belong to which topic. Topic units and skills are ordinary `units` / `skills` rows (unit `ord`s after every main-tree unit); units not in `topic_units` are the main tree |

Optional tables: an app MUST load packs without `sentence_features`, `skill_features`, `inflections`, the story tables and the topic tables (packs built before them), and MUST ignore unknown tables, unknown meta keys and facet kinds it does not know.

## 14. Catalogs (index.json)

A catalog lists downloadable packs. Anyone can host one: a static `index.json` next to (or pointing at) the `.sqlite` files. The official one is `https://github.com/linguaperta/tosk-data/releases/latest/download/index.json`.

```json
{
  "index_version": 1,
  "generated_at": "2026-10-14T10:00:00Z",
  "tag": "packs-20261014",
  "courses": [
    {"id": "it", "version": "1.2.0", "title": {"en": "Italian", "nl": "Italiaans"},
     "description": {"en": "Italian from the basics."}, "target": "it", "sources": ["en", "nl"],
     "unverified": false, "schema_version": "1", "min_app_version": "0.4.0",
     "license": "CC-BY-SA-4.0", "authors": [{"name": "…"}],
     "sha256": "b30bc3…", "size": 18726912,
     "url": "https://github.com/linguaperta/tosk-data/releases/download/packs-20261014/it.sqlite"}
  ]
}
```

| Field | Req. | Meaning |
| --- | --- | --- |
| `index_version` | yes | integer, 1. An app refuses a higher version ("needs a newer app") |
| `generated_at`, `tag` | no | informational |
| `courses[].id` | yes | course id; at most once per catalog |
| `courses[].url` | yes | URL of the `.sqlite` (redirects are followed): absolute `https://`, or relative to the catalog's own URL (apps from 0.7) |
| `courses[].sha256` | yes | lower-case hex SHA-256 of the file |
| `courses[].size` | yes | integer byte size |
| `courses[].version` | SHOULD | `meta.version` (default `0.0.0`) |
| `courses[].schema_version` | SHOULD | `meta.schema_version` (default `'1'`); a pack whose major differs from the app's is offered as "needs a newer app" |
| `courses[].min_app_version` | SHOULD | `meta.min_app_version`, else the publisher's default (official: `0.3.0`) |
| `courses[].title`, `description`, `target`, `sources` (= `meta.translations`), `unverified` | SHOULD | shown before download |
| `courses[].license`, `authors` | no | credits (ignored by apps before v0.8) |
| `courses[].web_url` | no | a gzipped copy of the pack (`gzip -9`) for web apps, absolute or relative to the catalog URL. Web apps from 0.7 download it instead of `url` (it is served same-origin from the GitHub Pages mirror, which avoids CORS) and decompress it; native apps and older apps ignore it |
| `courses[].gz_sha256`, `gz_size` | with `web_url` | SHA-256 and byte size of the `.gz` file; `sha256` and `size` stay those of the uncompressed `.sqlite`, which is checked after decompressing |

The web fields are written by `pack index --gz`, `pack publish --gz` (and `python -m pipeline publish --gz`), and by `python -m pipeline mirror --out <dir>`, which builds the GitHub Pages mirror from a release (`<id>.sqlite.gz` next to an `index.json` with relative `web_url`s).

The app checks size and checksum while downloading, then validates the file's meta (course id, version, schema major) before replacing an installed pack. Unknown fields are ignored. `pack index` writes a catalog for packs you host (section 17).

## 15. Versioning and compatibility

### 15.1 Pack format version

This document versions the whole format: **1.0** = source format of sections 2–11, compiled schema 1 minor 1, catalog `index_version` 1; **1.1** adds the optional keys marked (1.1) (`required_translations`, `tense_persons`, `tense_person_labels`, `tense_groups`, skill `recognition` and `equivalent_tense`, detector types `pattern` and `enclitic`) and compiled schema minor 2; **1.2** adds `topics` (section 3.3) and compiled schema minor 3. A minor format version adds optional things that older tools and apps may ignore; a major one breaks something.

### 15.2 Compiled schema

- **Breaking change** (a column removed or renamed, a meaning changed, a required table added): bump the major (`COURSE_DB_SCHEMA_VERSION` in the pipeline, `kCourseDbSchemaVersion` in the app, `PRAGMA user_version` in the DDL). Apps refuse other majors and catalogs offer them as "needs a newer app".
- **Additive change that older apps can skip safely** (a new optional table, a new facet kind, a new token form shape): bump `schema_minor` and document it in this file and the DDL. If older apps would misbehave rather than skip it, also raise `min_app_version` for packs that use it (as minor 1 did: apps before 0.4.0 crashed on facet kind `infl`).
- **Purely informational meta keys** (`license`, `authors`, `data_sources`) need no bump.

### 15.3 Pack version

`version` is the content's semver. It MUST increase with every distributed change: the app replaces a bundled pack, and offers a catalog update, only when the version is newer (a file the learner adds by hand replaces the installed pack of that course whatever its version). Suggested use: patch for corrections, minor for new content, major for a restructured course. Progress always survives an update because item ids are permanent; facets of removed items stay in the learner's log but are no longer scheduled.

### 15.4 Minimum app version

`meta.min_app_version` is the oldest app that can use the pack. The compiler sets `0.4.0` for packs that train inflection tables and `0.7.3` for packs of schema minor 2 (moods, recognition-only skills); `course.yaml` `min_app_version` overrides it; catalogs copy it, defaulting to `0.3.0` (grammar gating and generated sentences). Topics (minor 3) raise nothing: an app before them ignores the topic tables and shows the topic units as further units at the end of the main tree, locked until their prerequisites are practised, with the same ids and progress. But that view draws a bough from each topic skill to the main-tree skill it requires, and apps 0.7.1–0.7.3 fail to paint very long boughs; a pack whose topics grow from early in the main tree sets `min_app_version: 0.7.4` (the official courses do, docs/topic-split.md). A new exercise type, facet kind or table that older apps would handle wrongly MUST come with a higher `min_app_version`.

### 15.5 Toolkit

The JSON schemas forbid unknown keys, so a source using a newer optional field fails validation in an older toolkit: use a toolkit at least as new as the pack format the source was written for (`pack --version` prints it).

## 16. Validator rules

`pack validate` (and every build) fails on any of these. **Generic** rules hold for every language; **language rules** run only where the pipeline has rules for the language (section 17.2).

Generic:

1. Every record matches its JSON schema (`course.yaml`, each JSONL line). Structural errors stop the run before the checks below.
2. Item ids are unique and start with `{course}:`; every item `unit` exists; with an `ids.tsv`, every item is listed with the same lemma and POS.
3. Verb records are unique, belong to an item, and that item is a verb.
4. Sentence ids are unique; a sentence `unit` exists.
5. Unit and skill ids are unique; prerequisites exist, are not the skill itself, and form no cycle.
6. A verbs skill's tense is declared; `time_adverbs` list only declared tenses.
7. Each skill selects at least its minimum (`min`, else 5 items, or for verbs `len(lemmas)` / `min(15, top)`); every explicit verb lemma has a complete table for the tense.
8. Every selected item has glosses in every required translation language (`required_translations`, default `translations`) and a `unit` no later than the skill's unit; every item with a unit has those glosses. `required_translations` lists only `translations` languages.
9. Article skills: every selected noun's `article` is in `articles` (when `articles` is declared).
10. Every grammar skill has a non-empty note in every `note_langs` language.
11. Verb tables: tenses declared or non-finite; persons declared or `_`; non-finite tenses use `_` only; `stem` + `ending` both or neither, and equal to `form`.
12. Inflection tables: `base` is a cell; labels name cells; an item's table is declared, allowed for its POS, has exactly the declared cells; stem + ending = form; `alts` don't repeat `form`; `wrong` forms are no form of the table. A `facet: infl` skill names a table; every trained table is declared; an `inflections` skill has at least one item that inflects.
13. Tokens re-render the text; every `lex` exists; a verb `form` exists in the verb's table; an `infl:` form exists for the item and the token text is an accepted form of the cell.
14b. (1.2) Topics: topic ids are unique; unit and skill ids are unique over every tree; the anchor (given or default) exists and is a main-tree skill, and every main-tree skill the topic's first skill requires is the anchor, one of its prerequisites or a sibling no deeper than it (later skills of the topic may require later main-tree skills: late requirements); a topic whose first skill requires no main-tree skill names its anchor; main-tree skills require no topic skill, topic skills no other topic's skill; no prerequisite cycle across trees; a main-tree skill selects no item introduced in a topic unit.
14a. (1.1) `tense_persons`, `tense_person_labels` and `tense_groups` name declared tenses (and persons); `recognition` is not combined with `facet`; `equivalent_tense` belongs to a recognition verbs skill and names another declared tense.
14. Grammar gating: detector types are known; every base feature and `introduces` entry is a tense feature or has a detector; every sentence feature is introduced by some skill or the base set, and allowed at the sentence's home skill (only when `base_features` is declared).
14c. (the fairness rule, packs with topics and gating; `python -m pipeline gen floor` and every build/validate of the official courses) Every main-tree grammar skill keeps its sentence floor for a learner who skipped every topic: its easy sentences (features allowed, at most one word taught later or in a topic), each verb × person slot of its tense (8) and each of its items (3). A floor that the skill only misses because of topic words is an error; thin spots that exist either way are the generator's ordinary gaps.

Language rules (only with pipeline support):

15. Stories: every text aligns (each word an item taught by the unit, the one declared new word, a name or a number, or one of at most three words of topics outside the story's tree); grammar allowed at the unit; 5–10 sentences of at most 14 words; every required translation present and every given one passing the translation check; 3–5 questions with 3–4 distinct options, a valid answer index and complete i18n. A pack with stories in a language without rules fails with a clear error.
16. Sentence features are computed with the language's compound-tense and auxiliary rules where they exist; otherwise only from token forms (no compound tenses).

## 17. Toolkit (`pack`) and what is generic

### 17.1 Commands

Install from a checkout of the tosk repository: `pip install -e pipeline` (Python 3.11+), which provides the `pack` command (also `python -m pipeline.cli`).

| Command | Does |
| --- | --- |
| `pack new <code> [DIR] [--title T] [--author NAME]` | writes a starter pack that validates and builds (the example of section 18) |
| `pack validate <dir>` | validates a pack source anywhere on disk; exit 1 with the errors |
| `pack build <dir> [-o out.sqlite] [--report]` | validates, then compiles (default `./{course_id}.sqlite`); `--report` prints per-skill coverage |
| `pack info <file.sqlite> [--json]` | meta, schema version, licence, authors, sources, counts per table and facet kind |
| `pack index <file.sqlite>... --base-url URL [-o index.json]` | a catalog for packs served from `URL/{course_id}.sqlite` |
| `pack publish <id>... (--dry-run \| --yes)` | the official GitHub Release (tosk-data maintainers; refuses without one of the flags, and always for restricted courses) |

The older `python -m pipeline {fetch,import,build,validate,gen,stories,publish,flags}` keeps working for the official courses (pipeline/README.md).

### 17.2 Generic and language-specific parts

| Generic (any language, driven by the pack's data) | Language-specific (pipeline code per language) |
| --- | --- |
| the source format, schemas, ids, queries and facets | tokenizer (`tokens.py`: Italian elision, Dutch clitics; other languages use the Dutch rules) |
| the compiler and the compiled pack | aligner (`align.py`: compound tenses, person disambiguation, elision; a private course plugin may bring its own) |
| the validator's generic rules (section 16) | compound tenses and auxiliaries for feature tagging (`lang.py`, keyed by course id) |
| grammar gating: the skill graph, home-skill rule, `words` and `irregular_tense` detectors (`modal_infinitive` and `separable` work from the tables too, but were only tried on Italian and Dutch) | detector `compound_aux` and compound-tense tagging (need the language's compound tenses and auxiliaries) |
| catalogs, publishing, `pack info` | inflection builders (`inflect.py` `BUILDERS[code]`), Wiktionary importers (`importer.py`, `wikt.py`) |
| the app (no language code; only conveniences keyed by `target`: handwriting model, TTS voice, AI prompt language name) | stories and generated sentences (need tokenizer + aligner), translation check (`trcheck.py`: number words, weekdays), names lists (`generate.py`) |

A pack in a language without pipeline rules can use everything on the left: write the tokens and alignments yourself (or with your own tools) and the pack validates, builds and plays. Adding a language to the pipeline means adding a `Lang` (and tokenizer rules if needed) so the importers, stories and sentence generation work.

## 18. Worked example

`pack new xx` writes this pack (with `--title "Demo course" --author Ada`). Its words are a made-up language, chosen to show every part of the format in a few lines: 2 units, 5 skills (vocab, a verb tense, nouns with a plural table, articles, a second tense), every facet kind, grammar gating (`ex:6` uses the past, allowed only from the `past` skill on), notes, credits.

```
xx/
  course.yaml
  ids.tsv
  lexicon/u1.jsonl   lexicon/u2.jsonl   lexicon/pool.jsonl
  verbs/u1.jsonl
  sentences/u1.jsonl sentences/u2.jsonl
  grammar/present.md grammar/past.md   grammar/articles.md
```

<!-- example: course.yaml -->
**`xx/course.yaml`**

```yaml
# Course definition of the pack 'xx' (pack format 1.2, docs/pack-format.md in the tosk repo).
#
# `pack new` wrote this starter. The words, verbs and sentences are EXAMPLE CONTENT in a made-up
# language, only there so that the pack validates and builds and shows every part of the format:
# replace them with your own (keep the structure, or delete what you don't need).
#
#   pack validate .            check the source
#   pack build . -o xx.sqlite
#   pack info xx.sqlite
id: xx
version: 0.1.0
title: {en: "Demo course"}
description: {en: "A new course. Describe it here."}
target: xx
translations: [en]            # the learner's languages: every taught word needs a gloss in each
note_langs: [en]              # every grammar skill needs a note in each (grammar/{skill}.md = en)
unverified: true              # set to false once a speaker has checked the content

# Credits (shown with the course). license is an SPDX identifier of the content licence.
license: CC-BY-SA-4.0
authors:
  - {name: "Ada", role: author}
data_sources:
  - {title: "Written by the course authors", license: CC-BY-SA-4.0}

# Verb grammar of the language: person keys (display order) and tense keys.
persons: [mi, tu, li, nos, vos, los]
person_labels:
  mi: {en: "mi (I)"}
  tu: {en: "tu (you)"}
  li: {en: "li (he/she)"}
  nos: {en: "nos (we)"}
  vos: {en: "vos (you, plural)"}
  los: {en: "los (they)"}
tenses: [present, past]
tense_labels:
  present: {en: present}
  past: {en: past}
articles: [le, la]            # options of the article exercise (each noun's `article` is one of them)

# Inflection tables of non-verbs: here the plural of nouns (lexicon `infl.number`).
inflection_tables:
  number:
    title: {en: singular and plural}
    pos: [noun]
    cells: [sg, pl]
    base: sg
    labels:
      sg: {en: singular}
      pl: {en: plural}

# Grammar gating: what a sentence may use from the start. Every other feature is introduced by a
# skill (a `verbs` skill introduces tense:{its tense} by itself).
base_features: ["tense:present"]

units:
  - id: u1
    title: {en: Basics}
    skills:
      - id: basics
        kind: vocab
        title: {en: Basics}
        icon: wave
        items: {tags: [basics]}
      - id: present
        kind: grammar
        title: {en: Present tense}
        icon: verb
        requires: [basics]
        verbs: {tense: present, min: 2}
  - id: u2
    title: {en: Things}
    skills:
      - id: things
        kind: vocab
        title: {en: Things}
        icon: home
        requires: [basics]
        items: {tags: [things], min: 3}
        inflections: {table: number}
      - id: articles
        kind: grammar
        title: {en: The article}
        icon: article
        requires: [things]
        facet: article
        items: {tags: [things], min: 3}
      - id: past
        kind: grammar
        title: {en: Past tense}
        icon: past
        requires: [present]
        verbs: {tense: past, min: 2}

# Optional: topics (pack format 1.2). A topic is a themed side tree with its own units and skills,
# drawn as its own map; on the main tree a branch grows off its anchor skill ("Go to <title>").
# Its skills may require main-tree skills and earlier skills of the same topic; the anchor is where
# the topic starts (the last main-tree skill its first skill requires), and a later skill may require
# a later main-tree skill (it stays locked until that one is started). Words the learner already
# knows from any tree count as known. Uncomment to try it:
#
# topics:
#   - id: market
#     title: {en: At the market}
#     short_title: {en: Market}   # carved on the branch where the title doesn't fit
#     icon: shopping
#     anchor: things              # default: the deepest main-tree skill its first skill requires
#     units:
#       - id: market-u1
#         title: {en: Buying food}
#         skills:
#           - id: market-food
#             kind: vocab
#             title: {en: Food}
#             icon: food
#             requires: [things]
#             items: {lemmas: [mela, pano], min: 2}
```

<!-- example: ids.tsv -->
**`xx/ids.tsv`**

```text
id	lemma	pos	sense_key
xx:salo	salo	intj	intj
xx:tanko	tanko	intj	intj
xx:ja	ja	adv	adv
xx:ne	ne	adv	adv
xx:mi	mi	pron	pron
xx:tu	tu	pron	pron
xx:li	li	pron	pron
xx:nos	nos	pron	pron
xx:vos	vos	pron	pron
xx:los	los	pron	pron
xx:kantar	kantar	verb	verb
xx:manjar	manjar	verb	verb
xx:mela	mela	noun	noun
xx:pano	pano	noun	noun
xx:tavo	tavo	noun	noun
xx:le	le	det	det
xx:kasa	kasa	noun	noun
```

<!-- example: lexicon/u1.jsonl -->
**`xx/lexicon/u1.jsonl`**

```json
{"id": "xx:salo", "lemma": "salo", "pos": "intj", "freq": 20, "unit": "u1", "tags": ["basics"], "tr": {"en": ["hello", "hi"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
{"id": "xx:tanko", "lemma": "tanko", "pos": "intj", "freq": 25, "unit": "u1", "tags": ["basics"], "tr": {"en": ["thank you", "thanks"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
{"id": "xx:ja", "lemma": "ja", "pos": "adv", "freq": 10, "unit": "u1", "tags": ["basics"], "tr": {"en": ["yes"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
{"id": "xx:ne", "lemma": "ne", "pos": "adv", "freq": 5, "unit": "u1", "tags": ["basics"], "tr": {"en": ["no", "not"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
{"id": "xx:mi", "lemma": "mi", "pos": "pron", "freq": 1, "unit": "u1", "tags": ["basics"], "tr": {"en": ["I", "me"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
{"id": "xx:tu", "lemma": "tu", "pos": "pron", "freq": 2, "unit": "u1", "tags": ["basics"], "tr": {"en": ["you"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
{"id": "xx:li", "lemma": "li", "pos": "pron", "freq": 3, "unit": "u1", "tags": ["basics"], "tr": {"en": ["he", "she"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
{"id": "xx:nos", "lemma": "nos", "pos": "pron", "freq": 6, "unit": "u1", "tags": ["basics"], "tr": {"en": ["we", "us"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
{"id": "xx:vos", "lemma": "vos", "pos": "pron", "freq": 8, "unit": "u1", "tags": ["basics"], "tr": {"en": ["you (plural)"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
{"id": "xx:los", "lemma": "los", "pos": "pron", "freq": 7, "unit": "u1", "tags": ["basics"], "tr": {"en": ["they", "them"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
{"id": "xx:kantar", "lemma": "kantar", "pos": "verb", "freq": 30, "unit": "u1", "tr": {"en": ["to sing"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
{"id": "xx:manjar", "lemma": "manjar", "pos": "verb", "freq": 15, "unit": "u1", "tr": {"en": ["to eat"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
```

<!-- example: lexicon/u2.jsonl -->
**`xx/lexicon/u2.jsonl`**

```json
{"id": "xx:mela", "lemma": "mela", "pos": "noun", "article": "la", "gender": "f", "plural": "meli", "freq": 40, "unit": "u2", "tags": ["things"], "tr": {"en": ["apple"]}, "tr_src": {"en": "manual"}, "src": "pack-template", "infl": {"number": {"sg": {"form": "mela", "stem": "mel", "ending": "a"}, "pl": {"form": "meli", "stem": "mel", "ending": "i", "wrong": ["melas"]}}}}
{"id": "xx:pano", "lemma": "pano", "pos": "noun", "article": "le", "gender": "m", "plural": "pani", "freq": 45, "unit": "u2", "tags": ["things"], "tr": {"en": ["bread", "loaf"]}, "tr_src": {"en": "manual"}, "src": "pack-template", "infl": {"number": {"sg": {"form": "pano", "stem": "pan", "ending": "o"}, "pl": {"form": "pani", "stem": "pan", "ending": "i", "wrong": ["panos"]}}}}
{"id": "xx:tavo", "lemma": "tavo", "pos": "noun", "article": "le", "gender": "m", "plural": "tavi", "freq": 50, "unit": "u2", "tags": ["things"], "tr": {"en": ["table"]}, "tr_src": {"en": "manual"}, "src": "pack-template", "infl": {"number": {"sg": {"form": "tavo", "stem": "tav", "ending": "o"}, "pl": {"form": "tavi", "stem": "tav", "ending": "i", "wrong": ["tavos"]}}}}
```

<!-- example: lexicon/pool.jsonl -->
**`xx/lexicon/pool.jsonl`**

```json
{"id": "xx:le", "lemma": "le", "pos": "det", "freq": 4, "tr": {"en": ["the"]}, "tr_src": {"en": "manual"}, "src": "pack-template", "inflections": ["la"]}
{"id": "xx:kasa", "lemma": "kasa", "pos": "noun", "article": "la", "gender": "f", "freq": 60, "tr": {"en": ["house"]}, "tr_src": {"en": "manual"}, "src": "pack-template"}
```

<!-- example: verbs/u1.jsonl -->
**`xx/verbs/u1.jsonl`**

```json
{"id": "xx:kantar", "class": "ar", "stem": "kant", "irregular": false, "irregular_in": [], "src": "pack-template", "forms": {"infinitive": {"_": {"form": "kantar"}}, "present": {"mi": {"form": "kanto", "stem": "kant", "ending": "o"}, "tu": {"form": "kanti", "stem": "kant", "ending": "i"}, "li": {"form": "kanta", "stem": "kant", "ending": "a"}, "nos": {"form": "kantamo", "stem": "kant", "ending": "amo"}, "vos": {"form": "kantate", "stem": "kant", "ending": "ate"}, "los": {"form": "kantano", "stem": "kant", "ending": "ano"}}, "past": {"mi": {"form": "kantevo", "stem": "kant", "ending": "evo"}, "tu": {"form": "kantevi", "stem": "kant", "ending": "evi"}, "li": {"form": "kanteva", "stem": "kant", "ending": "eva"}, "nos": {"form": "kantevamo", "stem": "kant", "ending": "evamo"}, "vos": {"form": "kantevate", "stem": "kant", "ending": "evate"}, "los": {"form": "kantevano", "stem": "kant", "ending": "evano"}}}}
{"id": "xx:manjar", "class": "ar", "stem": "manj", "irregular": false, "irregular_in": [], "src": "pack-template", "forms": {"infinitive": {"_": {"form": "manjar"}}, "present": {"mi": {"form": "manjo", "stem": "manj", "ending": "o"}, "tu": {"form": "manji", "stem": "manj", "ending": "i"}, "li": {"form": "manja", "stem": "manj", "ending": "a"}, "nos": {"form": "manjamo", "stem": "manj", "ending": "amo"}, "vos": {"form": "manjate", "stem": "manj", "ending": "ate"}, "los": {"form": "manjano", "stem": "manj", "ending": "ano"}}, "past": {"mi": {"form": "manjevo", "stem": "manj", "ending": "evo"}, "tu": {"form": "manjevi", "stem": "manj", "ending": "evi"}, "li": {"form": "manjeva", "stem": "manj", "ending": "eva"}, "nos": {"form": "manjevamo", "stem": "manj", "ending": "evamo"}, "vos": {"form": "manjevate", "stem": "manj", "ending": "evate"}, "los": {"form": "manjevano", "stem": "manj", "ending": "evano"}}}}
```

<!-- example: sentences/u1.jsonl -->
**`xx/sentences/u1.jsonl`**

```json
{"id": "ex:1", "text": "Salo, mi kanto.", "tr": {"en": "Hello, I sing."}, "tr_src": {"en": "manual"}, "src": "pack-template", "unit": "u1", "tokens": [{"t": "Salo", "lex": "xx:salo"}, {"t": ",", "is_word": false}, {"t": "mi", "pre": " ", "lex": "xx:mi"}, {"t": "kanto", "pre": " ", "lex": "xx:kantar", "form": "present.mi"}, {"t": ".", "is_word": false}]}
{"id": "ex:2", "text": "Tanko, los kantano.", "tr": {"en": "Thanks, they sing."}, "tr_src": {"en": "manual"}, "src": "pack-template", "unit": "u1", "tokens": [{"t": "Tanko", "lex": "xx:tanko"}, {"t": ",", "is_word": false}, {"t": "los", "pre": " ", "lex": "xx:los"}, {"t": "kantano", "pre": " ", "lex": "xx:kantar", "form": "present.los"}, {"t": ".", "is_word": false}]}
{"id": "ex:3", "text": "Tu manji?", "tr": {"en": "Are you eating?"}, "tr_src": {"en": "manual"}, "src": "pack-template", "unit": "u1", "tokens": [{"t": "Tu", "lex": "xx:tu"}, {"t": "manji", "pre": " ", "lex": "xx:manjar", "form": "present.tu"}, {"t": "?", "is_word": false}]}
```

<!-- example: sentences/u2.jsonl -->
**`xx/sentences/u2.jsonl`**

```json
{"id": "ex:4", "text": "Li manja la mela.", "tr": {"en": "He eats the apple."}, "tr_src": {"en": "manual"}, "src": "pack-template", "unit": "u2", "tokens": [{"t": "Li", "lex": "xx:li"}, {"t": "manja", "pre": " ", "lex": "xx:manjar", "form": "present.li"}, {"t": "la", "pre": " ", "lex": "xx:le"}, {"t": "mela", "pre": " ", "lex": "xx:mela", "form": "infl:number.sg"}, {"t": ".", "is_word": false}]}
{"id": "ex:5", "text": "Nos manjamo meli.", "tr": {"en": "We eat apples."}, "tr_src": {"en": "manual"}, "src": "pack-template", "unit": "u2", "tokens": [{"t": "Nos", "lex": "xx:nos"}, {"t": "manjamo", "pre": " ", "lex": "xx:manjar", "form": "present.nos"}, {"t": "meli", "pre": " ", "lex": "xx:mela", "form": "infl:number.pl"}, {"t": ".", "is_word": false}]}
{"id": "ex:6", "text": "Mi kantevo, tu manjevi le pano.", "tr": {"en": "I sang, you ate the bread."}, "tr_src": {"en": "manual"}, "src": "pack-template", "unit": "u2", "tokens": [{"t": "Mi", "lex": "xx:mi"}, {"t": "kantevo", "pre": " ", "lex": "xx:kantar", "form": "past.mi"}, {"t": ",", "is_word": false}, {"t": "tu", "pre": " ", "lex": "xx:tu"}, {"t": "manjevi", "pre": " ", "lex": "xx:manjar", "form": "past.tu"}, {"t": "le", "pre": " ", "lex": "xx:le"}, {"t": "pano", "pre": " ", "lex": "xx:pano", "form": "infl:number.sg"}, {"t": ".", "is_word": false}]}
```

<!-- example: grammar/present.md -->
**`xx/grammar/present.md`**

```markdown
## The present tense

Verbs end in **-ar** in the dictionary form. Take the stem (*kant-* from *kantar*, to sing) and add
the ending for the person:

| person | ending | example |
| --- | --- | --- |
| mi | -o | mi kanto |
| tu | -i | tu kanti |
| li | -a | li kanta |
| nos | -amo | nos kantamo |
| vos | -ate | vos kantate |
| los | -ano | los kantano |

*(Example note of the `pack new` starter: replace it with your own.)*
```

<!-- example: grammar/past.md -->
**`xx/grammar/past.md`**

```markdown
## The past tense

The past puts **-ev-** between the stem and a present-like ending: *mi kantevo* (I sang),
*tu manjevi* (you ate), *li kanteva*, *nos kantevamo*, *vos kantevate*, *los kantevano*.

*(Example note of the `pack new` starter: replace it with your own.)*
```

<!-- example: grammar/articles.md -->
**`xx/grammar/articles.md`**

```markdown
## The article

Every noun has a fixed article, **le** or **la**: *le pano* (the bread), *la mela* (the apple).
Learn the article together with the noun. The plural ends in **-i**: *meli*, *pani*.

*(Example note of the `pack new` starter: replace it with your own.)*
```

What the build makes of it (`pack build xx && pack info xx.sqlite`):

| Skill | Selects | Facets |
| --- | --- | --- |
| `basics` (vocab) | 10 items tagged `basics`, by `freq` | `#rec`, `#prod` each |
| `present` (grammar) | `kantar`, `manjar` (complete present tables) | `#form:present` |
| `things` (vocab, `inflections: number`) | `mela`, `pano`, `tavo` | `#rec`, `#prod`, `#infl:number` |
| `articles` (grammar, `facet: article`) | the same nouns | `#article` |
| `past` (grammar) | `kantar`, `manjar` | `#form:past`; introduces `tense:past` |

`kasa` and `le` are pool items: wrong options and aligned words, never taught. `meta.min_app_version` is `0.4.0` because the pack trains an inflection table. The attribution is generated from `license`, `authors` and `data_sources`.

## 19. Open issues

Current behaviour that is accidental or inconsistent. The rule stated in this document is the intended one; the code has not been changed yet.

1. **`note_langs` defaults to `[en, nl]`** (the official courses' languages) in `validate.py`, not to `translations`. Intended default: `translations`. Packs SHOULD set `note_langs` explicitly until then (`pack new` does).
2. **`note:` path only knows English and Dutch** (`{path}.md` = en, `{path}.nl.md` = nl, `compile.note_texts`). Intended: `{path}.{lang}.md` for every language, like `grammar/`.
3. **The default attribution names tosk-data and CC BY-SA 4.0** for any pack without `attribution` or credits (`compile.attribution_text`). Intended: generated from the pack's credits only; packs without credits get "no licence declared". (Packs that declare credits already get a generic text.)
4. **The official packs declare no `license`/`authors`/`data_sources`** (it, nl, es: licence only in the attribution text and ATTRIBUTION.md). They should add them to `course.yaml` in tosk-data.
5. **`build` writes a different `dist/index.json`** (`build.write_index`: `schema_version` as an integer, a `note`, relative `url`s, no `index_version`) than `publish` (section 14), into the same file, merging into whatever is there; the tosk-data `dist/index.json` currently mixes both shapes. An app cannot read the build variant. Intended: `build` writes no catalog (or a valid one); only `publish`/`pack index` write catalogs.
6. ~~**Relative `url`s in catalogs** are not resolved by the app.~~ Fixed in app 0.7: `url` and `web_url` resolve against the catalog's own URL (older apps still need absolute URLs).
7. **Course id = target is not enforced** (neither schema nor validator compares `id` and `target`), while language rules are looked up by **course id** (`lang.get_lang(course["id"])`, `tokenize(text, code)`) and the app's language features by `target`. Intended: the validator enforces `id == target` in format 1.0, and the pipeline looks language rules up by `target` (needed for extension packs, section 20).
8. **`facet: article` / `facet: infl` are allowed on vocab skills** (schema and validator only require `items`). Intended: they need `kind: grammar`.
9. ~~**`exercises:` in course.yaml cannot list `listen_pick`**~~ Fixed in format 1.1.
10. **`persons` and `tenses` are required and non-empty** even for a pack without verbs. Intended: optional, default `[]` (the app reads empty lists fine); until then a verb-less pack declares a dummy person and tense.
11. ~~**`tr_src` in the lexicon is a closed list.**~~ Fixed in v0.8: lexicon `tr_src` is an open tag (section 11.2) like sentence `tr_src` and every `src`; the registered tags are documented in section 11.2.
12. **AI labels are Claude-specific** (`claude`, `claude-draft`, `claude-gen`), and the unsuffixed `claude` duplicates `claude-draft`. Intended: keep the three; other systems use `ai-{system}-gen` / `ai-{system}-draft`, and the app's "generated" ranking should match `*-gen` from any system.
13. **Provenance is dropped at compile time** except `sentences.src` and `stories.src`, so the app cannot show per-word sources. Proposal (schema minor 2): `items.src`, `verbs.src`.
14. **Additions without a minor bump**: grammar gating tables (`sentence_features`, `skill_features`, `meta.base_features`), `meta.time_adverbs` and the story tables were added within schema minor 0, so a minor-0 pack may or may not have them (the app checks table presence). From format 1.0 on, every additive change bumps `schema_minor`.
15. **ids.tsv permanence is not checked across versions**: the validator only checks the current items against the file. Proposal: `pack diff old.sqlite new.sqlite` reporting removed or changed ids.
16. **The schemas live outside the Python package** (`schema/` at the repository root), so the toolkit works from a checkout (`pip install -e pipeline`) but a plain wheel would lack them. Before publishing the toolkit on PyPI, ship the schema files as package data (one source of truth).
17. **Machine-specific defaults** in `paths.py` (`C:/Users/timo/Repositories/tosk-data`); the app's local-pack tests read `$TOSK_HNS_PACK` only (v0.8). The `pack` commands take explicit paths and don't use them.
18. **The course id pattern `^[a-z]{2,3}$`** leaves no room for several courses of one language (personal packs, extensions). Needed for section 20: `^[a-z]{2,3}(-[a-z0-9]+)*$` with `target` carrying the language.
19. **`min_app_version` default 0.3.0** lives in `publish.py`, not in the pack; packs built without inflection tables carry no `min_app_version` at all. Intended: the compiler always writes it.
20. **Stories have no `src` field**: the build labels every story `claude-gen (story)` (`stories.SRC`), also one a person wrote. Intended: an optional `src` per story, defaulting to `claude-gen` only for the official courses' Claude-written stories.
21. **The app does not show `license`, `authors` and `data_sources` yet** (only `meta.attribution`, in Settings); the course preview showing them is a v0.8 backlog item.

## 20. DRAFT: extension packs (v0.8)

**DRAFT, not implemented.** (Built-in topic trees, section 3.3, are implemented in 1.2; an extension pack would add such topics from a separate pack.) An extension pack adds vocabulary, sentences or units on top of a base course and shares its progress: a job vocabulary, a song collection, a book ("read Montalbano").

```yaml
id: it-montalbano            # needs the wider id pattern (open issue 18)
target: it
extends: {course: it, version: ">=1.2.0"}    # or the short form: "it >= 1.2"
units:
  - id: ch1
    skills:
      - id: ch1-words
        kind: vocab
        items: {tags: [ch1]}
```

Draft rules:

- **Base item ids are reused.** The extension's lexicon refers to base items by their id (`it:mangiare`) and does not redefine them; facets of base items keep their base ids (`it:mangiare#rec`), so practice counts for both packs. New words get ids in the extension's own namespace (`it-montalbano:cumissario`), or (preferred, once accepted) are proposed for the base course.
- **Compiled form:** `meta.extends = {"course": "it", "version": ">=1.2.0"}`; the pack contains copies of the base items, verb tables and inflections it uses (so it renders without the base), marked as base items.
- **App:** an extension is offered only when a satisfying base version is installed (a base-pack check); its skills appear as their own course map or as extra units of the base; progress needs no change because it is keyed by facet id.
- **Gating:** `base_features` of an extension default to the base course's features of the units the learner has started.
- **Open questions:** a base update that drops an item the extension uses; whether `requires` may point at base skills (`it/passato-prossimo`); reading readiness (`pack from-text`) as extension-pack metadata.

## Appendix A: source-specific importers

Importers, scrapers and reference data aimed at one copyrighted source are not part of the format or the generic toolkit. They live in private repositories and plug into the pipeline as course plugins (`pipeline/pipeline/plugins.py`); restricted courses are kept out of every public location by `pipeline/pipeline/restricted.py`. How the plugin point works: [docs/private-importers.md](private-importers.md).
