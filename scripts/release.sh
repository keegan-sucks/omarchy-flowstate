#!/usr/bin/env bash
#
# Cut a Flowstate release: bump manifest.json, commit, tag, push, GitHub release.
#
#   scripts/release.sh <version>      e.g.  scripts/release.sh 0.3.0
#
# Omarchy installs plugins straight from git (omarchy plugin add / update follow the
# repo's HEAD), so a release is just a version bump + tag. After it lands on main,
# ask the marketplace to verify the new commit (see README → Releasing).
set -euo pipefail

VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "usage: $0 <version>   e.g. $0 0.3.0"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

omarchy plugin validate "$ROOT" >/dev/null 2>&1 || { echo "manifest failed 'omarchy plugin validate'"; exit 1; }

echo "==> Bumping manifest.json to $VERSION"
tmp="$(mktemp)"; jq --arg v "$VERSION" '.version = $v' manifest.json > "$tmp" && mv "$tmp" manifest.json

git add manifest.json
git commit -m "Release v$VERSION" || true
git tag -f "v$VERSION"
git push origin HEAD
git push -f origin "v$VERSION"

if command -v gh >/dev/null 2>&1; then
  if gh release view "v$VERSION" >/dev/null 2>&1; then
    gh release edit "v$VERSION" --title "Flowstate $VERSION" >/dev/null
  else
    gh release create "v$VERSION" --title "Flowstate $VERSION" --generate-notes >/dev/null
  fi
fi

echo
echo "==> Released v$VERSION ($(git rev-parse HEAD))."
echo "    Users update with:  omarchy plugin update io.github.keegan-sucks.flowstate"
