# Development guide

## How to build

Release version

### Debian:

```sh
docker build -t cubejs/cube:latest -f latest.Dockerfile .
docker buildx build --platform linux/amd64 -t cubejs/cube:latest -f latest.Dockerfile .
docker buildx build --platform linux/amd64,linux/arm64 -t cubejs/cube:latest -f latest.Dockerfile .
```

### JDK

```sh
docker build -t cubejs/cube:latest-jdk -f latest-debian-jdk.Dockerfile .
```

### Not released, development (from `cubejs-docker` directory)

```sh
docker build -t cubejs/cube:dev -f dev.Dockerfile ../../
docker buildx build --platform linux/amd64 -t cubejs/cube:dev -f dev.Dockerfile ../../
```

## Stacklet builds

The Stacklet fork patches certain Cube packages at the TypeScript source level.
Because `latest.Dockerfile` installs packages from npm (not from the local
workspace), a wrapper script is required to compile modified packages and stage
their compiled output before `docker build` runs.

**Always use the build script — never `docker build` directly:**

```sh
# From the repo root:
./scripts/build-docker.sh cubejs/cube:v1.6.6-stacklet-$(git rev-parse --short HEAD)
```

The script:
1. Runs `yarn workspace @cubejs-backend/server-core build` (and any other
   patched packages)
2. Copies compiled `dist/` output into `stacklet-patches/<pkg>-dist/`
3. Runs `docker build`; the Dockerfile overlays those dist files on the
   npm-installed versions
4. Cleans up the staged files on exit

### Adding a new patched package

1. Make source changes and compile: `yarn workspace @cubejs-backend/<pkg> build`
2. Add a compile + stage block to `scripts/build-docker.sh`:
   ```bash
   mkdir -p "$PATCHES_DIR/<pkg>-dist"
   cp -r "$REPO_ROOT/packages/cubejs-<pkg>/dist/." "$PATCHES_DIR/<pkg>-dist/"
   ```
3. No Dockerfile change is needed — `latest.Dockerfile` automatically applies
   any `*-dist/` directories it finds in `stacklet-patches/`.

### Verifying a patch is in the image

```sh
docker run --rm <tag> grep -c "Performing query completed" \
  /cube/node_modules/@cubejs-backend/server-core/dist/src/core/logger.js
# expected: 2
```
