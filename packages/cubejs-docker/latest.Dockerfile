FROM node:22.23.4-bookworm-slim AS builder

WORKDIR /cube
COPY . .

RUN yarn policies set-version v1.22.22
# Yarn v1 uses aggressive timeouts with summing time spending on fs, https://github.com/yarnpkg/yarn/issues/4890
RUN yarn config set network-timeout 120000 -g

# Required for node-oracledb to buld on ARM64
RUN apt-get update \
    # python3 package is necessary to install `python3` executable for node-gyp
    # libpython3-dev is needed to trigger post-installer to download native with python
    && apt-get install -y python3 python3.11 libpython3.11-dev gcc g++ make cmake ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# We are copying root yarn.lock file to the context folder during the Publish GH
# action. So, a process will use the root lock file here.
RUN yarn install --prod \
    # Remove DuckDB sources to reduce image size
    && rm -rf /cube/node_modules/duckdb/src \
    && yarn cache clean

# Stacklet: replace the dist/ of npm-installed packages with locally compiled
# ones. stacklet-patches/<pkg>-dist/ dirs are populated by
# scripts/build-docker.sh. Each holds a package's full compiled output, so
# replacing rather than copying over stops files deleted from the source
# surviving from the npm build.
COPY stacklet-patches/ /cube/stacklet-patches/
RUN find /cube/stacklet-patches -maxdepth 1 -name '*-dist' -type d | while read d; do \
      pkg=$(basename "$d" -dist); \
      target="/cube/node_modules/@cubejs-backend/$pkg/dist"; \
      [ -d "$target" ] || { echo "stacklet-patches: $target not installed" >&2; exit 1; }; \
      rm -rf "$target" && cp -r "$d" "$target" || exit 1; \
    done && rm -rf /cube/stacklet-patches

FROM node:22.23.4-bookworm-slim

ARG IMAGE_VERSION=unknown

ENV CUBEJS_DOCKER_IMAGE_VERSION=$IMAGE_VERSION
ENV CUBEJS_DOCKER_IMAGE_TAG=latest

RUN DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    && apt-get install -y --no-install-recommends libssl3 python3.11 libpython3.11 \
    && rm -rf /var/lib/apt/lists/*

RUN yarn policies set-version v1.22.22

# Stacklet: the server never runs npm (only dev mode's Playground dashboard-app
# launcher does), and npm's bundled dependencies carry their own CVEs.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
      /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack

ENV NODE_ENV=production
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

WORKDIR /cube

COPY --from=builder /cube .

# By default Node dont search in parent directory from /cube/conf, @todo Reaserch a little bit more
ENV NODE_PATH=/cube/conf/node_modules:/cube/node_modules
ENV PYTHONUNBUFFERED=1
RUN ln -s /cube/node_modules/.bin/cubejs /usr/local/bin/cubejs
RUN ln -s /cube/node_modules/.bin/cubestore-dev /usr/local/bin/cubestore-dev

WORKDIR /cube/conf

EXPOSE 4000

CMD ["cubejs", "server"]
