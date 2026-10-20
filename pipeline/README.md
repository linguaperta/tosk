# tosk content pipeline

Python scripts that turn open data into the compiled course packs the app reads
(`schema/course_db.sql`). Not part of the app.

```
open data (cache)  --fetch-->  filtered dumps  --import-->  content/{it,nl}/*.jsonl  --build-->  dist/{it,nl}.sqlite
```

## Setup

```sh
C:\Python313\python.exe -m venv pipeline/.venv
pipeline/.venv/Scripts/python -m pip install -r pipeline/requirements.txt
pipeline/.venv/Scripts/python -m pip install -e pipeline      # makes `python -m pipeline` work from any folder
```

Dependencies: pyyaml, jsonschema, requests (pytest for the tests).

## Commands

```sh
python -m pipeline fetch [it nl] [--force] [--skip-english]   # downloads into the cache (online)
python -m pipeline import it nl [--content-root DIR]           # cache -> content/{course}/*.jsonl
python -m pipeline build it nl [--install] [--quiet]           # validate + compile + report + dist/index.json (offline)
python -m pipeline validate it nl                              # validation only
python -m pipeline gen gaps it nl                              # thin spots (grammar slots, items, unit 1)
python -m pipeline gen context it --skill present-are          # what a sentence for that skill may use
python -m pipeline gen check it drafts.jsonl                   # check Claude-written drafts (dry run)
python -m pipeline gen add it drafts.jsonl                     # ... and add the accepted ones
python -m pipeline gen refresh it [--drop]                     # re-align generated sentences after an import
python -m pipeline stories it [--show u3|all]                  # check the graded stories (+ print their alignment)
python -m pipeline publish it nl [--tag packs-YYYYMMDD] [--dry-run]   # dist/index.json + GitHub Release (gh; never hns)
python -m pytest pipeline/tests                                # offline tests

python -m pipeline fetch hns                 # Sarnami: scrape the [source] dictionary (1 req/s) + extra sources
python -m pipeline import hns                # -> <main checkout>/local/content/hns (local only)
python -m pipeline build hns --local [--desktop]   # -> local/dist/hns.sqlite (+ copy into the desktop app)
```

Sarnami (`hns`) content is copyrighted and lives only in the git-ignored `local/` folder of the main
checkout; the pipeline refuses to write it anywhere else (`pipeline/hns/safeguard.py`) and refuses
`--install`. Details, sources and verification: `docs/sarnami.md`.

* **Content root** (the folder with `it/`, `nl/`): `--content-root`, else `$TOSK_CONTENT`, else
  `../tosk-data/content` next to the repo root, else `C:/Users/timo/Repositories/tosk-data/content`
  (so git worktrees find the data checkout). `dist/` is the sibling of the content root.
* **Cache**: `%LOCALAPPDATA%\tosk-cache` (override with `TOSK_CACHE`). Never committed.
* `build --install` copies the packs to `app/assets/courses/{id}.sqlite` (bundled with the app).
* `build` needs only the committed JSONL/YAML/markdown, so it works offline and is deterministic apart from
  `meta.built_at`.
* `publish` (`pipeline/publish.py`) rewrites `dist/index.json` for a release (absolute asset URLs,
  `index_version`, `generated_at`, `tag`, and per course id, version, title, description, target,
  sources, unverified, schema_version, min_app_version, sha256, size, url) and runs
  `gh release create <tag> dist/<id>.sqlite... dist/index.json --repo timoverlaan/tosk-data --latest`.
  The app reads `https://github.com/timoverlaan/tosk-data/releases/latest/download/index.json`.
  `--dry-run` writes the index and prints the commands. Restricted courses (`hns`) are refused.
  Steps and `gh auth login`: docs/release.md, "Publishing course packs".

## Sources (fetch)

| Cache file | Source | Notes |
|---|---|---|
| `kaikki-{it,nl}.jsonl` | kaikki.org English-Wiktionary dumps for Italian / Dutch (770 / 256 MB) | streamed and filtered on the fly: lemma entries (no form-of entries) whose word is in the 50k frequency list; ~30 / 25 MB |
| `en-trans-it-nl.jsonl` | kaikki.org English dictionary (3.3 GB) | streamed; keeps only translation-table senses listing both an Italian and a Dutch word (Italian -> Dutch pivot) |
| `kaikki-nlwikt-it.jsonl` | kaikki.org Dutch Wiktionary, Italian entries | Dutch glosses for Italian words |
| `nlwikt-nl-aux.jsonl` | kaikki.org Dutch Wiktionary, Dutch entries (1.2 GB, streamed) | perfect auxiliary (hebben/zijn) per Dutch verb, which en.wiktionary's tables lack |
| `tatoeba/*.tsv.bz2` | downloads.tatoeba.org per-language exports | ita/nld/eng sentences, ita-eng, ita-nld, nld-eng links |
| `freq/{it,nl}_50k.txt` | hermitdave/FrequencyWords 2018 (OpenSubtitles) | word-form counts |

## Source pack format (`content/{course}/`)

