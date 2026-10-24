# Hosting and going public

Decisions agreed with the owner on 20 October 2026, and the checklist for making tosk usable by other people. All of it is free; paid stores are optional later.

## Decisions

| Topic | Decision |
| --- | --- |
| App id | **Done in 0.7.1:** `io.github.timoverlaan.tosk` → **`org.linguaperta.tosk`**, Windows `tosk.exe` → `tosk.exe` (data folder `%APPDATA%\linguaperta	osk`) (the owner moves their own progress with backup export/import; the new id installs as a separate app). The Windows exe name and secure-storage key follow the rename. |
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

- [x] Move the copyrighted-source importers **and the local Sarnami data (`local/`)** to the private repo **`timoverlaan/tosk-data-private`** (checkout `C:\Users\timo\Repositories\tosk-data-private`, created by the owner on 20 Oct). Done 20 Oct: the importer is a private course plugin (`pipeline/pipeline/plugins.py`, `$TOSK_PRIVATE_PIPELINE`), the safeguard is the public `pipeline/pipeline/restricted.py`; see [private-importers.md](private-importers.md). The history rewrite still has to drop the old paths listed there.
- [x] Scan the **whole git history** of both repos for Sarnami data, keys, `key.properties`, keystores, `google-services.json` (20 Oct: no secrets or Sarnami data; only the importer code and `docs/sarnami.md`, which the rewrite removes). `tosk-data` is clean.
- [x] Remove every remaining old-name reference and **rewrite the whole history** (done 21 Oct): the moved Sarnami paths and every old course pack were dropped from all commits; the old name and the source names were replaced in contents, paths and messages; the current tree was byte-identical to the tested one; force-pushed with the preview tags. Backup of the old history: `C:\Users\timo\Repositories\tosk-before-rewrite.bundle` (local only). GitHub may still serve old commits by hash until its own garbage collection.
- [x] Add `LICENSE` (Apache-2.0), `NOTICE`, `TRADEMARKS.md`, and `app/assets/brand/LICENSE` (CC BY-NC-ND 4.0); content repo keeps CC BY-SA 4.0.
- [x] Rename the app id to `org.linguaperta.tosk` (and the Windows exe/secure-storage name); update docs and signing.
- [ ] Add `license` / `authors` / `data_sources` to the it, nl and es `course.yaml`; the course preview shows them.
- [x] Owner: create the `linguaperta` GitHub org, move and rename the repos (public since 20 Oct).
- [ ] Owner: enable GitHub Pages (Settings → Pages → Source: GitHub Actions).
- [x] Owner: create the Firebase project ([firebase-setup.md](firebase-setup.md)), add the Pages origin as an authorized domain, add the CI secrets.
- [x] Privacy policy page: `app/web/privacy.html`, deployed with the web app at `https://linguaperta.github.io/tosk/privacy.html` (what stays on the device, what syncs per answer and setting, reports only when sent, no analytics or ads, AI directly to the provider with the learner's key, GitHub, fonts, ML Kit and speech, Android backup, "Delete my cloud data", contact). Linked from the welcome's sign-in page, Settings → Account & sync and Settings → About.
- [ ] Owner: publish the updated Firestore rules ([firebase-setup.md](firebase-setup.md), step 9), set up reading feedback (step 10), fill in the OAuth consent screen with the privacy URL and publish it (step 11), and check the privacy page's Firestore region.
- [x] Ready for outside testers (after v0.7.6): flags, feedback (Settings → Send feedback) and opt-in crash reports reach the owner when the learner is signed in (`python -m pipeline feedback pull`); developer-only settings (the debug screen) are behind seven taps on the version; About has the version, licences, source and privacy links; the Unverified badge explains itself; error panels say what to do.
- [ ] Small website (`linguaperta.github.io`): downloads, the web app, the pack docs, the privacy policy.
- [ ] First public release: tag → CI builds the APK, Windows and web, attaches them to the GitHub Release and deploys Pages.
