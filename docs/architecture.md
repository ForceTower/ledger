# Architecture

## What this is

ledger turns the QR code on a Brazilian NFC-e receipt into structured, categorized, queryable
spending data. The flow:

```
iOS app scans QR  ─POST /scan {url}─►  API  ──►  @ledger/nfce (fetch + parse + categorize)
                                        │
                                        └──►  Postgres (upsert store, purchase, items, payments)
                                        ◄──   PurchaseSummary  (shown as a snippet in the app)
```

This replaces an earlier file-based prototype (one JSON file per purchase in a private repo). That
history is imported once into Postgres (see _Migration_) and Postgres becomes the source of truth.

## Decisions

- **Bun + Hono + Kysely + Postgres** for the API. Kysely (a typed query builder, not an ORM) fits the
  workload — most value is aggregations (spend by category/month/store, price history per GTIN), which
  are SQL. Migrations are hand-written; `kysely-codegen` regenerates the typed schema from the live DB.
- **Single-user per instance, open-source.** No accounts/multi-tenancy. One static bearer token.
  Others self-host their own copy (docker-compose + anonymized seed data).
- **Postgres self-hosted** on a Mac mini / Raspberry Pi, exposed via a Cloudflare Tunnel.
- **English everywhere in code.** The prototype used Portuguese field names; everything here is
  translated to English (mapping below).

### Cross-cutting infrastructure

- **Redis** (`ioredis`) — caching and a lock around the scan write (the slug sequence must be computed
  serially). Always wired; degrades gracefully if absent in local dev.
- **Firebase Admin / FCM** — push notifications to the iOS app (scan processed, budget alerts, …).
  Optional: with no service account, `NotificationService` becomes a no-op and the app runs unchanged.
  Device tokens are stored in `device_tokens` and registered via `POST /devices/token`.
- **OpenTelemetry logs** — structured logs via `loglayer` + `pino`, exported over OTLP when
  `OTEL_EXPORTER_OTLP_ENDPOINT` is set (stdout-only otherwise).

## Data model

Postgres tables (snake_case columns; Kysely exposes them camelCase via `CamelCasePlugin`):

- **stores** — `id, name, legal_name, cnpj (unique), address, created_at`. Dedup by CNPJ.
- **purchases** — `id, slug (unique), date, time, source, store_id, access_key (unique), receipt_number,
receipt_series, gross_total, discount_total, paid_total, item_count, taxes_total, source_html,
created_at`. **`access_key` (the 44-digit NFC-e key) is the dedup key** — a unique constraint
  replaces the prototype's "grep the files" check.
- **products** — `id, barcode (unique), canonical_description, default_category, created_at`. Optional
  FK target from items; enables price history across stores/time. Weighed produce/meat have no GTIN.
- **purchase_items** — `id, purchase_id, product_id, seq, description, code, barcode, quantity, unit,
unit_price, total, category`. Unique `(purchase_id, seq)`.
- **payments** — `id, purchase_id, code, method, amount, change`.
- **trips** — `id, date (unique), legs jsonb, created_at`. Transport costs to the store.
- **donations** — `id, date, source_purchase_slug, entries jsonb, total, created_at`. Donated items.
- **scan_requests** — `id, url, status, error_code, error_message, purchase_slug, warnings jsonb,
duration_ms, created_at`. Audit trail of every `POST /scan`: the raw scanned QR URL and how
  processing it went (`saved`/`duplicate`/`failed` + the error when it failed).