| File | Written by | Schema |
|---|---|---|
| `course.yaml` | hand | `schema/course.schema.json` |
| `seed.yaml` | hand (curation input for the importer) | — |
| `lexicon/{unit}.jsonl`, `lexicon/pool.jsonl` | importer | `schema/lexicon.schema.json` |
| `verbs/{unit}.jsonl`, `verbs/pool.jsonl` | importer | `schema/verbs.schema.json` |
| `sentences/{unit}.jsonl` | importer | `schema/sentences.schema.json` |
| `sentences/gen-{unit}.jsonl` | `gen add` (Claude-written, kept by the importer) | `schema/sentences.schema.json` |
| `sentence_ids.tsv` | `gen add` (append-only) | `id, key` (generated sentence id, normalized text) |
| `stories/u{n}.yaml` | Claude (graded stories, see [Stories](#graded-stories-pipelinestoriespy)) | checked by `stories.py` |
| `grammar/{skill}.md` (en), `grammar/{skill}.nl.md` (nl) | hand | — |
| `ids.tsv` | importer (append-only) | `id, lemma, pos, sense_key` |

The files are grouped by the unit that introduces the item; `pool.jsonl` holds the distractor pool
(items without a unit). Grouping is only for readability: the `unit` field is what counts.

Examples:

```json
{"id": "it:mangiare", "lemma": "mangiare", "pos": "verb", "freq": 238, "unit": "u2", "tr": {"en": ["to eat"], "nl": ["eten"]}, "tr_src": {"en": "wiktionary", "nl": "claude"}}
{"id": "it:mangiare", "class": "are", "stem": "mangi", "irregular": false, "irregular_in": [], "auxiliary": "avere", "forms": {"presente": {"noi": {"form": "mangiamo", "stem": "mang", "ending": "iamo"}}, "passato_prossimo": {"io": {"form": "ho mangiato"}}}}
{"id": "s:4821", "text": "Mangiamo alle otto.", "tr": {"en": "We eat at eight."}, "tr_src": {"en": "tatoeba:1234"}, "src": "tatoeba:4821", "unit": "u2", "tokens": [{"t": "Mangiamo", "lex": "it:mangiare", "form": "presente.noi"}, {"t": "alle", "pre": " ", "lex": "it:al"}, ...]}
```

Sentence records use `text` + `tr` (like the database) instead of the spec sketch's `it`/`en` keys.
Token `form` is `'{tense}.{person}'` for verb forms and `'infl:{table}.{cell}'` for inflected
non-verbs (`infl:number.pl`, `infl:agreement.f.sg`).

### course.yaml queries

Skills select items with queries (resolved identically by importer and compiler, `pipeline/query.py`):

* `items: {tags, pos, lemmas, exclude, top, min}` (vocab skills; with `facet: article` the skill trains
  `#article` of nouns that have an article)
* `verbs: {tense, class, regular, aux, lemmas, exclude, top, min}` (grammar skills): verbs with a
  **complete** table (all persons) for `tense`; `regular: true` = the tense is not in the verb's
  `irregular_in`; `aux` = the primary perfect auxiliary.
* Order = frequency rank (an explicit `lemmas` list without `top` keeps its own order).
* Minimum (validator): `min`, else for verb queries `len(lemmas)` or `min(15, top)`, else 5 items.
* `inflections: {table: T}` (or `table: [T1, T2]`) on an `items` skill trains the inflection table T
  (facet `#infl:T`) of its items, see [Inflection tables](#inflection-tables-pipelineinflectpy).
  With `facet: infl` the skill trains only those facets and selects only items whose table T has
  at least two different forms; without `facet` they come on top of `#rec`/`#prod`.

### Inflection tables (`pipeline/inflect.py`)

Non-verbs can have inflection tables (docs/ARCHITECTURE.md, "Inflection tables"). A course
declares them; the importer fills them per item from Wiktionary with the language's builders
(`inflect.BUILDERS[code][table]`); skills train them:

```yaml
inflection_tables:
  number:                                    # table name (a key: [a-z][a-z0-9_]*)
    title: {en: singular and plural, nl: enkelvoud en meervoud}
    pos: [noun]                              # parts of speech that can have it
    cells: [sg, pl]                          # cell keys in display order ([a-z0-9_] with dots: m.sg)
    base: sg                                 # the cell equal to the lemma: given, never asked
    labels: {sg: {en: singular, nl: enkelvoud}, pl: {en: plural, nl: meervoud}}
  agreement:
    title: {en: gender and number, nl: geslacht en getal}
    pos: [adj, det]
    cells: [m.sg, f.sg, m.pl, f.pl]
    base: m.sg
    agreement: true                          # the cell follows from the sentence (the noun):
    labels: {...}                            #   other cells are wrong options in sentences
units:
  - skills:
      - id: plurals
        kind: grammar
        facet: infl                          # only #infl facets ...
        inflections: {table: number}         # ... of this table
        items: {pos: noun, tags: [people, food], top: 30}
      - id: adjectives
        kind: grammar
        items: {tags: [adjectives]}
        inflections: {table: agreement}      # #rec + #prod + #infl:agreement
```

* **Lexicon records** get `"infl": {table: {cell: {form, stem?, ending?, alts?, wrong?}}}` (and
  `"uncountable": true` for mass nouns: Wiktionary `-` or seed `uncountable`, no number table).
  `stem`+`ending` = the longest common prefix of the table's forms (`gatt`+`o`/`i`, `wit`+``/`te`;
  Italian invariable nouns split off the final vowel: `citt`+`à`). `wrong` = plausible learner
  errors that are **no word**: not in the 50k frequency list nor any Wiktionary form (`gatte` is a
  word and never offered; `gattoi`, `katen`, `huisen`, `wite`, `huistje` are).
* **Builders** (it): `number` (plural from the entry's plural forms, `invariable` → same form; no
  table for uncountable or plural-only nouns), `agreement` (tagged feminine / plural forms, alts
  such as `bel`/`bei`/`begli`; adjectives also by rule: -o → a/i/e, -e → e/i/i). (nl): `number`
  (other plurals as alts: `appels`/`appelen`; a plural spelled like the singular is dropped),
  `agreement` (`base`/`infl`), `comparison` (`base`/`comparative`/`superlative`, imported, not
  trained yet), `diminutive` (`sg`/`dim`). A new language adds builders to `BUILDERS` and, for
  agreement tables, a rule to `AGREEMENT` (which word controls the agreement).
* **Alignment** (`InflectionAligner`, run at the end of `Aligner.align`): a token aligned to an
  item with tables gets `form = 'infl:{table}.{cell}'`. Spelling decides for tables without
  agreement (a noun's `sg`/`pl`; a form shared by two cells, `città`, gets none; an adjective's
  base form is left to the agreement rule). Diminutive tokens are linked to their noun when they
  are unaligned or aligned to an untaught item spelled the same (`huisje`). Agreement cells are set
  only where the language rule finds the controlling word and the attested form agrees: Italian,
  the adjacent noun or the noun before a copula (`una casa bella`, `la pizza è buona`, `mia madre`)
  with a fixed gender (not `m|f`) and a known number; Dutch, attributive (`het grote huis`, `een
  groot huis`, `een grote man`: -e unless a singular het-word after een/geen/no article; fixed
  expressions like `het openbaar vervoer` contradict the rule and get no form) or predicative at
  the clause end without a determiner before it (`Het huis is groot.`).
* **Feature tagging** is unaffected (tenses come only from verb tokens).
* **Sentence selection:** an inflection skill gets up to 6 sentences per (item, table, asked cell)
  (`INFL_QUOTA`), counted for the skill like a verb tense for its grammar skill.
* **Validator:** tables declared, cells complete, pos allowed, stem+ending = form, `wrong` never a
  form of the table, token forms `infl:...` exist for the token's item and its text is an accepted
  form of the cell, every inflection skill has at least one inflecting item.

Grammar gating keys (see [Grammar gating](#grammar-gating-pipelinefeaturespy)):

```yaml
base_features: ["tense:presente"]                 # allowed from the start
feature_detectors:                                # construct features and how to find them
  "aux:essere": {type: compound_aux, aux: essere}
  modal: {type: modal_infinitive, verbs: [potere, dovere, volere, sapere], infinitive_pattern: "..."}
  "prep:articulated": {type: words, words: [del, della, nel, ...]}
  "irregular:futuro": {type: irregular_tense, tense: futuro}
  separable: {type: separable, particles: [op, mee, weg, terug, ...]}     # Dutch
units:
  - skills:
      - id: passato-prossimo-essere
        introduces: ["aux:essere"]                # a verbs skill also introduces tense:{T}
```

Time adverbs (optional; compiled to `meta.time_adverbs`, the validator checks the tenses): the tenses
each adverb fits. The app never rewrites a sentence containing one (whole words, case-insensitive)
into another tense in the transform exercise.

```yaml
time_adverbs:
  ieri: [passato_prossimo, imperfetto]
  la settimana scorsa: [passato_prossimo, imperfetto]   # multi-word keys are fine
  adesso: [presente]
```

### seed.yaml (curation)

```yaml
exclude: [coso, sulla/noun]              # never in the frequency pool
exclude_sentences: [1234567]             # Tatoeba sentence ids a review found wrong or odd: never imported
exclude_words: [vos, tenés]              # sentences with these words (another variety) are not imported
exclude_moods: [subjunctive, conditional] # moods the tables leave out: sentences with their forms are
                                         # not imported (a spelling that is also another word, 'fuera',
                                         # only counts after que/si/ojalá)
uncountable: [burro, latte]              # mass nouns: no plural in the lexicon (no 'burri' option)
items:
  - {lemma: ciao, pos: intj, tags: [greetings], en: [hi, bye], nl: [hoi, doei]}
  - {lemma: del, pos: prep, en: [of the], nl: [van de], inflections: [della, dei]}
  - {lemma: pensare, pos: verb, nl: [denken]}      # gloss override only
  - {lemma: mens, pos: noun, article: "de|het", tags: [people]}   # both articles are right
```

A noun with two articles (`de|het`: *de mens* / *het mens*, *de/het soort*) is never asked or
swapped as an article error by the app; keep it out of article skills (`exclude`).

`tags` put the word in vocab skills; glosses written here get `tr_src: claude`.

## What the importer does

1. Parses the filtered Wiktionary entries: POS, cleaned short English glosses, gender, plural,
   inflections, and the **first** conjugation table (later tables hold archaic/regional variants).
   Forms tagged archaic, regional, formal, subjunctive, conditional, imperative, historic past, ...
   are dropped. Italian pronunciation accents on non-final vowels are stripped (`màngio` → `mangio`).
2. Frequency rank per (lemma, POS): count of the lemma plus its inflected forms. Homographs: the full
   lemma count goes to the function word / verb / entry with most senses; others get 0.5 %; a lemma
   that is also a form of another word gets 10 % (1 % for verbs, e.g. Dutch *waren*). A **tagged**
   seed item (a taught word) takes the highest score of its non-verb homographs, which drop to 0.5 %,
   so the alignment links the word to the taught item (*madre* noun, not the adjective; *solo* adverb,
   not the conjunction). Verbs keep their own score.
3. Pool = top 3000 eligible lexemes (has English glosses, lowercase, no digits, no Italian pronominal
   verbs) plus every seed item. IDs come from `ids.tsv` (see below).
4. Translations: `tr.en` from Wiktionary (or seed); Italian `tr.nl` from seed (Claude) > Dutch
   Wiktionary > English translation-table pivot. Dutch items have only `tr.en`.
5. Verb tables: simple tenses from Wiktionary (only complete tenses are kept), compound tenses built
   from the auxiliary's present + participle (Italian essere-verbs list feminine/plural agreement as
   `alts`; Dutch hebben|zijn verbs list the other auxiliary as `alts`). `irregular_in` is computed by
   comparing with the regular paradigm (Italian -are/-ere/-ire/-isc; Dutch stem / stem+t / infinitive
   with spelling-insensitive stem comparison). Classes: it `are|ere|ire|isc|other`, nl
   `weak|strong|mixed`.
6. Stem/ending split (simple tenses only, compound forms get NULL): Italian = the class ending for that
   person, stem must match the infinitive stem (`cerch+iamo`, `cap+isco`, `mangi+o`, `mang+iamo`);
   Dutch only for verbs regular in that tense: present `werk+''`, `werk+t`, `werk+en`, weak past
   `werk+te`, `werk+ten`. The Dutch ik-form has an **empty ending** (stem = form).
7. Units: every skill query is resolved in unit order; an item belongs to the first unit that selects it.
8. Sentences (Tatoeba): 2–10 words, an English translation required (Dutch added for Italian when
   linked), invisible characters removed (zero-width spaces), duplicates removed (same text after
   folding case, punctuation and spacing: *Grazie mille!* = *Grazie mille.*), at most one unlinked
   word (names and numbers don't count) and ≥ 80 % linked. With grammar gating (a course with
   `base_features`): the sentence must be valid at its home skill, at most one word that is never
   taught (pool or unlinked), and it only counts for a skill item (verb tense) when the item's skill
   (the verb's grammar skill) allows all its features and at most 2 (1) of its words are taught after
   that skill. Greedy selection, fewest unknown words first, then shortest/cleanest, while a quota is
   open: 25 sentences per skill item, 48 per (grammar verb, tense) and up to 8 per (verb, tense,
   person), always accepting up to 2 per person. `unit` = the latest unit among the skill items in
   the sentence. Translation check (`trcheck.py`): a pair whose numbers, weekdays/months or names
   (only names both languages write alike: Tom, Boston) differ is a link to another variant of the
   sentence; the sentence is dropped (Dutch translation of an Italian sentence: only that
   translation). Compound numbers are read whole on both sides (*two hundred* = *doscientos* =
   *tweehonderd* = 200, *treinta y dos* = *thirty-two*, *vijfentwintig*, *duemila*). 2026-10: 643 it / 266 nl candidates dropped, 25 Dutch translations dropped.
   Generated sentences (`sentences/gen-*.jsonl`) are kept, and a Tatoeba sentence with the same
   text is skipped.

### Tokenizer (`pipeline/tokens.py`)

Words and punctuation are separate tokens; `pre` keeps the whitespace, so `pre+t` concatenated
re-renders the text exactly. Italian elision: an apostrophe between two letters stays on the first
token (`l'|acqua`, `dell'|uomo`, `c'|è`, `un'|amica`); a final apostrophe is kept only for known
truncations (`po'`, `mo'`, `be'`, `di'`, `fa'`, `va'`, `da'`, `sta'`, `to'`). Dutch keeps internal
apostrophes (`auto's`, `zo'n`) and treats `'s`, `'t`, `'k`, `'n` as words. Hyphenated words are one token.

### Alignment (`pipeline/align.py`)

Tokens get `lex` (item id) and, for verbs, `form = '{tense}.{person}'` by reverse lookup in the
conjugation tables. Rules:

* Noun vs verb: verb reading unless the previous word is a determiner/preposition (`la porta`), or
  (Dutch) the only verb reading is an ik-form without *ik* next to it (`waar`).
* **Compound tenses**: a participle plus a present form of its auxiliary in the same clause
  (Italian: within 4 words before, with only adverbs or subject pronouns in between: *ho già
  mangiato*, but not *Sono sicura del suo successo*; Dutch: anywhere in the clause, not after *te*) → the participle
  token gets `form = passato_prossimo.{person}` / `perfectum.{person}` and the auxiliary token gets
  its own present form. *The participle token's text is only part of the multi-word form in
  `verb_forms`* (`mangiato` vs `ho mangiato`). Participles without auxiliary → `participle._`.
  Not linked (both words keep `lex`, no compound `form`), because an exercise built on them would be
  wrong: an auxiliary whose adjacent subject pronoun fits none of its persons (inversion `Heb je
  gegeten?`, `io e lui abbiamo`) or is polite *u*; Dutch modal + perfect infinitive (`zou … geweest
  zijn`: `zijn` is an infinitive); *zijn* + participle of a verb that lists *zijn* only as its second
  auxiliary (nl.wiktionary does that for transitive verbs because of the passive: `is gezien`);
  possessive *zijn* before a noun. Italian: after a form of *essere*, a participle/finite homograph
  is the participle (`sono state costruite`).
* Ambiguous persons: an adjacent subject pronoun decides; a pronoun that fits no form (subjunctive)
  leaves `form` unset; Dutch infinitive after *te* or a finite verb in the clause; a name/noun subject
  requires a 3rd-person form (else unset); Italian *sono*: following -i/-e adjective/participle =
  *loro*, else *io*; otherwise 3rd singular, 3rd plural, first person in order.
* Dutch inversion (`werk jij`, `wil je`, `kwam je`), imperatives and other clause-initial verbs
  without a subject pronoun after them (`Laat me …`, `Werkt Tom …?`), verbs next to polite *u*
  (`u bent` / `u is`), forms of two different verbs (`was` as *ik was*: zijn or wassen, unless no
  object follows: *Ik was moe*; *hij was* is only zijn) and conditional *zou* keep `lex` but get no
  `form`.
* Italian imperatives look like present forms: a clause-initial tu/lui/noi/voi form (after *non* or
  clitics at most) without a subject pronoun, not of essere/avere, in a sentence with `!` or whose
  English translation starts with an imperative (*Ask …*, *Please …*, *Don't …*, *Let's …*) keeps
  `lex` but gets no `form` (`Chiedi a un poliziotto!` is no `tu chiedi`).
* An interjection item at the start of a clause wins over a homograph (*Prego.*, *Scusa, …*, *Dag
  Anna!*, *Bedankt!*); multi-word phrase items link every word (*per favore*, *tot ziens*).
* Dutch adjective/verb homographs before a copula are the adjective (*dat ik laat ben*, *of het open
  is*).
* Dutch clauses (`Lang.clause_starters`, `coordinators`, …): one finite verb per clause, so a later
  infinitive homograph is the infinitive (`Ik zal jullie vertellen`, `Wat kan ik voor jullie doen?`)
  and an adjective homograph the adjective (`te laat`, `hoe laat`); a subordinate clause starts over
  when a pronoun, name or *er* directly follows its conjunction (`Ik weet dat jullie werken`), not
  after a demonstrative *dat* (`Kun je me dat laten weten?`). In a verb-final clause where several
  persons share the form (`maakt`: jij/hij), only an unambiguous subject pronoun earlier in the clause
  decides (`dat ik weg moet`); `je`/`ze`/`het` may be objects, so with them the person stays open.
  A clause-initial noun or a noun after an inflected adjective is not a verb (`Leven is …`, `het
  eeuwige leven`).
* Spanish (`lang_es.py`, generic fields in `lang.py`): after a finite *ser*/*estar* (`copula_lemmas`, only
  `skip_between` words in between) a word is no finite verb (*¿Estás todavía despierta?*: awake);
  irregular tú-imperatives spelled like another verb's present (`imperative_homographs`: *ve*, *ven*,
  *sé*, *di*, *sal*, *ten*) link to their own verb without a form when clause-initial and the sentence
  has `!` or its English translation starts with that verb (*Ven enseguida* = Come right away);
  `verb_needs_pronoun` words (*como*, *caso*) are verbs after an object clitic too (*lo como*).
* A participle right after a determiner that is no pronoun (*su pedido*, *por supuesto*) is a noun the
  lexicon lacks: it stays unlinked instead of tagging the perfect.
* A form that several items of one part of speech list as an inflection goes to the item whose own
  inflection table has it (Wiktionary lists *esa*, *esta*, *aquella* under every Spanish demonstrative).
* Unmatched tokens stay unlinked.
* **Split separable verbs** (Dutch): a finite verb whose cell (tense, person) together with the
  last word of its clause is a two-word form of a separable verb (`sta … op` = `opstaan`, ik)
  links both words to the separable verb with that cell, like the two words of a compound form:
  *Ik sta morgen vroeg op*, *Hij komt morgen terug*, *Nooit belt er iemand me op*. The clause
  ends at punctuation, a coordinator or a clause starter (`Ik sta op en ga …`); not when the finite
  verb has no person (inversion `Sta je op?`, imperatives) and not when the clause has `hier`,
  `daar` or `waar` (a stranded preposition: `Hier komt nooit een eind aan`). The engine then finds
  the split form like `heb … gegeten` (cloze gaps the finite word, spot the error swaps it).
  Subordinate-clause forms written as one word (`dat ik opsta`) are not in the tables and stay
  unlinked.
* Inflected non-verbs get `infl:{table}.{cell}` forms, see [Inflection tables](#inflection-tables-pipelineinflectpy).

### Grammar gating (`pipeline/features.py`)

A learner should not meet a grammar construct before the skill that teaches it
(`docs/ARCHITECTURE.md`, "Grammar gating"). The pipeline tags every sentence with **features** and
every skill with the features it **introduces**; the compiler writes them to `sentence_features`,
`skill_features` and `meta.base_features`.

* `tense:{T}` for every verb token in tense T. A compound form tags its compound tense on the
  participle and its auxiliary is not tagged as present; a participle without an auxiliary
  (passive, adjectival) tags the compound tense too. A verb token without a `form` is looked up by
  its spelling (only a spelling that is no present form and no infinitive counts: *Kwam je?*).
  A Dutch perfect with a double infinitive (*Ik heb Tom niet zien vallen*, *Hij heeft Japans willen
  leren*, *Ik ben gaan zwemmen*: a finite auxiliary and two adjacent infinitives later in its
  clause, the first not after *te*/*om*) tags `tense:perfectum` too, plus `aux:zijn` with *zijn*
  and `modal` when the first infinitive is a modal.
* Construct features from `course.yaml` `feature_detectors`: `compound_aux` (a compound form with
  that auxiliary: *sono andato*), `modal_infinitive` (a finite modal plus a later infinitive, also an
  Italian clitic infinitive matching `infinitive_pattern`: *posso farlo*), `words` (any of these
  spellings), `irregular_tense` (a form of a tense in the verb's `irregular_in`: *andrò*, *ging*),
  `separable` (a separable verb in any form, or a finite verb with a clause-final particle that
  together form one: *Hij komt morgen terug.*).
* A skill introduces its `introduces` list, plus `tense:{T}` for a `verbs: {tense: T}` skill.
* **Home skill** of a sentence: the last skill (course order) among the skills introducing its
  aligned items, the verb skills whose tense it shows for one of their verbs, and the first skill
  introducing each non-base feature. Valid = every feature is introduced by the home skill, one of
  its prerequisites (transitively) or the base set. The importer selects only valid sentences and the
  validator checks every sentence again. Courses without `base_features` are tagged but not gated.
* Features per course: it `tense:{imperfetto,futuro,passato_prossimo}`, `aux:essere`, `modal`,
  `prep:articulated`, `irregular:futuro` (base `tense:presente`); nl `tense:{verleden_tijd,
  perfectum}`, `aux:zijn`, `modal`, `separable`, `irregular:verleden_tijd` (base
  `tense:tegenwoordige_tijd`).

## Courses

Units, skills (items; `*` = grammar) and the features each unit introduces. Every unit's skills
require the previous unit's grammar, so a later skill allows everything taught before it.

**Italian 1.2.0** — 41 skills, 738 taught items, 1613 facets, 20 805 sentences (2213 generated).

| Unit | Skills (items) | Introduces |
|---|---|---|
| u1 Basics | greetings (19), little-words (31), people (33), essere-avere* (2) | |
| u2 The present tense | food (30), numbers (23), present-are* (20), articles* (55), present-ere* (18), present-ire* (18) | |
| u3 Everyday life | time (30), home (29), family (16), everyday-verbs (28), irregular-present* (14), pronouns* (9), modal-verbs* (4), plurals* (30, `#infl:number`) | `modal` |
| u4 Describing things | adjectives* (31, + `#infl:agreement`), body (28), adverbs (18), colours (13), possessives* (5, + `#infl:agreement`) | |
| u5 Around town | city (28), travel (23), kitchen (29), prepositions* (19) | `prep:articulated` |
| u6 The past | work (28), feelings (23), passato-prossimo* (20), passato-prossimo-essere* (16) | `tense:passato_prossimo`, `aux:essere` |
| u7 Memories | weather (26), animals (21), clothes (22), imperfetto* (20) | `tense:imperfetto` |
| u8 Plans for the future | leisure (23), shopping (20), futuro* (18), futuro-irregular* (16) | `tense:futuro`, `irregular:futuro` |
| u9 Talking about life | more-verbs (30), ideas (28) | |

**Dutch 1.2.0** — 37 skills, 712 taught items, 1597 facets, 16 539 sentences (2338 generated).

| Unit | Skills (items) | Introduces |
|---|---|---|
| u1 Basics | greetings (20), little-words (39), people (29), present-regular* (20) | |
| u2 Daily life | food (23), numbers (25), present-irregular* (15), home (28), de-het* (69) | `modal` |
| u3 Everyday life | time (32), family (17), everyday-verbs (30), pronouns* (12), separable* (21), plurals* (30, `#infl:number`) | `separable` |
| u4 The perfect tense | work (27), feelings (22), perfectum-hebben* (20), perfectum-zijn* (16) | `tense:perfectum`, `aux:zijn` |
| u5 Describing things | adjectives* (31, + `#infl:agreement`), body (27), adverbs (21), colours (12), possessives* (7), diminutives* (25, `#infl:diminutive`) | |
| u6 Around town | city (26), travel (22), kitchen (29), shopping (18) | |
| u7 The simple past | weather (25), animals (21), clothes (22), verleden-tijd-weak* (20), verleden-tijd-strong* (20) | `tense:verleden_tijd`, `irregular:verleden_tijd` |
| u8 Free time and ideas | leisure (22), more-verbs (31), ideas (27) | |

**Spanish 1.0.0** (v0.6 pilot) — 46 skills, 1002 taught items, 2219 facets, 23 776 sentences (3244
generated, 14 %); peninsular standard with all six persons (vosotros), notes on Latin America.

| Unit | Skills (items) | Introduces |
|---|---|---|
| u1 Basics | greetings (23), little-words (45), people (32), ser* (1), estar* (1) | |
| u2 The present tense | food (37), numbers (41), present-ar* (16), articles* (54), present-er-ir* (15) | |
| u3 Everyday life | time (52), home (51), prepositions* (21), stem-changing* (15), irregular-present* (12) | `prep:contraction` |
| u4 Wants and likes | everyday-verbs (30), body (41), adverbs (27), verb-phrases* (4), object-pronouns* (10), gustar* (8) | `modal`, `gerund` |
| u5 People and things | family (26), adjectives* (53, + `#infl:agreement`), plurals* (17, `#infl:number`), colours (13, + `#infl:agreement`), possessives* (8, + `#infl:agreement`) | |
| u6 Around town | city (40), travel (40), shopping (25), kitchen (30), reflexive* (12), clothes (31) | `reflexive` |
| u7 The recent past | work (44), feelings (34), preterito-perfecto* (16), participles-irregular* (10) | `tense:preterito_perfecto`, `irregular:preterito_perfecto` |
| u8 The simple past | weather (36), animals (35), leisure (29), indefinido* (16), indefinido-irregular* (14) | `tense:preterito_indefinido`, `irregular:preterito_indefinido` |
| u9 Memories and plans | imperfecto* (16), futuro* (14), futuro-irregular* (9), more-verbs (30), ideas (46) | `tense:imperfecto`, `tense:futuro`, `irregular:futuro` |

Spanish curation (seed.yaml): `exclude_moods` keeps subjunctive, conditional and imperative forms
out (23 825 Tatoeba candidates skipped), `exclude_words` keeps voseo out, `exclude_sentences` lists
the sentences the native review (`docs/samples/es_exercises.txt`) rejected. One grammar slot stays
empty: `sentar.yo` (*me siento* is read as *sentir*, which shares the spelling).

Notes: item-based grammar skills (pronouns, prepositions, separable; Dutch possessives, where
only *ons/onze* inflects) train `#rec`/`#prod` of their words and come with a grammar note.
Adjectives and Italian possessives add `#infl:agreement`; plurals and diminutives train only
`#infl`. Dutch diminutives have few sentences (median 1 per noun with an asked cell; the picker
carries the skill), and the Dutch `comparison` table is imported but no skill trains it yet. Split
separable verbs are aligned (*sta … op*), but the separable skill still trains only `#rec`/`#prod`.
Italian reflexive (pronominal) verbs are still excluded from the pool.

**Sarnami 0.2.0 (local only, unverified)** — 35 skills, 394 taught items, 990 facets, 3004 sentences
(1772 [source] examples, 1214 generated `claude-gen`, 18 [source]); 6284 items, 742 verb tables.
Grammar first: `base_features` is empty, every tense and construct has its own skill.

| Unit | Skills (items) | Introduces |
|---|---|---|
| u1 Eerste stappen | basics (22), pronouns (9), copula* (1), people (15) | `tense:present` |
| u2 Familie | family (16), present* (20), negation (6), numbers (18) | `negation` |
| u3 Vragen en bezit | questions (8), possessives (9), body (20), present-more* (20) | `question`, `possessive` |
| u4 Eten en drinken | food (26), present-progressive* (15), adjectives (26) | `tense:present_progressive` |
| u5 Thuis | home (24), clothes (16), past-tr* (20), past-intr* (15) | `tense:past` |
| u6 Buiten | nature (22), animals (18), perfect* (20), places (17) | `tense:perfect` |
| u7 Tijd | time (28), past-progressive* (12), future* (20), shopping (15) | `tense:past_progressive`, `tense:future` |
| u8 Werk en gevoel | work (16), modal* (2), feelings (17), actions (30) | `modal` |
| u9 Beleefd en wensen | polite (7), subjunctive* (15), travel (15), celebrations (15) | `polite`, `tense:subjunctive` |

## Generated sentences (`pipeline/generate.py`, `pipeline/gaps.py`)

Real Tatoeba sentences come first. Where a skill still has too few **easy** sentences (allowed at the
skill, at most one word taught later; the report's `easy` column), Claude writes short everyday
sentences with their translations (`src: "claude-gen (skill: target)"`, `tr_src: claude-gen`):

* **Gaps** (`gen gaps`): grammar slots (verb × person of the skill's tense) with fewer than 8 easy
  sentences (impersonal verbs, `succedere` / `gebeuren`: third persons only), vocabulary items with
  fewer than 3, skills with fewer than 40 (unit-1 skills: 150).
* **Drafts** (JSON lines): `{"skill", "target", "text", "en", "nl"}`, where `target` is `LEMMA
  TENSE.PERSON` (the verb form the sentence must show), `LEMMA` (an item) or absent (any item of
  the skill). `gen context` prints a skill's allowed features, slots and known vocabulary.
* **Checks** (`gen check` / `gen add`): tokenizes and aligns like the importer (with the English
  translation, for imperatives); every word links to an item except the allowed names
  (`generate.NAMES`, not sentence-initial) and digits; the target is aligned to the intended item
  and form; the features are allowed at the skill and the home-skill rule accepts the sentence; at
  most one word is taught after the skill; translations exist and pass `trcheck.py`; the text is
  new. Failures are reported with a reason and not added.
* **Files**: accepted sentences get permanent ids `g:{course}:{n}` from `sentence_ids.tsv`
  (append-only, keyed by the normalized text) and go to `sentences/gen-{unit}.jsonl`. The importer
  keeps them; after an import, `gen refresh` re-aligns them (a sentence that no longer passes is
  reported, and dropped with `--drop`).
* The app ranks a generated sentence after unseen Tatoeba sentences with as many unknown words
  (`kGeneratedSentenceWeight`, docs/engine.md).

## Graded stories (`pipeline/stories.py`)

2–3 short stories per unit (5–10 sentences, 3–5 comprehension questions), written by Claude
(`src: claude-gen`), using only the vocabulary taught up to the unit and only the grammar allowed
there (docs/ARCHITECTURE.md, "Stories"). One YAML list per unit:

```yaml
- id: u3-chiavi                       # permanent, unique in the course
  unit: u3                            # whose words and grammar it uses; the app unlocks it there
  new_words: [ritardo]                # at most one lemma taught later (or never), glossed in the reader
  names: [Rex]                        # extra names besides generate.NAMES
  title: {it: "Dove sono le chiavi?", en: "Where are the keys?", nl: "Waar zijn de sleutels?"}
  sentences:
    - {it: "È lunedì mattina e Paolo è in ritardo.", en: "It's Monday morning and Paolo is late.", nl: "..."}
  questions:
    - q: {en: "Where are the keys?", nl: "Waar liggen de sleutels?"}   # source language (required)
      prompt: "Dove sono le chiavi?"          # optional target-language question (checked like a sentence)
      options: ["in giardino", "in cucina", "in bagno"]   # target-language strings (checked) ...
      # options: [{en: "The keys", nl: "De sleutels"}, ...]   # ... or source-language i18n
      answer: 0                               # the correct index (the app shuffles the options)
      why: {en: "Sentence 5.", nl: "Zin 5."}  # optional explanation
```

* **Checks** (part of `validate`, so `build` fails on them; `python -m pipeline stories it` runs only
  these): every title, sentence, target prompt and target option tokenizes and aligns like the
  importer; every word is aligned to an item or is a name (`generate.NAMES` + `names`, anywhere in
  the sentence, even when it is also an item: *Roma*) or a number; every item is taught in the
  story's unit or earlier (the unit of the first skill selecting it), except at most one distinct
  lemma per story, which must be declared in `new_words`; the features (`features.py`) are allowed at
  the unit (base ∪ everything introduced by this or an earlier unit); 5–10 sentences of at most 14
  words with every course translation, passing `trcheck.py`; 3–5 questions with 3–4 options,
  non-empty and distinct after folding case, punctuation and accents (like the engine's
  `OptionPicker`), not mixing target and translated options, `answer` in range, i18n complete.
* `--show u3` (or `all`) prints each story's tokens as `word/lemma[tense.person]`, for reviewing the
  alignment the reader's word popovers will show (the aligner's limits apply: *sono* without a
  subject reads as *io*, a noun right after *e* may read as a verb (*sale* → *salire*): rephrase).
* **Compiled** into `stories`, `story_sentences` and `story_questions`; the sentences go into
  `sentences` + `tokens` + `sentence_features` with ids `st:{storyId}.{n}` and src
  `claude-gen (story: {storyId})` (the app keeps them out of the exercise pool). Tokens are aligned at
  build time (nothing is stored in the YAML), so an import that changes the lexicon re-aligns them,
  and a story that no longer passes fails the build.
* 2026-10: it 18 stories (132 sentences, 61 questions), nl 16 (117 sentences, 51 questions), 2 per unit.

## IDs

`{course}:{lemma}` (spaces → `_`), homographs `{course}:{lemma}.{n}`; the most frequent homograph
gets the plain id on first import. `ids.tsv` maps (lemma, POS) → id, is append-only, and is reused
by every import, so ids never change or get reused. Sentence ids: `s:{tatoebaId}` (Tatoeba), `g:{course}:{n}` (generated, `sentence_ids.tsv`).

## Compiler, validator, report

* `compile.py` executes `schema/course_db.sql` verbatim, fills meta (incl. `attribution`,
  `built_at`, `schema_version`, `unverified`), resolves skills into `skill_items` and `skill_facets`
  (vocab → `#rec` + `#prod`; verb grammar → `#form:{tense}`; `facet: article` → `#article`;
  `inflections: {table: T}` → `#infl:T`, see above), writes `inflections` and
  `meta.inflection_tables`, and VACUUMs. `COURSE_DB_SCHEMA_VERSION = 1`, `COURSE_DB_SCHEMA_MINOR = 1`
  (`meta.schema_minor`, also in `dist/index.json` per course); a pack with `#infl` facets gets
  `meta.min_app_version = 0.4.0` (`MIN_APP_VERSION_INFL`; course.yaml `min_app_version` overrides).
* `validate.py` fails the build on: schema errors, duplicate ids, ids.tsv mismatches, unknown or
  cyclic prerequisites, too few items / verbs with complete tables, missing translations on skill
  items, articles outside `meta.articles`, stem+ending ≠ form, undeclared tenses/persons, tokens that
  don't re-render the text, unknown token lex, token forms missing from the verb table, missing
  en/nl grammar notes, base features/`introduces` that are no tense and have no detector, and
  sentences whose features their home skill does not allow, and stories that fail the story checks.
* `report.py` prints per skill: items, facets, sentences touching the skill (`sents`), the ones whose
  features the skill allows (`fit`) and of those the ones with at most one word taught later
  (`easy`), the features it introduces, and for verb skills the number of complete tables and fit
  sentences with an aligned form per verb (min/median, person slots); plus sentences per feature.
