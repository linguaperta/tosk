"""CLI: python -m pipeline {fetch,import,build,validate,gen,flags,feedback,publish,mirror} ..."""
from __future__ import annotations

import argparse
import sys


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m pipeline", description="tosk content pipeline")
    sub = ap.add_subparsers(dest="cmd", required=True)

    from .plugins import describe
    plugins_note = describe()

    p = sub.add_parser("fetch", help="download open-data sources into the cache (and plugin courses' sources)",
                       epilog=plugins_note)
    p.add_argument("langs", nargs="*", default=["it", "nl"])
    p.add_argument("--force", action="store_true", help="re-download even if cached")
    p.add_argument("--skip-english", action="store_true", help="skip the 3 GB English dump (it->nl pivot)")

    p = sub.add_parser("import", help="cached dumps -> JSONL in content/", epilog=plugins_note)
    p.add_argument("langs", nargs="+")
    p.add_argument("--content-root")

    p = sub.add_parser("build", help="validate + compile + report + dist/index.json")
    p.add_argument("langs", nargs="+")
    p.add_argument("--content-root")
    p.add_argument("--local", action="store_true",
                   help="use the local (unpublished) content and dist folders (always the case for restricted courses)")
    p.add_argument("--install", action="store_true", help="copy packs to app/assets/courses/ (refused for restricted courses)")
    p.add_argument("--desktop", action="store_true",
                   help="also copy the packs into this computer's app data courses/ folder (for local-only packs)")
    p.add_argument("--quiet", action="store_true", help="short report")

    p = sub.add_parser("validate", help="validate content only")
    p.add_argument("langs", nargs="+")
    p.add_argument("--content-root")
    p.add_argument("--local", action="store_true", help="use the local content folder (always the case for restricted courses)")

    p = sub.add_parser("gen", help="generated example sentences (it/nl): gaps, floor (the fairness rule), "
                                   "context, check, add, refresh")
    p.add_argument("action", choices=["gaps", "floor", "context", "check", "add", "refresh"])
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

    p = sub.add_parser("publish", help="dist/index.json + a GitHub Release of the built packs (never restricted courses)")
    p.add_argument("langs", nargs="+")
    p.add_argument("--tag", help="release tag (default packs-YYYYMMDD, UTC)")
    p.add_argument("--dry-run", action="store_true", help="write dist/index.json and print the gh commands only")
    p.add_argument("--min-app-version", help="oldest app version that can use these packs (default 0.3.0)")
    p.add_argument("--repo", help="GitHub repository (default linguaperta/tosk-data)")
    p.add_argument("--gz", action="store_true",
                   help="also write <id>.sqlite.gz for the web app and add web_url/gz_sha256/gz_size to the index")
    p.add_argument("--content-root")

    p = sub.add_parser("mirror", help="web pack mirror: gzipped packs + index.json (GitHub Pages workflow)")
    p.add_argument("--out", required=True, help="output folder, e.g. site/packs")
    p.add_argument("--index", help="release index URL or local index.json (default: the stable latest URL)")

    p = sub.add_parser("flags", help="triage exercise flags exported from the app")
    fsub = p.add_subparsers(dest="flags_cmd", required=True)
    q = fsub.add_parser("summarize", help="print flags grouped by course/skill/type with the exercise")
    q.add_argument("files", nargs="+", help="tosk-flags-*.jsonl")
    q.add_argument("--course", help="only this course id")
    q.add_argument("--verdict", choices=["exercise_wrong", "ambiguous", "exercise_correct", "none"])
    q.add_argument("--json", action="store_true", help="also print each raw exercise snapshot")

    from .feedback import add_parser as add_feedback_parser
    add_feedback_parser(sub)

    a = ap.parse_args(argv)
    from .restricted import RestrictedContentError
    try:
        return _run(a)
    except RestrictedContentError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2


def _run(a) -> int:
    if a.cmd in ("fetch", "import"):
        from .plugins import ENV_VAR, course_plugin
        from .restricted import is_restricted
        public = []
        for lang in a.langs:
            plugin = course_plugin(lang)
            step = None if plugin is None else (plugin.fetch if a.cmd == "fetch" else plugin.import_)
            if step is not None and a.cmd == "fetch":
                step(force=a.force)
            elif step is not None:
                step(a.content_root)
            elif plugin is not None or is_restricted(lang):
                print(f"error: '{a.cmd} {lang}' needs its private course plugin (set ${ENV_VAR}, "
                      "see docs/private-importers.md)", file=sys.stderr)
                return 2
            else:
                public.append(lang)
        if public and a.cmd == "fetch":
            from .fetch import fetch
            fetch(public, force=a.force, skip_english=a.skip_english)
        elif public:
            from .importer import run_import
            for lang in public:
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
                           min_app_version=a.min_app_version or pub.DEFAULT_MIN_APP_VERSION, gz=a.gz)
    if a.cmd == "mirror":
        from .webpacks import STABLE_INDEX_URL, mirror
        mirror(a.out, a.index or STABLE_INDEX_URL)
        return 0
    if a.cmd == "flags":
        from .flags import main_summarize
        return main_summarize(a.files, a.course, a.verdict, a.json)
    if a.cmd == "feedback":
        from .feedback import main as feedback_main
        return feedback_main(a)
    return 1


if __name__ == "__main__":
    sys.exit(main())
