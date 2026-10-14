"""CLI: python -m pipeline {fetch,import,build,validate} ..."""
from __future__ import annotations

import argparse
import sys


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m pipeline", description="tosk content pipeline")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("fetch", help="download open-data sources into the cache (hns: scrape the [source] dictionary)")
    p.add_argument("langs", nargs="*", default=["it", "nl"])
    p.add_argument("--force", action="store_true", help="re-download even if cached")
    p.add_argument("--skip-english", action="store_true", help="skip the 3 GB English dump (it->nl pivot)")

    p = sub.add_parser("import", help="cached dumps -> JSONL in content/")
    p.add_argument("langs", nargs="+")
    p.add_argument("--content-root")

    p = sub.add_parser("build", help="validate + compile + report + dist/index.json")
    p.add_argument("langs", nargs="+")
    p.add_argument("--content-root")
    p.add_argument("--local", action="store_true",
                   help="use the git-ignored local/content and local/dist (always the case for hns)")
    p.add_argument("--install", action="store_true", help="copy packs to app/assets/courses/ (refused for hns)")
    p.add_argument("--desktop", action="store_true",
                   help="also copy the packs into this computer's app data courses/ folder (for local-only packs)")
    p.add_argument("--quiet", action="store_true", help="short report")

    p = sub.add_parser("validate", help="validate content only")
    p.add_argument("langs", nargs="+")
    p.add_argument("--content-root")
    p.add_argument("--local", action="store_true", help="use local/content (always the case for hns)")

    p = sub.add_parser("gen", help="generated example sentences (it/nl): gaps, context, check, add, refresh")
    p.add_argument("action", choices=["gaps", "context", "check", "add", "refresh"])
    p.add_argument("lang")
    p.add_argument("files", nargs="*", help="draft JSONL files (check, add)")
    p.add_argument("--skill", help="context: the skill to write for")
    p.add_argument("--out", help="context: write to this file")
    p.add_argument("--drop", action="store_true", help="refresh: drop sentences that no longer pass")
    p.add_argument("--quiet", action="store_true", help="gaps: summary lines only")
    p.add_argument("--content-root")

    a = ap.parse_args(argv)
    from .hns.safeguard import RestrictedContentError
    try:
        return _run(a)
    except RestrictedContentError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2


def _run(a) -> int:
    if a.cmd == "fetch":
        if "hns" in a.langs:
            from .hns.sil import fetch_all
            from .hns.sources import fetch_sources
            fetch_all(force=a.force)
            fetch_sources(force=a.force)
        rest = [x for x in a.langs if x != "hns"]
        if rest:
            from .fetch import fetch
            fetch(rest, force=a.force, skip_english=a.skip_english)
        return 0
    if a.cmd == "import":
        for lang in a.langs:
            if lang == "hns":
                from .hns.importer import run_import as run_import_hns
                run_import_hns(a.content_root)
            else:
                from .importer import run_import
                run_import(lang, a.content_root)
        return 0
    if a.cmd == "build":
        from .build import build
        return build(a.langs, a.content_root, install=a.install, quiet=a.quiet, local=a.local, desktop=a.desktop)
    if a.cmd == "gen":
        from .generate import run
        return run(a.action, a.lang, a.content_root, a)
    if a.cmd == "validate":
        from .build import validate_only
        return validate_only(a.langs, a.content_root, local=a.local)
    return 1


if __name__ == "__main__":
    sys.exit(main())
