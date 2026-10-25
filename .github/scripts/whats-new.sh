#!/usr/bin/env bash
# Writes the web app's whats_new.json (read by lib/updates/web_update.dart):
# the app version from pubspec.yaml, the deployed build (commit), and the
# title and notes of that version's GitHub release (tag preview-X.Y.Z or
# vX.Y.Z), empty while there is no such release yet.
#
#   .github/scripts/whats-new.sh <pubspec.yaml> <build> <owner/repo> <out.json>
#
# Needs gh (GH_TOKEN in CI) and jq. Never fails the deploy: without a release
# (or without gh) the notes are just empty, and the app shows no sheet.
set -euo pipefail

pubspec="$1"
build="$2"
repo="$3"
out="$4"

version=$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' "$pubspec" | head -n 1)
if [ -z "$version" ]; then
  echo "::error::No version in $pubspec" >&2
  exit 1
fi

title=""
notes=""
url=""
tmp=$(mktemp)
for tag in "preview-$version" "v$version"; do
  if gh release view "$tag" --repo "$repo" --json name,body,url > "$tmp" 2>/dev/null; then
    title=$(jq -r '.name // ""' "$tmp")
    notes=$(jq -r '.body // ""' "$tmp")
    url=$(jq -r '.url // ""' "$tmp")
    echo "Release notes from $tag"
    break
  fi
done
rm -f "$tmp"
[ -n "$title" ] || echo "::notice::No release for $version yet: whats_new.json has no notes."

jq -n \
  --arg version "$version" \
  --arg build "$build" \
  --arg title "$title" \
  --arg notes "$notes" \
  --arg url "$url" \
  '{version: $version, build: $build, title: $title, notes: $notes, url: $url}' > "$out"
cat "$out"
