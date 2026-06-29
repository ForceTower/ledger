# @ledger/api

Bun + Hono + Kysely backend. Wraps `@ledger/nfce` (fetch + parse) and persists to Postgres.

## Dev

```bash
docker compose -f ../../infra/docker/docker-compose.yml up -d postgres
cp .env.example .env            # set API_TOKEN
bun run migrate                 # apply migrations
bun run dev                     # http://localhost:3000
```

## Scripts

- `bun run dev` / `start` — run the server (watch / once).
- `bun run migrate` / `migrate:down` / `migrate:status` — Kysely migrations.
- `bun run db:codegen` — regenerate `src/db/schema.ts` from the live DB (run after a migration).
- `bun run import:legacy -- <path-to-prototype-repo>` — one-time import of the file-based history.
- `bun run typecheck` / `test` / `lint`.

## Layout

- `src/index.ts` — Bun server entry.
- `src/app.ts` — Hono app: middleware, routes, error handling.
- `src/env.ts` — validated env + the cached service registry (db + services).
- `src/api/` — route modules + response helpers (`ok`/`err`) + bearer auth middleware.
- `src/service/` — business logic (e.g. `scan` orchestrates nfce + db).
- `src/db/` — Kysely client, generated `schema.ts`, and `migrations/`.
- `scripts/` — `migrate.ts`, `import-legacy.ts`.

See `../../docs/api-contract.md` for the wire contract and `../../docs/architecture.md` for the model.

> Status: scaffold. Routes return mock data shaped exactly like the contract so the iOS app can be
> built against a running server now. Replace the `TODO`s in `src/service` and `packages/nfce` with the
> real fetch/parse/DB logic.
