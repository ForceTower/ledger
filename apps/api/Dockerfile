FROM oven/bun:1.3.12-alpine AS deps
WORKDIR /app
COPY package.json bun.lock ./
COPY apps/api/package.json ./apps/api/
COPY packages/nfce/package.json ./packages/nfce/
COPY packages/shared-types/package.json ./packages/shared-types/
RUN bun install --frozen-lockfile

FROM oven/bun:1.3.12-alpine AS runtime
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY tsconfig.json ./
COPY apps/api ./apps/api
COPY packages/nfce ./packages/nfce
COPY packages/shared-types ./packages/shared-types

ENV NODE_ENV=production
WORKDIR /app/apps/api
EXPOSE 3000
USER bun

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget --quiet --tries=1 --spider "http://127.0.0.1:${PORT:-3000}/" || exit 1

CMD ["bun", "run", "src/index.ts"]
