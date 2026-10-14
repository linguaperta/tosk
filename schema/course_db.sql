-- Compiled course database: the contract between pipeline/ (writer) and app/ (reader).
-- One file per course (it.sqlite, nl.sqlite, hns.sqlite). Read-only inside the app.
--
-- Schema version lives in PRAGMA user_version AND meta.schema_version.
-- Bump COURSE_DB_SCHEMA_VERSION (pipeline/pipeline/compile.py and app/lib/data/course/course_schema.dart)
-- on any breaking change. The app refuses packs whose major schema version it doesn't know.
--
-- Conventions
--   * JSON columns hold UTF-8 JSON text. "i18n" = object keyed by source-language code: {"en": "...", "nl": "..."}.
--   * Every list column is a JSON array; never NULL (use '[]' / '{}').
--   * Language-specific vocabulary (persons, tenses, articles) is DATA in meta, never code in the app.

PRAGMA user_version = 1;

CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
-- Required keys (values are text; JSON where noted):
--   schema_version   '1'
--   course_id        'it' | 'nl' | 'hns'
--   version          semver of the pack, e.g. '1.0.0'
--   title            i18n JSON, e.g. {"en":"Italian","nl":"Italiaans"}
--   target           target language code, e.g. 'it'
--   translations     JSON array of source languages with translations, e.g. ["en","nl"]
--   persons          JSON array of person keys in display order, e.g. ["io","tu","lui/lei","noi","voi","loro"]
--   tenses           JSON array of tense keys, e.g. ["presente","passato_prossimo"]
--   tense_labels     JSON {tense: i18n}, e.g. {"presente":{"en":"present","nl":"tegenwoordige tijd"}}
--   articles         JSON array of article strings used as options in article exercises, e.g. ["de","het"]
--   unverified       '0' | '1'   (course content not yet checked by a speaker)
--   built_at         ISO-8601 UTC timestamp
--   attribution      text/markdown attribution for the content sources
-- Optional keys:
--   person_labels    JSON {person: i18n} when the person key isn't self-explanatory
--   description      i18n JSON
--   base_features    JSON array of grammar features allowed from the start, e.g. ["tense:presente"]
--                    (see sentence_features / skill_features)

CREATE TABLE units (
  id     TEXT PRIMARY KEY,           -- 'u1'
  ord    INTEGER NOT NULL,           -- 0-based display order
  title  TEXT NOT NULL               -- i18n JSON
);

CREATE TABLE skills (
  id         TEXT PRIMARY KEY,       -- 'present-are' (unique within the course)
  unit_id    TEXT NOT NULL REFERENCES units(id),
  ord        INTEGER NOT NULL,       -- order within unit
  kind       TEXT NOT NULL CHECK (kind IN ('vocab','grammar')),
  title      TEXT NOT NULL,          -- i18n JSON
  icon       TEXT,                   -- icon key, e.g. 'wave' (app maps to an icon; unknown -> default)
  tense      TEXT,                   -- for verb grammar skills: the tense trained, else NULL
  exercises  TEXT NOT NULL DEFAULT '[]', -- JSON array of allowed exercise type ids; [] = all applicable
  pos_x      INTEGER,                -- optional layout override (column)
  pos_y      INTEGER,                -- optional layout override (row/layer)
  query      TEXT NOT NULL DEFAULT '{}'  -- the original selection query from course.yaml, for reference/debug
);

CREATE TABLE skill_requires (
  skill_id    TEXT NOT NULL REFERENCES skills(id),
  requires_id TEXT NOT NULL REFERENCES skills(id),
  PRIMARY KEY (skill_id, requires_id)
);

-- Grammar notes, markdown. One row per (skill, language). lang = source language of the note.
-- The app picks the user's source language, falling back to 'en', then any.
CREATE TABLE notes (
  skill_id TEXT NOT NULL REFERENCES skills(id),
  lang     TEXT NOT NULL,
  md       TEXT NOT NULL,
  PRIMARY KEY (skill_id, lang)
);

-- Every lexical item in the pack (skill members AND the wider distractor pool).
CREATE TABLE items (
  id        TEXT PRIMARY KEY,        -- permanent, never reused: '{course}:{lemma}' or '{course}:{lemma}.{n}' for homographs
  pos       TEXT NOT NULL,           -- 'noun','verb','adj','adv','pron','det','prep','conj','num','intj','phrase',...
  lemma     TEXT NOT NULL,           -- citation form in the target language
  article   TEXT,                    -- definite article if the language has one and it's a noun: 'il','la','de','het'
  gender    TEXT,                    -- 'm','f','n','c' or NULL
  plural    TEXT,                    -- noun plural or NULL
  freq      INTEGER,                 -- frequency rank (1 = most frequent); NULL if unknown
  unit_id   TEXT,                    -- unit the item is introduced in (NULL for distractor-pool-only items)
  tr        TEXT NOT NULL,           -- JSON {"en":["to eat"],"nl":["eten"]}; first entry per language is the primary gloss
  variants  TEXT NOT NULL DEFAULT '[]', -- JSON array of accepted alternative target spellings
  tags      TEXT NOT NULL DEFAULT '[]'  -- JSON array (also normalized into item_tags)
);
CREATE INDEX items_freq ON items(freq);
CREATE INDEX items_pos  ON items(pos, freq);

