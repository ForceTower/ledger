FROM oven/bun:1.3.12 AS runtime
WORKDIR /app

# curl: used by the container healthcheck. The AI features need no extra binaries — the Claude
# Agent SDK dependency bundles its own runtime, and `bun install` below picks the platform build.
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install deps with only the manifests present so this layer caches until a
# package.json / lockfile changes. bun places each workspace's deps in that
# workspace's own node_modules (apps/api/node_modules, ...), not a hoisted root
# one, so the whole /app tree below must carry them.
COPY package.json bun.lock tsconfig.json ./
COPY apps/api/package.json ./apps/api/
COPY packages/nfce/package.json ./packages/nfce/
COPY packages/shared-types/package.json ./packages/shared-types/
RUN bun install --frozen-lockfile

# Source has no node_modules in CI, so copying it over the install is safe.
COPY apps/api ./apps/api
COPY packages/nfce ./packages/nfce
COPY packages/shared-types ./packages/shared-types

ENV NODE_ENV=production
USER bun
WORKDIR /app/apps/api
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl --fail --silent "http://127.0.0.1:${PORT:-3000}/" || exit 1

CMD ["bun", "run", "src/index.ts"]
