#!/usr/bin/env bash
# Fail if this tree changes code that won't reach the Docker image.
#
# Usage: ./scripts/stacklet-overlay-guard.sh [BASE_REF]
#   BASE_REF defaults to the upstream cube-js/cube release tag matching the
#   version in packages/cubejs-docker/package.json, fetched from GitHub.
#
# The image installs npm-published packages and overlays only the compiled
# TypeScript of the @cubejs-backend packages listed by
# `build-docker.sh --list-patched`. Every other change under packages/ or
# rust/ is silently dropped, so it fails here instead. Allowed: Markdown,
# tests, packages/cubejs-docker/ itself, and the TypeScript sources of
# patched packages (src/, or js/ for @cubejs-backend/native, whose src/ is
# Rust).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ $# -ge 1 ]; then
  base="$1"
else
  version="$(node -p "require('./packages/cubejs-docker/package.json').version")"
  # Only the tag's tree is needed. A depth limit in a full clone would make it
  # shallow, so only use one where the clone is already shallow (CI).
  depth=()
  if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
    depth=(--depth=1)
  fi
  echo "==> Fetching upstream tag v$version..."
  git fetch --quiet --no-tags "${depth[@]}" https://github.com/cube-js/cube.git "refs/tags/v$version"
  base=FETCH_HEAD
fi

# Process substitution hides a failing command from `set -e`, so check the base
# and capture command output in plain assignments first.
if ! git rev-parse --verify --quiet "$base^{tree}" >/dev/null; then
  echo "ERROR: base ref '$base' does not resolve to a tree"
  exit 1
fi
patched_out="$(./scripts/build-docker.sh --list-patched)"
changed_out="$(git diff --name-only "$base" HEAD)"
mapfile -t patched <<< "$patched_out"
mapfile -t changed <<< "$changed_out"

# Directory of TypeScript sources the overlay ships, per patched package.
declare -A shipped=()
for pkg in "${patched[@]}"; do
  if [ "$pkg" = native ]; then
    shipped[packages/cubejs-backend-native]=js
  else
    for manifest in packages/*/package.json; do
      if [ "$(node -p "require('./$manifest').name")" = "@cubejs-backend/$pkg" ]; then
        shipped[$(dirname "$manifest")]=src
      fi
    done
  fi
done

declare -A dropped=()
for path in "${changed[@]}"; do
  case "$path" in
    '' | *.md | packages/cubejs-docker/*) continue ;;
  esac
  # Top-level test directories only: `case` globs would also match test/
  # directories nested inside shipped code.
  if [[ "$path" =~ ^packages/[^/]+/(test|tests|__tests__)/ ]]; then
    continue
  fi
  if [[ "$path" =~ ^(packages/[^/]+)/([^/]+)/ && "${shipped[${BASH_REMATCH[1]}]:-}" = "${BASH_REMATCH[2]}" ]]; then
    continue
  fi
  if [[ "$path" =~ ^((packages|rust)/[^/]+)/ ]]; then
    dropped[${BASH_REMATCH[1]}]+="    $path"$'\n'
  fi
done

if [ ${#dropped[@]} -gt 0 ]; then
  echo "ERROR: changes that won't reach the image:"
  for dir in $(printf '%s\n' "${!dropped[@]}" | sort); do
    echo "  $dir"
    printf '%s' "${dropped[$dir]}"
  done
  echo "Only the TypeScript sources of packages in PATCHED_PACKAGES"
  echo "(scripts/build-docker.sh) are overlaid. Rust ships as prebuilt binaries."
  exit 1
fi

echo "Overlay guard OK (patched: ${patched[*]})"
