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
python -m pytest pipeline/tests                                # offline tests
```

* **Content root** (the folder with `it/`, `nl/`): `--content-root`, else `$TOSK_CONTENT`, else
  `../tosk-data/content` next to the repo root, else `C:/Users/timo/Repositories/tosk-data/content`
  (so git worktrees find the data checkout). `dist/` is the sibling of the content root.
* **Cache**: `%LOCALAPPDATA%\tosk-cache` (override with `TOSK_CACHE`). Never committed.
* `build --install` copies the packs to `app/assets/courses/{id}.sqlite` (bundled with the app).
* `build` needs only the committed JSONL/YAML/markdown, so it works offline and is deterministic apart from
  `meta.built_at`.

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

### course.yaml queries

Skills select items with queries (resolved identically by importer and compiler, `pipeline/query.py`):

* `items: {tags, pos, lemmas, exclude, top, min}` (vocab skills; with `facet: article` the skill trains
  `#article` of nouns that have an article)
* `verbs: {tense, class, regular, aux, lemmas, exclude, top, min}` (grammar skills): verbs with a
  **complete** table (all persons) for `tense`; `regular: true` = the tense is not in the verb's
  `irregular_in`; `aux` = the primary perfect auxiliary.
* Order = frequency rank (an explicit `lemmas` list without `top` keeps its own order).
* Minimum (validator): `min`, else for verb queries `len(lemmas)` or `min(15, top)`, else 5 items.

### seed.yaml (curation)

```yaml
exclude: [coso, sulla/noun]              # never in the frequency pool
items:
  - {lemma: ciao, pos: intj, tags: [greetings], en: [hi, bye], nl: [hoi, doei]}
  - {lemma: del, pos: prep, en: [of the], nl: [van de], inflections: [della, dei]}
  - {lemma: pensare, pos: verb, nl: [denken]}      # gloss override only
```

`tags` put the word in vocab skills; glosses written here get `tr_src: claude`.

## What the importer does

1. Parses the filtered Wiktionary entries: POS, cleaned short English glosses, gender, plural,
   inflections, and the **first** conjugation table (later tables hold archaic/regional variants).
   Forms tagged archaic, regional, formal, subjunctive, conditional, imperative, historic past, ...
   are dropped. Italian pronunciation accents on non-final vowels are stripped (`màngio` → `mangio`).
2. Frequency rank per (lemma, POS): count of the lemma plus its inflected forms. Homographs: the full
   lemma count goes to the function word / verb / entry with most senses; others get 0.5 %; a lemma
   that is also a form of another word gets 10 % (1 % for verbs, e.g. Dutch *waren*).
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
   linked), duplicates removed, at most one unlinked word (names and numbers don't count) and ≥ 80 %
   linked. Greedy selection, shortest/cleanest first, while a quota is open: 25 sentences per skill
   item, 24 per (grammar verb, tense) and up to 5 per (verb, tense, person), always accepting up to 2
   per person. `unit` = the latest unit among the skill items in the sentence.

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
  (Italian: within 4 words before; Dutch: anywhere in the clause, not after *te*) → the participle
  token gets `form = passato_prossimo.{person}` / `perfectum.{person}` and the auxiliary token gets
  its own present form. *The participle token's text is only part of the multi-word form in
  `verb_forms`* (`mangiato` vs `ho mangiato`). Participles without auxiliary → `participle._`.
* Ambiguous persons: an adjacent subject pronoun decides; a pronoun that fits no form (subjunctive)
  leaves `form` unset; Dutch infinitive after *te* or a finite verb in the clause; a name/noun subject
  requires a 3rd-person form (else unset); Italian *sono*: following -i/-e adjective/participle =
  *loro*, else *io*; otherwise 3rd singular, 3rd plural, first person in order.
* Dutch inversion (`werk jij`) and imperatives keep `lex` but get no `form`.
* Unmatched tokens stay unlinked.

## IDs

`{course}:{lemma}` (spaces → `_`), homographs `{course}:{lemma}.{n}`; the most frequent homograph
gets the plain id on first import. `ids.tsv` maps (lemma, POS) → id, is append-only, and is reused
by every import, so ids never change or get reused. Sentence ids: `s:{tatoebaId}`.

## Compiler, validator, report

* `compile.py` executes `schema/course_db.sql` verbatim, fills meta (incl. `attribution`,
  `built_at`, `schema_version`, `unverified`), resolves skills into `skill_items` and `skill_facets`
  (vocab → `#rec` + `#prod`; verb grammar → `#form:{tense}`; `facet: article` → `#article`) and VACUUMs.
  `COURSE_DB_SCHEMA_VERSION = 1`.
* `validate.py` fails the build on: schema errors, duplicate ids, ids.tsv mismatches, unknown or
  cyclic prerequisites, too few items / verbs with complete tables, missing translations on skill
  items, articles outside `meta.articles`, stem+ending ≠ form, undeclared tenses/persons, tokens that
  don't re-render the text, unknown token lex, token forms missing from the verb table, missing
  en/nl grammar notes.
* `report.py` prints per skill: items, facets, sentences touching the skill, and for verb skills the
  number of complete tables and sentences with an aligned form per verb (min/median, person slots).
