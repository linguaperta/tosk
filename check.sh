#!/usr/bin/env bash
# Full verification: pipeline tests, flutter analyze, flutter tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
export PATH="/c/Users/timo/dev/flutter/bin:$PATH"
if [ -d "$ROOT/pipeline" ]; then
  PY="$ROOT/pipeline/.venv/Scripts/python"; [ -x "$PY" ] || PY="$ROOT/pipeline/.venv/bin/python"; [ -x "$PY" ] || PY=python
  (cd "$ROOT" && "$PY" -m pytest -q pipeline/tests)
fi
(cd "$ROOT/app" && flutter analyze && flutter test)
# Local packages (excluded from the app's analysis; see app/packages/).
for pkg in "$ROOT"/app/packages/*/; do
  (cd "$pkg" && flutter pub get >/dev/null && flutter analyze && flutter test)
done
