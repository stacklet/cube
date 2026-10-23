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

The Stacklet fork patches some Cube packages at the TypeScript source level.
`latest.Dockerfile` installs packages from npm, not from the local workspace,
so build the image with the wrapper script rather than `docker build`:

```sh
# From the repo root, after `yarn install`:
./scripts/build-docker.sh cubejs/cube:dev
```

The script compiles the workspace (`yarn tsc`), copies the `dist/` of each
package in its `PATCHED_PACKAGES` list into `stacklet-patches/<pkg>-dist/`,
and runs `docker build`. The Dockerfile overlays every `*-dist/` directory it
finds there onto the npm-installed package. Extra arguments after the tag are
passed to `docker build`.

### Adding a new patched package

Add the package's `@cubejs-backend/` name, without the scope, to
`PATCHED_PACKAGES` in `scripts/build-docker.sh`. No Dockerfile change is
needed.

`scripts/stacklet-overlay-guard.sh` fails on any change under `packages/` or
`rust/` that would not reach the image. It allows Markdown, tests,
`packages/cubejs-docker/`, and the TypeScript sources of packages in
`PATCHED_PACKAGES`. Rust ships as prebuilt binaries, so Rust changes always
fail.

### Verifying a patch is in the image

```sh
docker run --rm <tag> grep -c "Performing query completed" \
  /cube/node_modules/@cubejs-backend/server-core/dist/src/core/logger.js
# expected: 2
```
