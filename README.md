# tosk

A free, offline-first language-learning app in the style of Duolingo, with a strong focus on grammar and conjugation. Courses: Italian and Dutch (v1), Sarnami later.

- Spec: [docs/SPEC.md](docs/SPEC.md)
- Architecture and contracts: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Backlog: [BACKLOG.md](BACKLOG.md)
- Content (CC BY-SA): the sibling repo `tosk-data`

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
