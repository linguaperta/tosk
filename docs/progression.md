# Progression

Phase 5 code lives in `app/lib/progression/` (pure Dart, depends only on `core`) and `app/lib/ui/progression/` (widgets). This page documents the rules and formulas.

## Core principle: everything is derived from the review log

XP, levels, tiers, streaks, freezes, challenges, badges, the verb collection, non-stop records and session summaries are all **pure functions of the review log**, plus the course data, a `Scheduler`, the user's calendar and "now". Nothing is stored as a counter. After a sync merge (the union of two logs), recomputing gives identical results on every device.

### Canonical replay (`replay.dart`)

`LogReplay` de-duplicates events by `id`, sorts them by `(at, id)`, and replays them through the `Scheduler`. For each event it records a `ReplayStep`: the facet's state just **before** and just **after** the event, the XP the event earned, and the cumulative XP.

- Updates are incremental. When the new canonical log extends the old one (new answers at the end), only the new events are replayed. When an older event arrives (a sync merge), the replay is rebuilt from scratch. Either way the result equals a full replay. Tests check this: event by event, by growing prefixes, with shuffled insertion orders, and with out-of-order merges.
- `ProgressionService` re-reads the log on every query and feeds it to the replay. Derived data (day counts, challenge facts, non-stop runs) is cached per replay version.

## XP (`xp.dart`)

XP is earned per review event (one graded facet outcome). Let `before` be the facet's state just before the event, `R` the scheduler's predicted recall at answer time, and `D` the FSRS difficulty (1..10).

| Case | XP |
| --- | --- |
| Wrong, and the facet was new or due | 1 |
| Wrong, facet not due | 0 |
| Correct, new facet (first review ever) | 8 |
| Correct, not due yet (re-practice) | 2 (anti-farming) |
| Correct, due | `10 + round(8·(1−R)) + round(4·(D−1)/9) + (3 if lapses > 0 or relearning)` |

- **Overdue-ness** is captured by `R`: the longer past due, the lower `R`, and the bigger the recall bonus. A facet answered right on its due date (R ≈ 0.9) gets +1.
- **Hard** facets (high D) get up to +4, and **lapsed** facets get +3.
- A single event earns at most 25 XP.
- Non-stop combos do **not** change XP. XP tracks memory; the combo affects the run score only.

All constants are in `XpRules`.

### Levels

Reaching level `n` takes `floor(100 · (n−1)^1.6)` cumulative XP, and level 1 starts at 0. So level 2 needs 100, level 5 needs 917, level 10 needs 3,373, level 20 needs 11,124 and level 50 needs about 50,600. `LevelCurve.levelFor(xp)` returns `LevelInfo(level, xpIntoLevel, xpForNext, totalXp)`, where `xpForNext` is the size of the current level.

## Skill tiers (`tiers.dart`)

The inputs are the course's skill facets, the facet states, the scheduler, and `now`. "Learned" means a facet has been reviewed and is no longer in its initial FSRS learning phase: `reps > 0 && phase != learning`. A relearning facet still counts as learned, because it graduated before.

| Tier | Rule |
| --- | --- |
| locked | Nothing reviewed, and some prerequisite has no reviewed facet. Prerequisites without facets, or with unknown ids, count as satisfied. |
| available | Unlocked, but nothing reviewed. (This state isn't in the spec, but it's needed between locked and started.) |
| started | At least one facet reviewed. A started skill is never shown as locked, for example when practiced through the lab. |
| bronze | Every facet learned. |
| silver | Bronze, and every facet has `R(now) ≥ 0.85` and stability ≥ 7 days. |
| gold | Bronze, and every facet has `R(now) ≥ 0.90` and stability ≥ 21 days. |

Tiers are computed at `now`, so a skill drops from gold to silver to bronze as recall decays. Bronze never decays, because learning is permanent; the fading signal shows the decay instead.

`SkillProgress` also carries:

