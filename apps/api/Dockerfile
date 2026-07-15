FROM oven/bun:1.3.12 AS deps
WORKDIR /app
COPY package.json bun.lock ./
COPY apps/api/package.json ./apps/api/
COPY packages/nfce/package.json ./packages/nfce/
COPY packages/shared-types/package.json ./packages/shared-types/
RUN bun install --frozen-lockfile

FROM oven/bun:1.3.12 AS runtime
WORKDIR /app

# curl: used by the Claude Code installer below and by the container healthcheck.
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=deps /app/node_modules ./node_modules
COPY tsconfig.json ./
COPY apps/api ./apps/api
COPY packages/nfce ./packages/nfce
COPY packages/shared-types ./packages/shared-types

ENV NODE_ENV=production
USER bun

# The photo-scan endpoint (POST /scan/photo) shells out to the `claude` CLI.
# Bake it into the image; auth is via ANTHROPIC_API_KEY passed at runtime.
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/bun/.local/bin:${PATH}"

WORKDIR /app/apps/api
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl --fail --silent "http://127.0.0.1:${PORT:-3000}/" || exit 1

CMD ["bun", "run", "src/index.ts"]
