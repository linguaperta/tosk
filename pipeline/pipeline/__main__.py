"""CLI: python -m pipeline {fetch,import,build,validate,gen,flags,publish} ..."""
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

    p = sub.add_parser("stories", help="check the graded stories of it/nl (content/{course}/stories/*.yaml)")
    p.add_argument("lang")
    p.add_argument("--content-root")
    p.add_argument("--show", help="print the alignment of the stories of this unit ('all' for every unit)")

    p = sub.add_parser("publish", help="dist/index.json + a GitHub Release of the built packs (never hns)")
    p.add_argument("langs", nargs="+")
    p.add_argument("--tag", help="release tag (default packs-YYYYMMDD, UTC)")
    p.add_argument("--dry-run", action="store_true", help="write dist/index.json and print the gh commands only")
    p.add_argument("--min-app-version", help="oldest app version that can use these packs (default 0.3.0)")
    p.add_argument("--repo", help="GitHub repository (default timoverlaan/tosk-data)")
    p.add_argument("--content-root")

    p = sub.add_parser("flags", help="triage exercise flags exported from the app")
    fsub = p.add_subparsers(dest="flags_cmd", required=True)
    q = fsub.add_parser("summarize", help="print flags grouped by course/skill/type with the exercise")
    q.add_argument("files", nargs="+", help="tosk-flags-*.jsonl")
    q.add_argument("--course", help="only this course id")
    q.add_argument("--verdict", choices=["exercise_wrong", "ambiguous", "exercise_correct", "none"])
    q.add_argument("--json", action="store_true", help="also print each raw exercise snapshot")

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
    if a.cmd == "stories":
        from .stories import run_check
        return run_check(a.lang, a.content_root, a.show)
    if a.cmd == "validate":
        from .build import validate_only
        return validate_only(a.langs, a.content_root, local=a.local)
    if a.cmd == "publish":
        from . import publish as pub
        return pub.publish(a.langs, tag=a.tag, dry_run=a.dry_run, content_root=a.content_root,
                           repo=a.repo or pub.DATA_REPO_SLUG,
                           min_app_version=a.min_app_version or pub.DEFAULT_MIN_APP_VERSION)
    if a.cmd == "flags":
        from .flags import main_summarize
        return main_summarize(a.files, a.course, a.verdict, a.json)
    return 1


if __name__ == "__main__":
    sys.exit(main())