- **strength:** the mean R over all facets, where never-reviewed facets count as 0
- **fading** (0..1, for desaturating the map): the mean over *reviewed* facets of `clamp((0.90 − R) / (0.90 − 0.50), 0, 1)`. It is 0 for a skill that was never started (new, not faded)
- `dueCount`, `minRetrievability`, `lastPracticed`, and `nextTierProgress` (the share of facets meeting the next tier's rule)

## Streaks, freezes and the heatmap (`calendar.dart`, `streaks.dart`)

**Local days.** Events are stored in UTC. A `LocalCalendar` maps each instant to the user's UTC offset *at that instant* (`Duration Function(DateTime utc)`), which gives a `LocalDate`. `LocalCalendar.system()` uses the device's zone rules, including historical DST, through `DateTime.toLocal()`. Tests pass explicit functions to simulate DST switches and travel. No tz database is needed.

A **practice day** is a local date with at least one review event. Days are processed in order:

1. A practice day extends the run by 1. Its reviews then count toward freezes: every **50 reviews** earns **1 freeze**, up to **2 held**. Reviews done at the cap earn nothing.
2. A missed day while a run is active consumes 1 freeze, and the day becomes "frozen". With no freeze left, the run resets to 0. Freezes are not spent while there is no active run.
3. Today is never counted as missed. If you haven't practiced yet today, `current` is the run through yesterday (`practicedToday = false`, and `atRisk` if you have no freezes). Days after today are ignored.

Frozen days keep a run alive but don't add to its length. `longest` is the maximum run. Milestones (7, 30, 100 and 365 days) record the first day each one was reached.

All of this is derived from per-day counts, so it is deterministic. A merge that adds an old practice day can retroactively repair a streak, which is the intended behavior for sync.

**Heatmap.** `HeatmapData` holds the review count per local date in an inclusive range, plus the frozen days. Intensity buckets are 0 for none, 1 for 1–9 reviews, 2 for 10–24, 3 for 25–49 and 4 for 50 or more. The service's default range is the 26 weeks ending today, starting on a Monday.

Known limitation: crossing the date line eastward can skip a local date entirely. That date counts as missed, so a freeze covers it.

## Challenges and badges (`challenges.dart`, `prng.dart`)

Periods are ISO weeks (Monday to Sunday, id `W2026-42`) and calendar months (`M2026-10`), both in local dates.

**Selection.** The pool is shuffled with xorshift32, seeded by FNV-1a of `tosk/challenges/{periodId}`. The first templates with *distinct metrics* are taken: 3 per week and 2 per month. The hash and PRNG are hand-written so they give identical results on the VM and the web, and across SDK versions. A pinned test guards against accidental changes, which would change every user's past challenges.

**Metrics.** Each event contributes to the period that contains its local date.

| Metric | Counts |
| --- | --- |
| reviews / correctAnswers | events / correct events |
| conjugations | correct `conj_pick` / `conj_grid` events |
| practiceDays | distinct local days |
| perfectLessons | sessions with mode `lesson`, ≥ 5 events and no mistake, counted at their last event |
| newWords | items (not facets) reviewed for the first time ever |
| xp | XP from the replay |
| strongVerbTables / masteredVerbTables | `#form:` facets whose stability first reaches 7 / 21 days |
| nonStopCombo | the best combo reached in a non-stop run (a maximum, not a sum) |

The weekly pool: 150 or 300 reviews, 50 conjugations, practice on 7 or 5 days, 3 perfect lessons, 20 new words, 1,500 XP, strengthen 5 verb tables, and a 25 combo. The monthly pool: 1,000 reviews, 250 conjugations, 20 practice days, 10 perfect lessons, 80 new words, 6,000 XP, master 10 verb tables, and a 50 combo.

**Badges.** Every completed challenge in every period from the first event to today is a badge, with id `{periodId}:{templateId}`. Its `earnedAt` is the instant of the event that completed it. Milestone badges are added on top: streak lengths of 7, 30, 100 and 365 days (`streak:N`) and levels 5, 10, 25, 50 and 100 (`level:N`). All of them are recomputed from the log.

## Verb collection (`verb_collection.dart`)

The collection has one card per verb item and one cell per tense. A cell is included when the verb has forms in that tense and either a skill trains `{itemId}#form:{tense}` or that facet has been reviewed.

| Mastery | Rule |
| --- | --- |
| unseen | no state |
| learning | reviewed but not learned, or learned with `R < 0.85` |
| known | learned and `R ≥ 0.85` |
| mastered | the gold criteria: `R ≥ 0.90` and stability ≥ 21 days |

Cards are sorted by frequency rank, then by lemma.

## Non-stop extras (`nonstop.dart`)

`NonStopRun` is an immutable state machine that is fed **one answer per graded exercise**: `run = run.answer(correct:, at:, exerciseType:)` or `run.applyResult(exercise, result, at:)`.

- **Combo:** the number of consecutive correct answers. A mistake resets it to 0 (`comboBroken` signal).
- **Multiplier:** `min(3.0, 1 + 0.5 · floor(combo / 5))`, using the combo *including* the current answer. That gives ×1 for 0–4, ×1.5 for 5–9, ×2 for 10–14, ×2.5 for 15–19 and ×3 for 20 or more.
- **Points:** a correct answer scores `round(10 × multiplier × roundMultiplier)`. A wrong answer scores 0.
- **Bonus round, the conjugation blitz.** It starts on every 25th correct answer of the run: `BonusRound(kind: 'conj_blitz', preferredTypes: ['conj_pick'], deadline: at + 60 s, targetAnswers: 10, multiplier: 2)`.
  - Answers at or before the deadline count toward the round and score ×2 on top of the combo.
  - After 10 answers the round completes with a bonus of `10 × correct answers in the round`.
  - An answer after the deadline first ends the round (`bonusRoundExpired`, no completion bonus) and then scores normally.
  - `run.preferredTypes` tells the engine what to serve. `tick(now)` ends an expired round for the HUD and never changes the score.
- **Best run from the log:** events with `mode == 'nonstop'` are grouped by `sessionId`. Within a session, consecutive events with the same `at` and `exerciseType` are one answer (for example match pairs), which is correct only if all of them are correct. The same machine then replays them. `bestNonStopRun` is the highest score, and ties go to the earlier run.

**Contract for the engine.** Record all facet outcomes of one exercise with the same `at`. **Contract for the UI.** Feed `NonStopRun` with the event timestamp the engine records (or the same clock reading), so the live score equals the replayed record.

## Session summary (`session_summary.dart`)

`summarizeSession(sessionId)` uses the replay to report the following:

- the number of reviews, the number correct, the accuracy, and the XP earned (the sum of the session's event XP)
- the level from the cumulative XP before the session's first event and after its last event, which gives `leveledUp`
- a `FacetChange` for each facet practiced: its state before and after, recall at the session start and at the session end, and its reviews and mistakes. A facet counts as `improved` if it is new, its stability grew, or it graduated into review. `improvedItemIds` lists the words that improved
- `TierChange`s for every course skill, evaluated at the session end with the states before the session against the states before the session plus **only this session's events**. That isolates the session's effect from decay and from events of other sessions interleaved in time, and it includes unlocks (locked to available).

## Facade (`progression_service.dart`)

```dart
ProgressionService({required ProgressStore store, required Scheduler scheduler, required CourseData course,
                    DateTime Function()? clock, LocalCalendar? calendar, ProgressionConfig config})
Future<ProgressProfile> profile([DateTime? now])        // XP, LevelInfo, StreakInfo, today's reviews/XP
Future<Map<String, SkillProgress>> skillTiers([DateTime? now])
Future<HeatmapData> heatmap({LocalDate? from, LocalDate? to, DateTime? now})
Future<ChallengeBoard> challenges([DateTime? now])     // weekly, monthly, badges
Future<List<EarnedBadge>> badges([DateTime? now])
Future<VerbCollection> verbCollection([DateTime? now])
Future<SessionProgressSummary?> sessionSummary(String sessionId)
Future<NonStopRecord?> bestNonStopRun()
Future<List<NonStopRecord>> nonStopHistory()
NonStopRun newNonStopRun()
```

XP, level, streak, heatmap, challenges and badges cover the whole log, across all courses. Skill tiers and the verb collection cover the given course.

## Widgets (`app/lib/ui/progression/`)

Every widget takes plain data objects and a `reduceMotion` flag, which turns off all animation. The widgets are `StreakHeatmap`, `StreakCounter`, `LevelBadge`, `TierBadge`, `ChallengesList`, `VerbCollectionView`, `SessionSummaryCard` and `NonStopHud`. `lib/main_progression_preview.dart` shows them all with fake data:

```
flutter run -t lib/main_progression_preview.dart
```