CREATE TABLE item_tags (
  item_id TEXT NOT NULL REFERENCES items(id),
  tag     TEXT NOT NULL,
  PRIMARY KEY (tag, item_id)
);

-- Verb metadata. One row per verb item.
CREATE TABLE verbs (
  item_id    TEXT PRIMARY KEY REFERENCES items(id),
  class      TEXT,                   -- 'are','ere','ire','isc', 'weak','strong', ... (course-defined)
  stem       TEXT,                   -- citation stem, e.g. 'mang'
  irregular  INTEGER NOT NULL DEFAULT 0,
  auxiliary  TEXT                    -- perfect auxiliary(ies) if relevant: 'avere','essere','hebben','zijn','hebben|zijn'
);

-- Full conjugation tables. Non-finite forms use person '_' (e.g. tense 'participle', person '_').
CREATE TABLE verb_forms (
  item_id  TEXT NOT NULL REFERENCES items(id),
  tense    TEXT NOT NULL,            -- one of meta.tenses, or 'infinitive','participle','gerund'
  person   TEXT NOT NULL,            -- one of meta.persons, or '_'
  form     TEXT NOT NULL,            -- the canonical form, may be multi-word ('ho mangiato', 'heb gegeten')
  stem     TEXT,                     -- stem part for the ending-picker ('mang'); NULL if the split isn't meaningful
  ending   TEXT,                     -- ending part ('iamo'); stem||ending == form when both non-NULL
  alts     TEXT NOT NULL DEFAULT '[]', -- JSON array of accepted alternative forms
  PRIMARY KEY (item_id, tense, person)
);
CREATE INDEX verb_forms_form ON verb_forms(form);

CREATE TABLE sentences (
  id      TEXT PRIMARY KEY,          -- 's:{tatoebaId}' or another stable id
  text    TEXT NOT NULL,             -- target-language sentence
  tr      TEXT NOT NULL,             -- JSON {"en":"We eat at eight.","nl":"We eten om acht uur."} (at least one)
  src     TEXT,                      -- 'tatoeba:4821'
  unit_id TEXT                       -- earliest unit whose vocabulary covers the sentence, if computed
);

-- Tokenization of the target sentence. Concatenating t with the whitespace in 'pre' rebuilds the text.
CREATE TABLE tokens (
  sentence_id TEXT NOT NULL REFERENCES sentences(id),
  idx         INTEGER NOT NULL,      -- 0-based
  t           TEXT NOT NULL,         -- surface token (words and punctuation are separate tokens)
  pre         TEXT NOT NULL DEFAULT '', -- whitespace before this token (usually ' ' or '')
  is_word     INTEGER NOT NULL DEFAULT 1, -- 0 for punctuation
  lex         TEXT,                  -- item id, if aligned
  form        TEXT,                  -- '{tense}.{person}' for verb forms, e.g. 'presente.noi'; NULL otherwise
  PRIMARY KEY (sentence_id, idx)
);
CREATE INDEX tokens_lex ON tokens(lex, form);

-- Skill membership, resolved from the course.yaml query at compile time (ordered by freq).
CREATE TABLE skill_items (
  skill_id TEXT NOT NULL REFERENCES skills(id),
  item_id  TEXT NOT NULL REFERENCES items(id),
  ord      INTEGER NOT NULL,         -- introduction order within the skill (0 = first)
  PRIMARY KEY (skill_id, item_id)
);
CREATE INDEX skill_items_item ON skill_items(item_id);

-- Facets trained by each skill, derived at compile time. Facet id scheme (see docs/ARCHITECTURE.md):
--   '{itemId}#rec'          recognize (target -> meaning)
--   '{itemId}#prod'         produce (meaning -> target)
--   '{itemId}#form:{tense}' a verb's forms in one tense
--   '{itemId}#article'      a noun's article/gender
-- A facet may belong to several skills; progress is per facet, so practice counts everywhere.
CREATE TABLE skill_facets (
  skill_id TEXT NOT NULL REFERENCES skills(id),
  facet_id TEXT NOT NULL,
  item_id  TEXT NOT NULL REFERENCES items(id),
  kind     TEXT NOT NULL CHECK (kind IN ('rec','prod','form','article')),
  tense    TEXT,                     -- for kind = 'form'
  ord      INTEGER NOT NULL,         -- introduction order (matches skill_items.ord of the item)
  PRIMARY KEY (skill_id, facet_id)
);
CREATE INDEX skill_facets_facet ON skill_facets(facet_id);

-- Grammar gating (docs/ARCHITECTURE.md, "Grammar gating"; additive, schema version stays 1).
-- Feature names are course data: 'tense:{tense}' plus construct features the course declares
-- ('aux:essere', 'modal', 'prep:articulated', 'separable', 'irregular:{tense}', ...).
-- Grammar features each sentence uses, derived by the pipeline from token alignment plus language rules.
CREATE TABLE sentence_features (
  sentence_id TEXT NOT NULL REFERENCES sentences(id),
  feature     TEXT NOT NULL,
  PRIMARY KEY (sentence_id, feature)
);
-- Features a skill introduces (course.yaml 'introduces', plus 'tense:{T}' for a verbs grammar skill).
CREATE TABLE skill_features (
  skill_id TEXT NOT NULL REFERENCES skills(id),
  feature  TEXT NOT NULL,
  PRIMARY KEY (skill_id, feature)
);
