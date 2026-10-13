"""Permanent item IDs, recorded in content/{course}/ids.tsv (id, lemma, pos, sense_key).

* `{course}:{lemma}` for the first word with that lemma, `{course}:{lemma}.{n}` (n = 2, 3, ...) for
  homographs that need a separate entry (different POS).
* Spaces in a lemma become '_' in the id ("it:per_favore").
* A (lemma, sense_key) pair always gets back the id it had; rows are never removed, so an id is
  never reassigned to a different word, even after the word leaves the pack.
* sense_key is the POS (one item per lemma + POS; Wiktionary etymologies with the same POS merge).
"""
from __future__ import annotations

from pathlib import Path

HEADER = "id\tlemma\tpos\tsense_key"


class IdRegistry:
    def __init__(self, course: str, path: Path | None = None):
        self.course = course
        self.path = path
        self.rows: list[tuple[str, str, str, str]] = []
        self.by_key: dict[tuple[str, str], str] = {}
        self.used: set[str] = set()
        if path and path.exists():
            for line in path.read_text(encoding="utf-8").splitlines():
                if not line.strip() or line.startswith("id\t"):
                    continue
                parts = line.split("\t")
                while len(parts) < 4:
                    parts.append("")
                iid, lemma, pos, sense = parts[:4]
                self.rows.append((iid, lemma, pos, sense))
                self.by_key[(lemma, sense or pos)] = iid
                self.used.add(iid)
        self.added = 0

    def get(self, lemma: str, pos: str, sense_key: str | None = None) -> str:
        key = (lemma, sense_key or pos)
        if key in self.by_key:
            return self.by_key[key]
        base = f"{self.course}:{lemma.replace(' ', '_')}"
        iid = base
        n = 2
        while iid in self.used:
            iid = f"{base}.{n}"
            n += 1
        self.by_key[key] = iid
        self.used.add(iid)
        self.rows.append((iid, lemma, pos, sense_key or pos))
        self.added += 1
        return iid

    def save(self) -> None:
        if not self.path:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        lines = [HEADER] + ["\t".join(r) for r in self.rows]
        self.path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
