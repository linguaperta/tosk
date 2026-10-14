# Roadmap

Direction (14 October 2026): the app is a **player for language packs**, and the pack format plus a tool suite for making packs is the product. See [VISION.md](VISION.md).

The detailed task list lives in [BACKLOG.md](../BACKLOG.md). This page is the release-level view.

| Release | Theme | Status |
| --- | --- | --- |
| v0.1 (preview 1) | Full stack on real it/nl packs: map, lessons, lab, non-stop, progression, settings | shipped 13 Oct 2026 |
| v0.2 (preview 2) | Real-pack correctness (compound tenses, Dutch clause rules), fast exercise generation | shipped 13 Oct 2026 |
| **v0.3** (preview 3) | Bigger grammar-first courses, AI explanations, flagging, sounds, mistake review, one-handed layout, B/W e-ink mode, reference, course picker, backup, daily goal, typing mode, Sarnami (local) | shipped 14 Oct 2026 |
| v0.4 | Content downloads and sync | planned |
| v0.5 | Handwriting and e-ink (Boox), listening | built; device testing pending ([checklist](device-testing.md)) |
| v0.6 | New full-size courses: Spanish, Portuguese, French, Esperanto, Swedish, Norwegian, Danish | planned |
| v0.8 | Pack toolkit: open pack spec, `pack new` / `from-text` / `draft --ai`, extension packs (`extends`), custom catalog URLs, license and sources in the course preview, a "read a book" pack (Montalbano) | planned |
| Later | RPG/forest layer, ghost race | parked |

## v0.3

- **Curriculum:** 8–10 units, ~30 skills and up to ~1000 taught words per course. Italian adds imperfetto, futuro, passato prossimo with essere, possessives, articulated prepositions, plurals and agreement, and modals; Dutch adds verleden tijd (weak and strong), modals, separable verbs, plurals, adjective endings and diminutives.
- **Grammar-first gating:** sentences in exercises only use grammar you've already started, and only a little unknown vocabulary (≤1 unknown word in grammar exercises, ≤2 in vocabulary). Contract: ARCHITECTURE.md, "Grammar gating".
- **One-handed layout:** exercise controls sit at the bottom of the screen (thumb zone).
- **Explain answer with AI:** after any checked answer, if a Claude or OpenAI key is configured in Settings (otherwise the button doesn't exist). Replies stream and are cached offline; without a network the bundled grammar note is shown.
- **Flag an exercise:** a reason plus a comment. *Submit* saves it on the device, to be exported as a `.jsonl` for the developer. *Confer with AI* checks your complaint, including telling you if your correction is wrong.
- **Sounds:** a satisfying correct sound, a lesson-complete fanfare, and a muted select tick, with a toggle in Settings.
- **Mistake review:** practice the exercises you got wrong, plus a list of mistakes.
- **Black & white e-ink mode** for the Boox: nothing is conveyed by color, there are no animations, and it's tested on every screen.
- **QA pass:** every flow on both courses, phone and desktop sizes, dark mode, large text.
- **Sarnami (`hns`):** a Dutch–Sarnami course from the [source] dictionary, marked unverified and kept local-only ([source] copyright), loaded from a file.

## v0.4: content downloads and sync

- `GitHubPackSource`: packs published on tosk-data GitHub Releases, read from `index.json`, with version check, checksum and atomic swap. App updates are then no longer needed for content.
- `DriveSyncBackend`: the review log is synced through the Google Drive `appDataFolder` (a union merge, so there are no conflicts), with file export/import on desktop and web.
- Optionally the iOS build (needs a Mac).

## v0.5: handwriting, e-ink, listening

- **Answer input: Write.** ML Kit Digital Ink on a writing pad in cloze, conjugation pick and grid, sentence builder and transform (Android and iOS); the course's model is downloaded once (about 20 MB) and works offline; the answer counts when any of the top readings is right. Sarnami uses the Dutch model.
- **Boox:** the Onyx pen SDK draws on the pad with e-ink latency, and a full e-ink refresh follows each lesson (Settings → E-reader).
- **Listening:** `listen_pick`, the 10th exercise type, with on-device text-to-speech (where the phone has a voice for the language; never for Sarnami), plus 🔊 pronounce buttons on word popovers, flashcards and word pages.
- What needs checking on the phone and the Boox: [device-testing.md](device-testing.md).

## v0.6: new full-size courses

These are the "easy" languages for this pipeline: good Wiktionary conjugation coverage, plenty of Tatoeba sentences, frequency lists, and space-separated Latin script. Spanish comes first as the pilot, then Portuguese, French, Esperanto, Swedish, Norwegian (Bokmål) and Danish. Each is built at the expanded it/nl scale (~30 skills and ~1000 words) with grammar-first gating and Dutch and English translations.

German and the Slavic languages follow once inflection tables are generalized beyond verbs (the declension extension, a v0.4 candidate).

## Parked

Forest skin and the RPG layer (regions, lanterns, dungeons and bosses, a spellbook, a mistake garden, amber, gear), personalized vocabulary packs, reading readiness for a target book, the ghost race, and optional monetization.
