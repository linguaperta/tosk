# Roadmap

The detailed task list lives in [BACKLOG.md](../BACKLOG.md). This page is the release-level view.

| Release | Theme | Status |
| --- | --- | --- |
| v0.1 (preview 1) | Full stack on real it/nl packs: map, lessons, lab, non-stop, progression, settings | shipped 13 Oct 2026 |
| v0.2 (preview 2) | Real-pack correctness (compound tenses, Dutch clause rules), fast exercise generation | shipped 13 Oct 2026 |
| **v0.3** | Bigger courses with grammar-first order, AI explanations, flagging, sounds, mistake review, one-handed layout, Sarnami (local) | in progress |
| v0.4 | Content downloads and sync | planned |
| v0.5 | Handwriting and e-ink (Boox), listening | planned |
| Later | RPG/forest layer, personalized vocabulary, reading readiness, ghost race | parked |

## v0.3

- **Curriculum:** 8–10 units, ~30 skills and up to ~1000 taught words per course. Italian adds imperfetto, futuro, passato prossimo with essere, possessives, articulated prepositions, plurals and agreement, and modals; Dutch adds verleden tijd (weak and strong), modals, separable verbs, plurals, adjective endings and diminutives.
- **Grammar-first gating:** sentences in exercises only use grammar you've already started, and only a little unknown vocabulary (≤1 unknown word in grammar exercises, ≤2 in vocabulary). Contract: ARCHITECTURE.md, "Grammar gating".
- **One-handed layout:** exercise controls sit at the bottom of the screen (thumb zone).
- **Explain answer with AI:** after any checked answer, if a Claude or OpenAI key is configured in Settings (otherwise the button doesn't exist). Replies stream and are cached offline; without a network the bundled grammar note is shown.
- **Flag an exercise:** a reason plus a comment. *Submit* saves it on the device, to be exported as a `.jsonl` for the developer. *Confer with AI* checks your complaint, including telling you if your correction is wrong.
- **Sounds:** a satisfying correct sound, a lesson-complete fanfare, and a muted select tick, with a toggle in Settings.
- **Mistake review:** practice the exercises you got wrong, plus a list of mistakes.
- **QA pass:** every flow on both courses, phone and desktop sizes, dark mode, large text.
- **Sarnami (`hns`):** a Dutch–Sarnami course from the [source] dictionary, marked unverified and kept local-only ([source] copyright), loaded from a file.

## v0.4: content downloads and sync

- `GitHubPackSource`: packs published on tosk-data GitHub Releases, read from `index.json`, with version check, checksum and atomic swap. App updates are then no longer needed for content.
- `DriveSyncBackend`: the review log is synced through the Google Drive `appDataFolder` (a union merge, so there are no conflicts), with file export/import on desktop and web.
- Optionally the iOS build (needs a Mac).

## v0.5: handwriting, e-ink, listening

- ML Kit Digital Ink as an `AnswerInput` for production exercises, plus the Onyx pen SDK on the Boox.
- E-ink mode: no animations, high contrast, a full refresh after each lesson.
- `listen_pick` with on-device text-to-speech.

## Parked

Forest skin and the RPG layer (regions, lanterns, dungeons and bosses, a spellbook, a mistake garden, amber, gear), personalized vocabulary packs, reading readiness for a target book, the ghost race, and optional monetization.
