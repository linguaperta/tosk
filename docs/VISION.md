# Vision

*Agreed with the project owner, 14 October 2026.*

## The pack format is the product

The app is a **viewer and player for language packs**. It knows no language: everything (words, conjugation and inflection tables, sentences, grammar notes, course structure, stories) comes from the pack. Anyone can make packs for any language or purpose.

- **The pack format is an open, versioned spec.** It consists of `schema/course_db.sql`, the JSON schemas in `schema/`, and the conventions in `docs/ARCHITECTURE.md` (facets, grammar gating, inflection tables, stories), written up as one standalone spec in `docs/pack-format.md` (format 1.0). The app refuses packs with an unknown major schema version.
- **A tool suite lets people build their own courses,** optionally with AI help. It is the pipeline (`pipeline/`) grown into a reusable toolkit (the `pack` command, docs/pack-format.md section 17).
- **Hosting:** the project hosts only **open-licensed packs** (the official catalog: GitHub Releases of `tosk-data`). Anyone can host their own catalog (`index.json`) or share a pack file.
- **Responsibility:** what people build and load for personal use, for example a pack made from a book they own, is their own business. The app plays packs; it does not police their sources. Packs show their own license, sources and authors in the course preview.
- **Public code stays generic.** Importers that target a specific copyrighted source (the Sarnami [source], [source]© and [source] parsers) stay in a private part of the code and never go into a public repo. Public tools are generic: JSONL, CSV, Wiktionary/kaikki, Tatoeba, plain text.

## Use cases

1. **Open courses** for languages big apps ignore, including endangered ones (Sarnami first), built and corrected by whoever cares. A community workflow (suggestions, review, speaker verification) may come later.
2. **Personal packs**, for example **"read Montalbano"**:
   - `pack from-text` analyses a book the user owns.
   - Words are lemmatised with the base course's tables, counted per chapter, and anything the learner already knows (from their progress) is dropped.
   - Units come per chapter ("before chapter 3"), with example sentences from the book.
   - Claude glosses words missing from the dictionaries (Camilleri's Sicilian *vigatese*), labelled as dialect.
   - A **reading readiness** score per chapter ("you know 96% of chapter 4").
   - The pack stays local.
3. **Extension packs:** a pack can `extend` a base course (`extends: it >= 1.2`) and reuse its item IDs (`it:mangiare`). Progress is per facet ID, so words learned in the extension count for the base course and the reverse. The same goes for job vocabularies, song collections or series.

## Tool suite (target)

| Command | Purpose |
| --- | --- |
| `pack new <lang>` | start a course from a template (course.yaml, folders, schema-valid stubs) |
| `pack import â€¦` | generic importers: kaikki/Wiktionary, Tatoeba, CSV/JSONL |
| `pack from-text <file>` | vocabulary and chapter units from a text, plus readiness (personal packs) |
| `pack draft --ai` | AI drafts of glosses, sentences, conjugation tables and grammar notes, always labelled `src: claude-*` |
| `pack validate` / `build` / `publish` | as today (validator, compiler, GitHub Release + index.json) |
| Claude Code skill | "make a pack for this book / this language" end to end |
