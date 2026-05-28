#!/usr/bin/env bash
# Build a Stacklet Cube Docker image.
#
# Usage: ./scripts/build-docker.sh [TAG]
#   TAG defaults to cubejs/cube:dev
#
# This script compiles Stacklet-patched packages and stages their dist output
# into packages/cubejs-docker/stacklet-patches/ before invoking docker build.
# The Dockerfile picks up whatever *-dist/ directories it finds there and
# overlays them on the npm-installed versions of those packages.
#
# To add a new patched package in the future:
#   1. Make your source changes and run: yarn workspace @cubejs-backend/<pkg> build
#   2. Add a compile + stage block below (following the server-core example)
#   3. No Dockerfile change is needed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER_DIR="$REPO_ROOT/packages/cubejs-docker"
PATCHES_DIR="$DOCKER_DIR/stacklet-patches"
TAG="${1:-cubejs/cube:dev}"

cleanup() {
  echo "Cleaning up staged patches..."
  find "$PATCHES_DIR" -maxdepth 1 -name '*-dist' -type d -exec rm -rf {} + 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Compile and stage Stacklet-patched packages
# ---------------------------------------------------------------------------

echo "==> Building @cubejs-backend/server-core..."
yarn --cwd "$REPO_ROOT" workspace @cubejs-backend/server-core build

echo "==> Staging server-core dist..."
mkdir -p "$PATCHES_DIR/server-core-dist"
cp -r "$REPO_ROOT/packages/cubejs-server-core/dist/." \
      "$PATCHES_DIR/server-core-dist/"

# ---------------------------------------------------------------------------
# Docker build
# ---------------------------------------------------------------------------

echo "==> Building Docker image $TAG..."
docker build -t "$TAG" -f "$DOCKER_DIR/latest.Dockerfile" "$DOCKER_DIR"

echo "==> Done: $TAG"
echo ""
echo "Verify the logger patch:"
echo "  docker run --rm $TAG grep -c 'Performing query completed' \\"
echo "    /cube/node_modules/@cubejs-backend/server-core/dist/src/core/logger.js"
echo "  (expected: 2)"
