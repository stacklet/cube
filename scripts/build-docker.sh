#!/usr/bin/env bash
# Build a Stacklet Cube Docker image.
#
# Usage: ./scripts/build-docker.sh [TAG [DOCKER_BUILD_ARGS...]]
#        ./scripts/build-docker.sh --list-patched
#   TAG defaults to cubejs/cube:dev. Any further arguments are passed through
#   to `docker build` (e.g. --label, --build-arg).
#   --list-patched prints PATCHED_PACKAGES, one per line, and exits.
#
# latest.Dockerfile installs the npm-published @cubejs-backend/* packages, so
# local source changes don't reach the image on their own. This script compiles
# the monorepo and stages the dist/ of each package in PATCHED_PACKAGES into
# packages/cubejs-docker/stacklet-patches/<pkg>-dist/. The Dockerfile overlays
# every *-dist/ directory it finds there onto the npm-installed package.
#
# To patch another package, add its @cubejs-backend/ name (without the scope)
# to PATCHED_PACKAGES. No Dockerfile change is needed.

set -euo pipefail

PATCHED_PACKAGES=(
  server-core
)

if [ "${1:-}" = "--list-patched" ]; then
  printf '%s\n' "${PATCHED_PACKAGES[@]}"
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER_DIR="$REPO_ROOT/packages/cubejs-docker"
PATCHES_DIR="$DOCKER_DIR/stacklet-patches"
TAG="${1:-cubejs/cube:dev}"
shift || true

cleanup() {
  echo "Cleaning up staged patches..."
  find "$PATCHES_DIR" -maxdepth 1 -name '*-dist' -type d -exec rm -rf {} + 2>/dev/null || true
}
trap cleanup EXIT

# Directory under packages/ whose package.json is named @cubejs-backend/<pkg>.
package_dir() {
  local pkg="$1" manifest
  for manifest in "$REPO_ROOT"/packages/*/package.json; do
    if [ "$(node -p "require('$manifest').name")" = "@cubejs-backend/$pkg" ]; then
      dirname "$manifest"
      return 0
    fi
  done
  echo "ERROR: no package named @cubejs-backend/$pkg under packages/" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Compile and stage Stacklet-patched packages
# ---------------------------------------------------------------------------

declare -A PATCHED_DIRS=()
for pkg in "${PATCHED_PACKAGES[@]}"; do
  PATCHED_DIRS[$pkg]="$(package_dir "$pkg")"
  # tsc never deletes stale output, and the package's tsbuildinfo lives in
  # dist/, so this forces a clean rebuild of what gets overlaid.
  rm -rf "${PATCHED_DIRS[$pkg]}/dist"
done

# Patched packages compile against the workspace's other packages, so build
# the whole TypeScript project graph (incremental after the first run).
echo "==> Compiling TypeScript packages..."
yarn --cwd "$REPO_ROOT" tsc

for pkg in "${PATCHED_PACKAGES[@]}"; do
  dir="${PATCHED_DIRS[$pkg]}"
  echo "==> Staging $pkg dist from ${dir#"$REPO_ROOT"/}..."
  mkdir -p "$PATCHES_DIR/$pkg-dist"
  cp -r "$dir/dist/." "$PATCHES_DIR/$pkg-dist/"
done

# The Docker build context is packages/cubejs-docker, so it needs its own copy
# of the root lockfile (which carries the CVE resolutions).
cp "$REPO_ROOT/yarn.lock" "$DOCKER_DIR/yarn.lock"

# ---------------------------------------------------------------------------
# Docker build
# ---------------------------------------------------------------------------

echo "==> Building Docker image $TAG..."
docker build -t "$TAG" -f "$DOCKER_DIR/latest.Dockerfile" "$@" "$DOCKER_DIR"

echo "==> Done: $TAG"

echo "==> Verifying logger patch..."
COUNT=$(docker run --rm "$TAG" grep -c 'Performing query completed' \
  /cube/node_modules/@cubejs-backend/server-core/dist/src/core/logger.js)
if [ "$COUNT" -ne 2 ]; then
  echo "ERROR: logger patch check failed (expected 2 matches, got $COUNT)"
  exit 1
fi
echo "Logger patch OK ($COUNT matches)"
