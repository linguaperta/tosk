# Hosting and going public

Decisions agreed with the owner on 20 October 2026, and the checklist for making tosk usable by other people. All of it is free; paid stores are optional later.

## Decisions

| Topic | Decision |
| --- | --- |
| App id | Change `io.github.timoverlaan.tosk` → **`org.linguaperta.tosk`** before the first public release (the owner moves their own progress with backup export/import; the new id installs as a separate app). The Windows exe name and secure-storage key follow the rename. |
| Name | **tosk**. Checked 20 Oct: no conflicting app, startup or trademark (only a small Rust CLI to-do tool `tosk` and Toskr, Inc., a US telecom). Overlap: "Tosk" is also the Albanian dialect standard Albanian is based on, so searches for Tosk courses find Albanian apps; accepted. |
| Code licence | **Apache-2.0** for the app and the pack toolkit. |
| Content licence | Official packs: **CC BY-SA 4.0** (required by the Wiktionary and FrequencyWords data; Tatoeba's CC BY sentences may be included). Our own additions (generated sentences, notes, stories, structure) are released under the same licence. |
| Brand | The name "tosk" and the Tosk art (`app/assets/brand/`) are **excluded** from Apache-2.0. The art is **CC BY-NC-ND 4.0** (share unchanged, non-commercially); forks must use their own name and mascot. Explained in `TRADEMARKS.md`. Gelasio stays under the SIL OFL. Trademark registration (BOIP ~€250, EU ~€850) only if the project grows. |
| Android | Signed release APKs on **GitHub Releases** (installable and updatable with Obtainium). Google Play maybe later ($25 once; 12 testers for 14 days for new personal accounts; privacy policy and data-safety form). |
| F-Droid | **No** separate FOSS build for now. |
| iOS | The web app (PWA, "Add to Home Screen"). An unsigned IPA from CI for AltStore/SideStore for enthusiasts. The App Store ($99/year) only if there is demand. |
| Windows | Zip/installer on GitHub Releases. |
| Web app and web packs | **GitHub Pages**, same origin, so no CORS: the app at `<org>.github.io/tosk/`, packs at `…/tosk/packs/` as `<code>.sqlite.gz` (~5 MB instead of ~19 MB) plus `index.json`. Deployed with the GitHub Actions Pages deployment, so pack binaries never enter git history. If it ever gets tight: Cloudflare Pages (25 MB per file) or R2. |
| Native packs | GitHub Releases on the content repo plus `index.json`, as today. |
| Sync | Firebase **Auth + Firestore only** (free Spark plan), no Firebase Hosting. Answers are batched into chunk documents so a user's day costs a handful of writes. Hidden until a Firebase config is added. |
| AI | Bring your own key, stored on the device. No hosted AI. |
| Repos | `linguaperta/tosk` (public): app, pipeline and `pack` toolkit, schema, spec. `linguaperta/tosk-data` (public, today tosk-data): content and compiled packs. Copyrighted-source importers (Sarnami) move to a **private** repo first. |

## Content licensing rules

- Every pack declares `license`, `authors` and `data_sources` in `course.yaml`; the app shows them in the course preview.
- Keep Tatoeba sentence ids so each sentence can be traced to its contributors.
- AI-made content keeps its `src: claude-*` tags.
- The official catalog accepts only open licences (CC BY-SA, CC BY, CC0). Self-hosted catalogs are their owner's responsibility. Personal packs carry no obligations unless shared, and copyrighted book text in them can never be shared.
- Recorded audio (if ever added) is checked per file; some Tatoeba audio is non-commercial only.

## Go-public checklist

- [ ] Move the copyrighted-source importers to a private repo ([private-importers.md](private-importers.md)), replacing the hooks it lists.
- [ ] Scan the **whole git history** of both repos for Sarnami/[source] data, keys, `key.properties`, keystores, `google-services.json`; rewrite history if anything turns up.
- [ ] Add `LICENSE` (Apache-2.0), `NOTICE`, `TRADEMARKS.md`, and `app/assets/brand/LICENSE` (CC BY-NC-ND 4.0); content repo keeps CC BY-SA 4.0.
- [ ] Rename the app id to `org.linguaperta.tosk` (and the Windows exe/secure-storage name); update docs and signing.
- [ ] Add `license` / `authors` / `data_sources` to the it, nl and es `course.yaml`; the course preview shows them.
- [ ] Owner: create the `linguaperta` GitHub org, move and rename the repos, enable GitHub Pages (Actions source).
- [ ] Owner: create the Firebase project ([firebase-setup.md](firebase-setup.md)), add the Pages origin as an authorized domain, add the CI secrets.
- [ ] Privacy policy page on the website: what is synced (the answer log and settings, linked to the Google account), no analytics, crash reports stay on the device, "Delete my cloud data".
- [ ] Small website (`linguaperta.github.io`): downloads, the web app, the pack docs, the privacy policy.
- [ ] First public release: tag → CI builds the APK, Windows and web, attaches them to the GitHub Release and deploys Pages.
