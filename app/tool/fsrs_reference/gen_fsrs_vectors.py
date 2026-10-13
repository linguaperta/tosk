"""Generate FSRS reference vectors from py-fsrs for the Dart scheduler tests.

Usage (from a scratch virtualenv, never inside the repo):

    python -m venv /tmp/fsrs-venv
    /tmp/fsrs-venv/bin/pip install fsrs==6.3.2
    /tmp/fsrs-venv/bin/python app/tool/fsrs_reference/gen_fsrs_vectors.py \
        app/test/fixtures/fsrs_vectors.json

The scheduler uses the py-fsrs defaults (FSRS-6, 21 parameters, desired
retention 0.9, learning steps 1m/10m, relearning step 10m, maximum interval
36500 days) with fuzzing DISABLED, so results are deterministic.

Every sequence is a list of reviews of one card. After each review the
resulting card state is recorded, plus the card's retrievability at a few
probe times. Times are integer epoch milliseconds (UTC).
"""

from __future__ import annotations

import importlib.metadata
import json
import random
import sys
from datetime import datetime, timedelta, timezone

from fsrs import Card, Rating, Scheduler

START = datetime(2026, 1, 1, 8, 0, 0, tzinfo=timezone.utc)
MS = timedelta(milliseconds=1)


def to_ms(dt: datetime) -> int:
    return (dt - datetime(1970, 1, 1, tzinfo=timezone.utc)) // MS


def card_json(card: Card) -> dict:
    return {
        "state": card.state.value,  # 1 learning, 2 review, 3 relearning
        "step": card.step,
        "stability": card.stability,
        "difficulty": card.difficulty,
        "due_ms": to_ms(card.due),
        "last_review_ms": to_ms(card.last_review) if card.last_review else None,
    }


def run(scheduler: Scheduler, name: str, plan: list[tuple[int, object]]) -> dict:
    """plan: list of (rating, when) where when is a timedelta after the
    previous review (or after START for the first one) or the string 'due'
    (review exactly at the due time) or ('due', timedelta) (due + offset)."""
    card = Card(card_id=1, due=START)
    now = START
    reviews = []
    for rating_value, when in plan:
        if when == "due":
            at = card.due
        elif isinstance(when, tuple) and when[0] == "due":
            at = card.due + when[1]
        else:
            at = now + when
        # Probe retrievability just before reviewing.
        r_before = scheduler.get_card_retrievability(card, at)
        card, _ = scheduler.review_card(card, Rating(rating_value), at)
        now = at
        probes = []
        for days in (0.5, 3, 45, 400):
            t = at + timedelta(days=days)
            probes.append({"at_ms": to_ms(t), "r": scheduler.get_card_retrievability(card, t)})
        reviews.append(
            {
                "rating": rating_value,
                "at_ms": to_ms(at),
                "r_before": r_before,
                "after": card_json(card),
                "probes": probes,
            }
        )
    return {"name": name, "reviews": reviews}


def fixed_sequences() -> list[tuple[str, list]]:
    m = lambda n: timedelta(minutes=n)  # noqa: E731
    d = lambda n: timedelta(days=n)  # noqa: E731
    seqs = []
    for r in (1, 2, 3, 4):
        seqs.append((f"first-{r}", [(r, m(0))]))
    seqs.append(("learn-good-good-then-due", [(3, m(0)), (3, "due"), (3, "due"), (3, "due"), (3, "due"), (3, "due")]))
    seqs.append(("learn-hard-steps", [(2, m(0)), (2, "due"), (3, "due"), (2, "due"), (3, "due"), (2, "due")]))
    seqs.append(("learn-again-loop", [(1, m(0)), (1, "due"), (3, "due"), (1, "due"), (3, "due"), (3, "due"), (3, "due")]))
    seqs.append(("easy-chain-to-max", [(4, m(0))] + [(4, "due")] * 25))
    seqs.append(("lapse-relearn", [(3, m(0)), (3, "due"), (3, "due"), (3, "due"), (1, "due"), (2, "due"), (3, "due"), (3, "due"), (1, ("due", d(30))), (1, "due"), (4, "due")]))
    seqs.append(("early-reviews", [(3, m(0)), (3, m(10)), (3, d(1)), (3, timedelta(hours=3)), (3, timedelta(hours=20)), (4, d(2)), (2, d(0)), (3, d(5))]))
    seqs.append(("overdue-a-lot", [(3, m(0)), (3, "due"), (3, ("due", d(200))), (2, ("due", d(400))), (1, ("due", d(1000))), (3, "due"), (3, "due")]))
    seqs.append(("mixed-sub-day", [(1, m(0)), (2, m(1)), (3, m(3)), (4, m(5)), (1, timedelta(hours=23, minutes=59)), (3, timedelta(hours=24)), (2, timedelta(hours=47)), (3, "due")]))
    return seqs


def random_sequences(rng: random.Random, count: int) -> list[tuple[str, list]]:
    seqs = []
    for i in range(count):
        length = rng.randint(3, 20)
        plan = []
        for j in range(length):
            rating = rng.choices([1, 2, 3, 4], weights=[2, 1, 6, 1])[0]
            kind = rng.random()
            if j == 0:
                when = timedelta(seconds=rng.randint(0, 3600))
            elif kind < 0.35:
                when = "due"
            elif kind < 0.6:
                when = ("due", timedelta(seconds=rng.randint(-3600 * 24 * 3, 3600 * 24 * 60)))
            elif kind < 0.8:
                when = timedelta(seconds=rng.randint(1, 3600 * 30))
            else:
                when = timedelta(seconds=rng.randint(1, 3600 * 24 * 500))
            if isinstance(when, tuple) and when[1] < timedelta(0):
                # never schedule before the previous review
                when = ("due", timedelta(0))
            plan.append((rating, when))
        seqs.append((f"random-{i}", plan))
    return seqs


def main() -> None:
    out = sys.argv[1] if len(sys.argv) > 1 else "fsrs_vectors.json"
    scheduler = Scheduler(enable_fuzzing=False)
    rng = random.Random(20261013)
    sequences = []
    for name, plan in fixed_sequences() + random_sequences(rng, 40):
        # Guard against a 'due'-relative step landing before the previous review.
        sequences.append(run(scheduler, name, plan))
    for seq in sequences:
        prev = None
        for rev in seq["reviews"]:
            assert prev is None or rev["at_ms"] >= prev, seq["name"]
            prev = rev["at_ms"]
    data = {
        "generator": f"py-fsrs {importlib.metadata.version('fsrs')}",
        "scheduler": scheduler.to_dict(),
        "sequences": sequences,
    }
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
    print(f"wrote {len(sequences)} sequences, {sum(len(s['reviews']) for s in sequences)} reviews to {out}")


if __name__ == "__main__":
    main()
