# tosk

A free, offline-first language-learning app in the style of Duolingo, with a strong focus on grammar and conjugation. Courses: Italian and Dutch (v1), Sarnami later.

- Spec: [docs/SPEC.md](docs/SPEC.md)
- Architecture and contracts: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Backlog: [BACKLOG.md](BACKLOG.md)
- Content (CC BY-SA): the sibling repo `tosk-data`

## Status (v0.3.0, 14 October 2026)

| Course | Units | Skills | Taught words | Sentences | Notes |
| --- | --- | --- | --- | --- | --- |
| Italian (`it`) | 9 | 40 | ~740 | ~20,400 (2,200 generated) | bundled |
| Dutch (`nl`) | 8 | 35 | ~710 | ~16,300 (2,300 generated) | bundled |
| Sarnami (`hns`) | 9 | 35 | ~390 | ~3,000 | local-only (copyright), unverified, see docs/sarnami.md |

Tests: ~900 Flutter tests and 132 pipeline tests. Builds: Android APK, Windows and web. Release steps: [docs/release.md](docs/release.md).

## Layout

```
app/        Flutter app (Android, iOS, desktop, web)
pipeline/   Python: open data -> JSONL -> course.sqlite
schema/     JSON Schemas + compiled course DB DDL
docs/       spec and architecture
```

## Verify everything

```bash
./check.sh
```
