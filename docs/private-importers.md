# Source-specific code for copyrighted sources: audit (v0.8)

*Audit of 20 October 2026, for docs/VISION.md ("Public code stays generic") and docs/pack-format.md, Appendix A. Nothing has been moved yet: this file only lists what has to move to a private module or repository **before any repository goes public**.*

The rule (VISION): public tools are generic (JSONL, CSV, Wiktionary/kaikki, Tatoeba, plain text). Importers, parsers, scrapers and reference data aimed at one specific copyrighted source stay private. Packs built from such sources stay local (`local/`, git-ignored). The open-data importers for Italian and Dutch (kaikki/Wiktionary, Tatoeba, hermitdave/FrequencyWords) are fine to publish.

## Must move (code aimed at a specific copyrighted source)

| Path | What it is | Source it targets |
| --- | --- | --- |
| `pipeline/pipeline/hns/sil.py` | polite scraper (URLs, user agent, rate limit) and HTML parser of the [source] dictionary pages | [source] Suriname, *Nederlands‚ÄìSarnami woordenboek* (¬© [source] Global, all rights reserved) |
| `pipeline/pipeline/hns/lexicon.py` | inverts parsed [source] entries (Dutch headword ‚Üí Sarnami) into lexemes; [source] POS abbreviations | [source] dictionary |
| `pipeline/pipeline/hns/ivt.py` | parser for the archive.org DjVu OCR of the 1991 word list (column layout, OCR fixes) | Instituut voor Taalwetenschap, *Woordenlijst Sarnami Hindoestani‚ÄìNederlands* (1991) |
| `pipeline/pipeline/hns/nt.py` | text extraction and word counts of the Sarnami New Testament PDF | [source] NT (CC BY-NC-ND 3.0: no derivatives, so frequencies only) |
| `pipeline/pipeline/hns/sources.py` | source registry with download URLs ([source], archive.org copies of [source] 1991, [source]© 1985 and [source], [source], two [source] readers) and the downloader | all of the above, [source]© 1985, [source] |
| `pipeline/pipeline/hns/importer.py` | the `import hns` pipeline: [source] + [source] merge, NT frequencies, [source]/[source] example sentences, [source]© paradigm check, reports | all of the above |
| `pipeline/pipeline/hns/verify.py` | checks drafted tables against forms attested in [source] examples and against the (local) [source]© reference paradigms | [source] dictionary, [source]© 1985 |
| `pipeline/pipeline/hns/grammar.py` | Sarnami conjugation rules; the provenance strings quote short [source]© example forms with ¬ß numbers (`marhe-1985 ¬ß9.7.1 (pa·πõhilƒÅ)`) | [source]© 1985 (rules checked against it), [source] examples |
| `pipeline/pipeline/hns/align.py`, `hns/generate.py` | Sarnami aligner and generated practice sentences | not a copyrighted source themselves, but only used by the private importer; move them with it (or keep them as a generic "analytic verb forms" aligner later) |
| `pipeline/pipeline/hns/template/` (`course.yaml`, `seed.yaml`, `grammar/*.nl.md`) | the Sarnami course template: the description and attribution name the sources; `seed.yaml` lists [source] Dutch headwords per tag; the grammar notes cite [source]© paragraphs | [source] dictionary, [source]© 1985 |
| `pipeline/tests/test_hns_sil.py`, `test_hns_import.py`, `test_hns_grammar.py`, `test_hns_sources.py` | tests of the above | (move with the code) |
| `pipeline/tests/fixtures/hns/` | **synthetic** imitations of the [source] HTML and the [source] DjVu XML (invented rows, no source text), but shaped after those sources | (move with the code) |
| `docs/sarnami.md` | the Sarnami build notes: source list with rights, [source]© ¬ß-references and example paradigms, open questions | describes the sources; move or reduce to a public summary |

## Hooks in generic code that reference the private part

These must be replaced by a plugin/registration point (or kept as a generic "restricted course" safeguard) when `hns/` moves out:

| Path | Reference |
| --- | --- |
| `pipeline/pipeline/__main__.py` | `fetch hns` ‚Üí `hns.sil.fetch_all` + `hns.sources.fetch_sources`; `import hns` ‚Üí `hns.importer.run_import`; help texts mention [source] |
| `pipeline/pipeline/build.py`, `publish.py`, `cli.py` | import `hns.safeguard` (`RESTRICTED_COURSES`, `check_destination`, `local_content_root`) and `hns.install` (desktop copy). The safeguard contains no source content and protects public locations: move it to a generic module (e.g. `pipeline/restricted.py`) and keep it public |
| `pipeline/pyproject.toml` | `packages = [..., "pipeline.hns"]` and its package data |
| `pipeline/requirements.txt` | `pypdf` (only for `hns/nt.py`) |
| `schema/lexicon.schema.json` | `tr_src` enum lists `sil` and `[source]` (source names in the public schema; harmless, but see pack-format.md Open issues: the enum should become an open tag) |
| `pipeline/pipeline/report.py` | docstring example `[source]:a.html#aan` (harmless) |

## Not source-specific (can stay public)

- `hns` as a **language** in the app: the handwriting-model fallback (`ink/ink_recognizer.dart`: `hns` ‚Üí `nl`), the AI prompt language name (`ai/prompts.dart`), the "no TTS voice" notes, `ui/settings/answer_input_section.dart`. They name the language, not a source.
- App tests that read the locally built pack when it exists (`test/engine/hns_pack_validity_test.dart`, `special_letters_test.dart`, `app/boot_test.dart`, `data/local_pack_source_test.dart`): they skip without the local file and contain no source data. The hard-coded `C:/Users/timo/...` default path should become an environment variable only.
- `local/` (git-ignored): the scraped HTML, the JSONL, the transcribed [source]© paradigms (`local/sources/hns/marhe-1985-paradigms.yaml`) and `hns.sqlite`. Never committed, so nothing to move; it was not read for this audit.
