# ledger Agent Instructions

## Overall

- ledger is a self-hosted, open-source household-spending ledger. Read `README.md` and
  `docs/architecture.md` for the big picture and `docs/api-contract.md` for the wire contract.
- ALWAYS read and understand relevant files before proposing edits. Do not speculate about code you
  have not inspected.
- Code readability matters most. Prefer fixing the root of a behavior over layering workarounds.

## Language: English everywhere in code

- All identifiers, API JSON fields, DB columns/tables, and category keys are **English**. There is no
  Portuguese on the wire or in the schema (this is a port of a Portuguese-named dataset — translate
  field names when porting; see `docs/architecture.md` for the legacy → English mapping).
- The only place Brazilian Portuguese appears is the iOS app's user-facing copy (labels, messages) —
  the owner's locale. Code, comments, and data shapes stay English.

## Tooling

- `mise` manages tool versions (see `.mise.toml`).
- `bun` is the package manager and script runner — we do NOT use `npm`, `yarn`, or `pnpm`.
- `bunx` must be used in place of `npx`.
- `oxlint` lints, `oxfmt` formats — we do NOT use `prettier`, `eslint`, or anything else.
- Native iOS is a standard Xcode project (`apps/ios`).

## Development workflow (TypeScript)

All `bun` scripts run from the repo root.

- `bun install` — install dependencies.
- `bun run check` — format-check and lint without applying fixes.
- `bun run fix` — format and lint, applying fixes. Run this frequently and always after a task.
- For typechecking, run `bun run --filter @ledger/api typecheck` (or inside the workspace).
- To run a command in a specific package: `bun run --filter @ledger/<pkg> ...`.

**Do NOT fix formatting by hand — use `bun run fix`.**

## Development workflow (iOS)

- SwiftUI, latest iOS. Native feel: Apple HIG, SF Pro, system materials, dynamic type, safe areas.
- Build the app against the contract in `docs/api-contract.md`. Layering follows Domain/Data
  (repository interfaces in `Domain/Repositories`, live implementations in `Data/Repositories`
  composing the generic `APIClient` transport + GRDB mirror); features depend only on repositories.
  Previews run on repository `previewValue`s; the live client reads the server URL + bearer token
  from Settings.
- User-facing copy is Brazilian Portuguese; currency is BRL (`R$ 1.234,56`). Type/identifier names
  stay English.
- If you make big iOS changes and we're on macOS, try to compile the app.

## Monorepo structure

- `apps/api` — Bun + Hono + Kysely backend. The main service.
- `apps/ios` — Native iOS app (Swift + SwiftUI).
- `packages/nfce` — NFC-e fetch + parse + categorize library. The reusable core; no HTTP server or DB
  concerns. This is the open-source crown jewel — keep it well-tested against HTML fixtures.
- `packages/shared-types` — Shared TS wire types, consumed by `apps/api`. The contract source of truth
  flows from here; Swift mirrors it.
- `infra/` — Docker Compose (dev + deploy).

## File organization & naming

- **TypeScript files**: `kebab-case.ts`.
- **Swift files**: `PascalCase.swift` for types, standard Swift conventions.
- **Exports**: named exports over default (enforced by `no-default-export`; config and a few route
  files are exempt — see `.oxlintrc.json`).
- **Export sources**: put a type in its natural home. If it belongs in `@ledger/shared-types`, put it
  there directly rather than re-exporting from `apps/api`.

## TypeScript & type safety

- Avoid `any` and type casting. Use `zod` to validate unknown data at boundaries (request bodies,
  fetched HTML, external responses). `@hono/zod-validator` is wired into `apps/api`.
- Instead of casting, add type guarding (e.g. with zod).
- Avoid explicit types when inference is sufficient; only annotate when inference is not enough.
- **Zod composition**: never use `.merge()` or `.extend()` — they create deeply nested generics that
  hit TS's instantiation depth limit (TS2589). Spread `.shape` into a flat `z.object()` instead:

```ts
// Bad
const bad = schemaA.extend({ field: z.string() });
// Good
const good = z.object({ ...schemaA.shape, field: z.string() });
```

## Database (Kysely + Postgres)

- Hand-write migrations in `apps/api/src/db/migrations` (`NNN_name.ts`, `up`/`down` via the schema
  builder). There is no schema-diff codegen — the migration is the source of truth.
- After changing migrations, regenerate the typed `Database` interface with `kysely-codegen`
  (`bun run --filter @ledger/api db:codegen`) so types never drift from the schema.
- Postgres columns are `snake_case`; the `CamelCasePlugin` exposes them as `camelCase` in TS. Write
  queries in `camelCase`.
- For aggregations and nested reads, prefer real SQL via Kysely (use `jsonArrayFrom`/`jsonObjectFrom`
  from `kysely/helpers/postgres` to assemble nested purchase → items/payments in one query). Drop to
  the `sql` tag for `pg_trgm` similarity fragments.

## Auth

- Single static bearer token (`API_TOKEN`), compared in constant time. There are no user accounts —
  one instance, one owner. Every protected route requires `Authorization: Bearer <token>`.

## Data & privacy

- Real purchase data lives ONLY in the owner's Postgres instance. Never commit real data. The only
  tracked dataset is the anonymized fixtures under `data/sample/`.

## Source control

- Do not add a co-author trailer (Claude or otherwise) or any "generated with" note to commits.