- **transfers** — `id, transaction_id (unique), transfer_type, amount, date, time, destination_*,
origin_*, purchase_id, extracted jsonb, created_at`. Pix receipts the AI read (`POST /scan/transfer`
  → `POST /transfers`). **`transaction_id` (the bank's end-to-end ID) is the dedup key**, the way
  `access_key` is for a nota. `purchase_id` points either at the single-item purchase the transfer
  materialized (`source: "pix"`) or at the nota it paid for, when the owner linked the two — a linked
  transfer adds no spending of its own.
- **device_tokens** — `id, token (unique), platform, created_at, last_seen_at`. FCM push tokens.

Extensions: `pg_trgm` for fuzzy product/description matching. `gen_random_uuid()` for PKs.

### Legacy (Portuguese) → English mapping

For the importer and the `@ledger/nfce` port. Left = prototype JSON / Python; right = this schema.

| Legacy                  | English                 |
| ----------------------- | ----------------------- |
| `loja` / `nome`         | `store` / `name`        |
| `razao_social`          | `legalName`             |
| `endereco`              | `address`               |
| `data`                  | `date`                  |
| `hora`                  | `time`                  |
| `origem`                | `source`                |
| `nfce.chave_acesso`     | `receipt.accessKey`     |
| `nfce.numero/serie`     | `receipt.number/series` |
| `itens`                 | `items`                 |
| `descricao`             | `description`           |
| `codigo`                | `code`                  |
| `codigo_barras`         | `barcode`               |
| `quantidade`            | `quantity`              |
| `unidade`               | `unit`                  |
| `valor_unitario`        | `unitPrice`             |
| `valor_total`           | `total`                 |
| `totais.valor_bruto`    | `totals.gross`          |
| `totais.descontos`      | `totals.discount`       |
| `totais.valor_pago`     | `totals.totalPaid`      |
| `totais.qtd_itens`      | `totals.itemCount`      |
| `pagamento` / `forma`   | `payments` / `method`   |
| `valor` / `troco`       | `amount` / `change`     |
| `tributos_totais`       | `taxesTotal`            |
| `transporte`/`trajetos` | `trips` / `legs`        |
| `doacoes`               | `donations`             |

Category slugs:

| Legacy             | English         |
| ------------------ | --------------- |
| `hortifruti`       | `produce`       |
| `carnes`           | `meat`          |
| `frios_laticinios` | `dairy_deli`    |
| `padaria`          | `bakery`        |
| `mercearia`        | `grocery`       |
| `bebidas`          | `beverages`     |
| `doces_snacks`     | `snacks_sweets` |
| `congelados`       | `frozen`        |
| `limpeza`          | `cleaning`      |
| `higiene`          | `hygiene`       |
| `pet`              | `pet`           |
| `bazar_utilidades` | `household`     |
| `outros`           | `other`         |

`transport`, `dining`, `health` and `services` have no legacy counterpart — the dataset was
supermarket receipts. They exist for the typed lançamentos (`POST /scan/entry`), which are about
spending no NFC-e ever covers.

## packages/nfce — the port

The prototype's fetch/parse/categorize is Python; this package is the TypeScript port and the reusable
core. It must produce output equivalent to the Python version. De-risk with **equivalence fixtures**:
the prototype's saved receipt HTML goes in `packages/nfce/tests/fixtures/`, and tests assert the parsed
result matches the expected JSON. Only the parser is in scope here — no HTTP server, no DB.

Tricky parts to port carefully:

- **fetch** (`fetch.ts`): the SEFAZ site is ASP.NET WebForms. The flow is: GET the simplified receipt,
  scrape the `__VIEWSTATE` / `__EVENTVALIDATION` hidden fields, re-POST with
  `__EVENTTARGET=btn_visualizar_abas` **in the same cookie session** to reach the detailed page that
  carries the per-item EAN. Bun's `fetch` does not keep a cookie jar — carry `Set-Cookie` forward
  manually. The QR's `p=` hash authenticates the request and skips the captcha.
- **parse** (`parse.ts`): items, totals, payments (compute `change` when paid > total), emission
  date/time, the 44-digit key (derive number/series from it), BRL money parsing. Match EAN to items by
  position (the detailed page lists products in receipt order); fall back to a code→EAN map.
- **categorize** (`categorize.ts`): de-accent, whole-word match against Portuguese keywords, English
  slugs above. Competing matches are scored rather than simply "longest wins": word count dominates
  (so `leite coco` beats `leite`), then a match at the head of the line — receipts lead with the
  product noun and trail with brand, size and flavour, so `DET LIQ YPE 500ML CAP LIMAO` is detergent
  rather than lime — then a brand from `BRANDS`, which pins a category when a misleading generic noun
  leads (`TOMATE POMAROLA` is passata). Some issuers prefix their internal code and NCM onto the
  description (`#1700900#18069000#TRU PIST`); that is stripped before matching.
- **validate**: item count and the sum of item totals vs. the receipt total → warnings, not failures.

## Categorization at ingest

The keyword rules above are only the first of three layers. `apps/api/src/service/categorize.ts`
settles each item cheapest signal first:

1. **rules** — anything but `other` means they recognised the line, and they win outright;
2. **barcode memory** — `products.default_category`, so a product keeps one category across receipts
   even when stores print it differently. An item that nothing could place is not a memory, so a
   product stays open to learning until something categorizes it;
3. **the model** — one batched call per receipt covering only the lines the first two could not place.

Every layer is optional: with no barcode, no history and `CATEGORIZE_WITH_AI=false`, an item simply
stays `other`. A model outage is logged and ignored rather than failing the scan.

`apps/api/scripts/recategorize.ts` replays this chain over items already stored, so rule improvements
reach history. It prints a diff and writes nothing without `--apply`; it covers `nfce` purchases only
unless given `--all`, because `manual` and `pix` categories were chosen by the owner or the photo scan
rather than by the rules.

## Migration

`apps/api/scripts/import-legacy.ts` reads the prototype's `dados/{compras,transporte,doacoes}/*.json`
from a path given by env/arg, translates field names, and upserts by natural key (`access_key`, slug).
Idempotent — safe to re-run. Run once against the real data to seed the live DB; run a transform of a
copy to produce the anonymized `data/sample/` set.

## Data & privacy

Real data lives only in the owner's Postgres. It is never committed. `data/sample/` holds anonymized
fixtures (fake store names/CNPJs, jittered amounts, real structure) so the project is runnable by
anyone. `data/private/` is git-ignored for any local scratch.
