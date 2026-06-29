# ledger

A self-hosted, open-source ledger for household spending. Scan the QR code on a Brazilian
electronic receipt (NFC-e) and ledger fetches it from SEFAZ, parses the itemized purchase,
categorizes it, and stores it in Postgres — building a single, queryable history of everything
you buy, with trends and (later) an AI assistant over the whole dataset.

It starts with supermarket receipts but the data model is generic enough to hold any invoice.

## Structure

This is a [Bun](https://bun.sh) workspace monorepo.

- **`apps/api`** — TypeScript backend (Bun + Hono + Kysely + Postgres). The scan pipeline and REST API.
- **`apps/ios`** — Native iOS app (Swift + SwiftUI). Scans the QR, shows what was saved, browses history.
- **`packages/nfce`** — The NFC-e fetch + parse + categorize library. The reusable core: given a SEFAZ
  QR URL it returns a structured, validated purchase. Has no knowledge of HTTP or the database.
- **`packages/shared-types`** — Shared TypeScript types for the wire contract (consumed by the API and any
  future web client). The native apps mirror these in Swift.
- **`infra/`** — Docker Compose for local dev (`infra/docker`) and the deploy stack (`infra/deploy`).
- **`docs/`** — The [API contract](docs/api-contract.md) (source of truth for clients) and
  [architecture notes](docs/architecture.md).

## Conventions

- The code, the API, and the data model are **all in English** — every JSON field, DB column, and
  category key. The iOS app's user-facing copy is Brazilian Portuguese (the owner's locale), but
  nothing in code or on the wire is.

## Quick start (backend)

```bash
mise install                       # bun (see .mise.toml)
bun install
docker compose -f infra/docker/docker-compose.yml up -d postgres
cp apps/api/.env.example apps/api/.env   # then edit
bun run --filter @ledger/api migrate
bun run --filter @ledger/api dev
```

## Deployment

Built to self-host on a small always-on box (a Mac mini or a Raspberry Pi) behind a
[Cloudflare Tunnel](infra/deploy/ledger-stack/README.md). See `infra/deploy/ledger-stack`.

## Data & privacy

Your real purchase data lives only in **your** Postgres instance — it is never committed to this
repo. The repository ships an anonymized fixture set under `data/sample/` so the project is runnable
without anyone's real data. See [docs/architecture.md](docs/architecture.md#data--privacy).

## License

[GPL-3.0](./LICENSE).
