"""CLI: python -m pipeline {fetch,import,build,validate,flags} ..."""
from __future__ import annotations

import argparse
import sys


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m pipeline", description="tosk content pipeline")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("fetch", help="download open-data sources into the cache")
    p.add_argument("langs", nargs="*", default=["it", "nl"])
    p.add_argument("--force", action="store_true", help="re-download even if cached")
    p.add_argument("--skip-english", action="store_true", help="skip the 3 GB English dump (it->nl pivot)")

    p = sub.add_parser("import", help="cached dumps -> JSONL in content/")
    p.add_argument("langs", nargs="+")
    p.add_argument("--content-root")

    p = sub.add_parser("build", help="validate + compile + report + dist/index.json")
    p.add_argument("langs", nargs="+")
    p.add_argument("--content-root")
    p.add_argument("--install", action="store_true", help="copy packs to app/assets/courses/")
    p.add_argument("--quiet", action="store_true", help="short report")

    p = sub.add_parser("validate", help="validate content only")
    p.add_argument("langs", nargs="+")
    p.add_argument("--content-root")

    p = sub.add_parser("flags", help="triage exercise flags exported from the app")
    fsub = p.add_subparsers(dest="flags_cmd", required=True)
    q = fsub.add_parser("summarize", help="print flags grouped by course/skill/type with the exercise")
    q.add_argument("files", nargs="+", help="tosk-flags-*.jsonl")
    q.add_argument("--course", help="only this course id")
    q.add_argument("--verdict", choices=["exercise_wrong", "ambiguous", "exercise_correct", "none"])
    q.add_argument("--json", action="store_true", help="also print each raw exercise snapshot")

    a = ap.parse_args(argv)
    if a.cmd == "fetch":
        from .fetch import fetch
        fetch(a.langs, force=a.force, skip_english=a.skip_english)
        return 0
    if a.cmd == "import":
        from .importer import run_import
        for lang in a.langs:
            run_import(lang, a.content_root)
        return 0
    if a.cmd == "build":
        from .build import build
        return build(a.langs, a.content_root, install=a.install, quiet=a.quiet)
    if a.cmd == "validate":
        from .build import validate_only
        return validate_only(a.langs, a.content_root)
    if a.cmd == "flags":
        from .flags import main_summarize
        return main_summarize(a.files, a.course, a.verdict, a.json)
    return 1


if __name__ == "__main__":
    sys.exit(main())
