# Private importers and restricted courses

The rule (docs/VISION.md): public tools are generic (JSONL, CSV, Wiktionary/kaikki, Tatoeba, plain text). Importers, scrapers and reference data aimed at one specific copyrighted source are private, and packs built from such sources never go into a public repo, release or app build.

**Done on 20 October 2026:** the Sarnami importer (`pipeline/pipeline/hns/`, its tests and fixtures, and its build notes) moved to the private repository `timoverlaan/tosk-data-private`, together with the locally built Sarnami data. This repository keeps only the generic plugin point and the safeguard.

## The plugin point (`pipeline/pipeline/plugins.py`)

The public pipeline discovers optional **course plugins**:

1. `$TOSK_PRIVATE_PIPELINE`: one or more folders (separated by `;` on Windows, `:` elsewhere). A folder with a `pipeline_private/` subfolder means that subfolder. The folder goes on `sys.path`, and each package in it that has a `tosk_plugin.py` is a plugin.
2. Installed packages with an entry point in the group `tosk.pipeline_plugins`.

A plugin module defines `register(registry)` and calls `registry.course(code, fetch=..., import_=..., restricted=True, local_root=..., description=...)`. `python -m pipeline fetch <code>` and `import <code>` then run the plugin's functions, and `python -m pipeline import --help` lists the plugins found. A plugin that fails to import only prints a warning. Without any plugin the public pipeline and its tests work unchanged; `fetch`/`import` of a restricted course code then exit with code 2 and a pointer to this page.

```sh
# PowerShell; for the owner's private checkout
$env:TOSK_PRIVATE_PIPELINE = "C:\Users\timo\Repositories\tosk-data-private"
pipeline/.venv/Scripts/python -m pipeline import --help    # "private course plugins: hns (...)"
```

## Restricted courses (`pipeline/pipeline/restricted.py`)

A restricted course is built from all-rights-reserved sources: `hns` (built in, so the protection holds without the plugin), any code in `$TOSK_RESTRICTED_COURSES` (comma-separated), and any course a plugin registers with `restricted=True`. For these courses:

- content may only be written below the **local root**: `$TOSK_LOCAL` (or the older `$TOSK_LOCAL`), else the plugin's `local_root`, else the git-ignored `local/` of the main checkout; never into the public content repo, `app/` or any other folder (`check_destination`);
- `build` always uses the local root, `build --install` is refused, and `publish` and `mirror` refuse them (`RestrictedContentError`, exit code 2);
- `build <code> --desktop` (`pipeline/pipeline/install.py`) copies the built pack into the desktop app's own `courses/` folder, which is not a repository.

Tests: `pipeline/tests/test_restricted.py` (the safeguard, a fake plugin, the desktop copy).

## Sarnami (`hns`)

Sarnami Hindustani for Dutch speakers: 9 units, 35 skills, built grammar first, marked unverified in the app (no speaker has checked it yet). Its sources are copyrighted, so the importer, its notes and the data live in the private repository, and the pack is loaded from a file (`build hns --desktop`, or "Add course from file…"). The app only knows `hns` as a language: no handwriting model (it uses Dutch) and no text-to-speech voice. The app tests that read the built pack (`app/test/engine/hns_pack_validity_test.dart`, `special_letters_test.dart`) run only when `$TOSK_HNS_PACK` points at it.
