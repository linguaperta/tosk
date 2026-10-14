"""Read and write the JSONL/YAML source pack of one course (content/{course}/)."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import yaml


@dataclass
class Pack:
    root: Path
    course: dict
    items: list[dict] = field(default_factory=list)
    verbs: dict[str, dict] = field(default_factory=dict)
    sentences: list[dict] = field(default_factory=list)
    notes: dict[str, dict[str, str]] = field(default_factory=dict)   # skill -> lang -> md
    # (file, line number) per record, for error messages
    origins: dict[str, str] = field(default_factory=dict)
    raw_lines: list[tuple[str, str, int, dict]] = field(default_factory=list)  # (kind, file, lineno, record)
    stories: list[dict] = field(default_factory=list)   # stories/*.yaml (stories.py)

    @property
    def code(self) -> str:
        return self.course["id"]

    def skills(self):
        for ui, unit in enumerate(self.course.get("units") or []):
            for si, skill in enumerate(unit.get("skills") or []):
                yield ui, unit, si, skill


def read_jsonl(path: Path) -> list[tuple[int, dict]]:
    out = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                out.append((n, json.loads(line)))
            except ValueError as e:
                raise ValueError(f"{path}:{n}: invalid JSON: {e}") from None
    return out


def write_jsonl(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False, separators=(", ", ": ")) + "\n")


def load_course_yaml(root: Path) -> dict:
    with open(root / "course.yaml", encoding="utf-8") as f:
        return yaml.safe_load(f)


def load_pack(root: Path) -> Pack:
    root = Path(root)
    pack = Pack(root=root, course=load_course_yaml(root))
    for kind in ("lexicon", "verbs", "sentences"):
        d = root / kind
        if not d.exists():
            continue
        for p in sorted(d.glob("*.jsonl")):
            for n, rec in read_jsonl(p):
                rel = f"{kind}/{p.name}"
                pack.raw_lines.append((kind, rel, n, rec))
                if kind == "lexicon":
                    pack.items.append(rec)
                elif kind == "verbs":
                    if rec.get("id") in pack.verbs:
                        pack.verbs[f"__dup__{rel}:{n}"] = rec
                    else:
                        pack.verbs[rec.get("id")] = rec
                else:
                    pack.sentences.append(rec)
    from .stories import load_stories
    pack.stories = load_stories(root)
    gdir = root / "grammar"
    if gdir.exists():
        for p in sorted(gdir.glob("*.md")):
            name = p.name[:-3]
            lang = "en"
            if "." in name:
                name, lang = name.rsplit(".", 1)
            pack.notes.setdefault(name, {})[lang] = p.read_text(encoding="utf-8")
    return pack
