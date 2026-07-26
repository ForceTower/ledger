# API Contract

The source of truth for every client (the iOS app today, a web dashboard later). The TypeScript
types live in `packages/shared-types`; Swift mirrors them. All fields are English.

## Conventions

- Base URL is configurable per client. Behind a Cloudflare Tunnel in production.
- **Auth**: every endpoint except `GET /` requires `Authorization: Bearer <API_TOKEN>`. Missing or
  wrong token → `401`.
- **Envelope**: every response is wrapped:

  ```jsonc
  // success
  { "ok": true,  "message": "…", "data": <T>,  "error": null }
  // failure
  { "ok": false, "message": "…", "data": null, "error": <details|null>, "errorCode": "…"|null }
  ```

- Money is a JSON number (BRL). Dates are `YYYY-MM-DD`; times are `HH:MM:SS`.

## Types

```ts
type Category =
  | "produce"
  | "meat"
  | "dairy_deli"
  | "bakery"
  | "grocery"
  | "beverages"
  | "snacks_sweets"
  | "frozen"
  | "cleaning"
  | "hygiene"
  | "pet"
  | "household"
  | "other";

interface PurchaseSummary {
  id: string; // slug, e.g. "2026-03-26_atacadao_01"
  store: string; // display name
  date: string;
  time: string;
  totalPaid: number;
  itemCount: number;
  categories: Record<Category, number>; // category -> item count (only present keys)
}

interface PurchaseItem {
  seq: number;
  description: string;
  code: string;
  barcode: string | null; // GTIN/EAN; null for weighed produce/meat or manual entries
  quantity: number;
  unit: string;
  unitPrice: number;
  total: number;
  category: Category;
}

interface Purchase {
  id: string; // slug
  date: string;
  time: string;
  source: "nfce" | "manual" | "pix";
  store: { name: string; legalName: string | null; cnpj: string | null; address: string | null };
  receipt: { number: number | null; series: number | null; accessKey: string } | null;
  items: PurchaseItem[];
  totals: { itemCount: number; gross: number; discount: number; totalPaid: number };
  payments: { code: number | null; method: string; amount: number; change?: number }[];
  taxesTotal: number | null;
}

interface PurchasePage {
  items: Purchase[];
  page: number; // 1-based
  pageSize: number; // fixed: 5
  total: number; // purchases matching the filters, across all pages
  hasMore: boolean;
}

interface PricePoint {
  date: string;
  store: string;
  unitPrice: number;
  purchaseId: string;
}

// A bank-transfer receipt (Pix comprovante) extracted by AI from a screenshot. Transfers
// materialize into a regular Purchase (source: "pix") so they appear in the history feed;
// the transfer row is kept as raw evidence and dedup anchor.
interface Transfer {
  transactionId: string; // the bank's end-to-end ID (e.g. "E1823…"); dedup key
  type: "pix";
  amount: number;
  date: string;
  time: string | null;
  destination: {
    name: string;
    institution: string | null;
    agency: string | null;
    account: string | null;
  };
  origin: {
    name: string;
    institution: string | null;
    agency: string | null;
    account: string | null;
  } | null;
  purchaseId: string | null; // slug of the materialized purchase
}

// Reading a transfer receipt and saving it are two steps, because the owner gets to correct the
// category and decide whether the transfer pays for a note already in the history.
interface TransferMatch {
  purchaseId: string;
  store: string;
  date: string;
  time: string;
  totalPaid: number;
  itemCount: number;
}

interface TransferScanResult {
  transfer: Transfer;
  category: Category; // the AI's guess for the transfer as a whole
  match: TransferMatch | null; // a same-day purchase with the same total
  comment: string; // pt-BR
}

interface TransferSaveRequest {
  transfer: Transfer;
  category: Category;
  linkedPurchaseId: string | null;
}

interface TransferSaveResult {
  transfer: Transfer;
  purchase: Purchase; // source: "pix"
}
```

## Endpoints

### `GET /`

Liveness. `200` with `data: "ledger API"`. No auth.

### `GET /health`

`200` `{ ok: true, data: { db: true, version: "0.1.0", purchaseCount: 23 } }` when the DB is
reachable; `503` otherwise. Powers the Settings "test connection" probe (it also validates the
token, since `/health` requires auth).

### `POST /scan`

Body: `{ "url": string }` — the full scanned NFC-e QR string (`…?p=<44-digit-key>|2|1|1|<hash>`).
The hash is required; the app sends the whole scanned payload.

Every attempt — success or failure — is recorded server-side in the `scan_requests` table (the raw
scanned URL, the outcome, and the error when it failed), so the owner can audit what was scanned
and why a link failed.

Outcomes are normal results, not errors:

```jsonc
// 200 — saved, or already existed (status distinguishes)
{
  "ok": true,
  "message": "Purchase saved.",
  "data": {
    "status": "saved", // "saved" | "duplicate"
    // the full Purchase (same shape as GET /purchases/:id), so the app can render
    // the result sheet and mirror it into the local store without a second request
    "purchase": {
      "id": "2026-03-26_atacadao_01",
      "date": "2026-03-26",
      "time": "14:44:08",
      "source": "nfce",
      "store": { "name": "Atacadão", "legalName": "…", "cnpj": "…", "address": "…" },
      "receipt": { "number": 123456, "series": 1, "accessKey": "2926…44" },
      "items": [{ "seq": 1, "description": "Bacon Fatiado Seara", "...": "…" }],
      "totals": { "itemCount": 10, "gross": 210.75, "discount": 2.0, "totalPaid": 208.75 },
      "payments": [{ "code": 3, "method": "Cartão de Crédito", "amount": 208.75 }],
      "taxesTotal": 34.02,
    },
    "warnings": [], // non-empty = saved but validation flagged something
  },
  "error": null,
}
```

Genuine failures use the failure envelope with an `errorCode`:

Failure statuses are always 4xx: the production Cloudflare Tunnel replaces origin `502`/`504`
bodies with its own error stub, which would strip the envelope (and `errorCode`) before it reaches
the app. Clients should key off `errorCode`, not the HTTP status.

| errorCode      | HTTP | meaning                                                    |
| -------------- | ---- | ---------------------------------------------------------- |
| `invalid_url`  | 400  | URL has no `p=` with a 44-digit key (bad/incomplete QR)    |
| `expired`      | 404  | SEFAZ link expired / receipt not found                     |
| `unavailable`  | 424  | SEFAZ unreachable or returned no products                  |
| `parse_failed` | 422  | fetched the page but could not parse it                    |
| `qr_rejected`  | 422  | SEFAZ refused the QR signature — offer the access-key flow |

`qr_rejected` means the store's POS signs its QR codes with a CSC the SEFAZ no longer recognizes
(e.g. `[QRCode v2.00]: 103 - Identificador de CSC inexistente`). Rescanning never helps, but the
receipt itself exists — clients should offer the access-key consultation below.

### `POST /scan/key/challenge`

Start an access-key consultation — the fallback when `/scan` answered `qr_rejected`. The portal
serves any authorized receipt by bare 44-digit key, but gates that flow behind an image captcha,
so the server opens the SEFAZ session and relays the image for the owner to read.

Body: `{ "accessKey": string }` — the 44-digit key (the digits in the QR's `p=` parameter).

```jsonc
// 200
{
  "ok": true,
  "message": "Captcha challenge created.",
  "data": {
    "challengeId": "6f0f…", // opaque; answer via POST /scan/key
    "captchaImage": "/9j/4AAQ…", // JPEG bytes, base64 (~180×50, 4–5 characters)
    "expiresIn": 300, // seconds before the challenge lapses
  },
  "error": null,
}
```

Failures: `invalid_url` (400) for a malformed key or unsupported state; `unavailable` (424) when
SEFAZ won't serve the form or the captcha.

### `POST /scan/key`

Answer the captcha and complete the consultation. On success the receipt runs through the same
pipeline as `/scan` — the response body (and the `scan_requests` audit row, recorded under
`access-key:<key>`) is identical to `POST /scan`'s.

Body: `{ "challengeId": string, "captcha": string }` — the characters the owner read.

Each challenge accepts exactly one answer: SEFAZ invalidates the shown image on every attempt, so
after any failure below the client must request a fresh challenge (and show the new image).

| errorCode           | HTTP | meaning                                             |
| ------------------- | ---- | --------------------------------------------------- |
| `challenge_expired` | 410  | unknown or lapsed `challengeId` — request a new one |
| `captcha_rejected`  | 422  | wrong captcha answer — request a new challenge      |
| `expired`           | 404  | SEFAZ does not know this key (yet) — retry later    |
| `unavailable`       | 424  | SEFAZ unreachable or refused the consultation       |
| `parse_failed`      | 422  | fetched the page but could not parse it             |

### `POST /scan/photo`

AI item identification: take a photo of one or more items — or of a printed receipt listing them —
and the server asks Claude to identify and categorize them. Body: `multipart/form-data` with an
`image` field (JPEG, PNG, or WebP, ≤ 10 MB).

Server configuration (env vars, shared by every AI read): `ANTHROPIC_API_KEY` (when set, the
Anthropic API is used; otherwise the server falls back to the local `claude` CLI), `CLAUDE_BIN`
(default `claude`), `CLAUDE_MODEL` (default `claude-haiku-4-5`), `CLAUDE_PHOTO_PROMPT` (the
identification instruction; the strict output format is always enforced server-side),
`CLAUDE_TIMEOUT_MS` (default `60000`).

`items` carries one entry per distinct product, most prominent first, and is never empty (several
copies of the same product are one entry — the app asks the owner for the quantity). At most 20
entries. A rejection is a normal result, not an error — the AI declines when it cannot identify
anything:

```jsonc
// 200 — identified
{
  "ok": true,
  "message": "2 items identified.",
  "data": {
    "status": "identified",
    "items": [
      {
        "description": "Café Torrado e Moído 500g", // pt-BR, like a receipt line
        "category": "grocery",
        "confidence": 0.92, // 0..1
      },
      {
        "description": "Leite Integral 1L",
        "category": "dairy_deli",
        "confidence": 0.81,
      },
    ],
    "comment": "O café parece ser da marca Pilão.",
  },
  "error": null,
}

// 200 — rejected
{
  "ok": true,
  "message": "Photo rejected by the AI.",
  "data": {
    "status": "rejected",
    "reason": "unclear_image", // "no_item" | "unclear_image" | "inappropriate"
    "comment": "A foto está desfocada demais para identificar o produto.",
  },
  "error": null,
}
```

Genuine failures use the failure envelope with an `errorCode`:

| errorCode           | HTTP | meaning                                                    |
| ------------------- | ---- | ---------------------------------------------------------- |
| `invalid_image`     | 400  | missing `image` field, unsupported type, or bad size       |
| `ai_unavailable`    | 424  | the API call or `claude` CLI failed, errored, or timed out |
| `ai_invalid_output` | 424  | the model ran but its output did not match the contract    |

### `POST /scan/transfer`

AI extraction of a bank-transfer receipt (Pix comprovante). Body: `multipart/form-data` with an
`image` field (the screenshot; JPEG, PNG, or WebP, ≤ 10 MB) and/or a `text` field (the receipt text
the owner copied out of the banking app, ≤ 8000 chars). At least one of the two is required — banks
put the amount in the screenshot, in the copied text, or both. When both arrive the prompt tells the
model to trust the text, since it was copied rather than read off a screenshot.

The upload's type is read from its own first bytes, not from the filename or the declared
content type.

Reading is not saving: this endpoint persists nothing. It returns `TransferScanResult` — the
extraction, a suggested `category` for the whole transfer, and `match`, a purchase from the same day
whose total equals `transfer.amount` (`null` when there is none). Purchases that came from a
transfer themselves, and notes another transfer already claims, are never offered as matches; when
several qualify, the one closest in time wins. The client shows both for review.

Uses the same server configuration as `POST /scan/photo`, with `CLAUDE_TRANSFER_PROMPT` in place of
`CLAUDE_PHOTO_PROMPT`.

Genuine failures use the failure envelope with an `errorCode`:

| errorCode           | HTTP | meaning                                                    |
| ------------------- | ---- | ---------------------------------------------------------- |
| `invalid_input`     | 400  | neither `image` nor `text`, unsupported type, or bad size  |
| `not_a_transfer`    | 422  | the AI read it but it is not a transfer receipt            |
| `ai_unavailable`    | 424  | the API call or `claude` CLI failed, errored, or timed out |
| `ai_invalid_output` | 424  | the model ran but its output did not match the contract    |

### `POST /transfers`

Persists a reviewed transfer. Body: `TransferSaveRequest`.

Inserts the `transfers` row (migration 004) keyed by `transactionId`. What it does with the money
depends on `linkedPurchaseId`:

- **`null`** — materializes a `Purchase` with `source: "pix"`, a single line item under the chosen
  `category`, and a `Pix` payment, so the transfer shows up in the history feed on its own.
- **a purchase slug** — attaches the transfer to that note and materializes nothing. The note
  already accounts for the money, so the transfer adds no spending of its own.

Re-posting the same `transactionId` is idempotent — it returns what is already stored rather than
double-counting.

`data: TransferSaveResult` — the stored transfer plus the purchase it is attached to (the new one,
or the linked note), so the client can mirror it without a second request.

### `GET /purchases?page=&from=&to=&store=`

The history feed. `data: PurchasePage` — **full** `Purchase` objects (same shape as
`GET /purchases/:id`), newest first, 5 per page. The app pages through this to mirror the whole
dataset into its local database for offline use (drives the "Histórico" list and its detail screen).

All query params optional. `page` is 1-based (default 1); a page past the end returns empty `items`.
`from`/`to` are `YYYY-MM-DD` (inclusive); `store` matches the store's display name exactly.

### `GET /purchases/:id`

`data: Purchase` (full). `404` if unknown.

### `GET /products/:barcode/prices`

`data: PricePoint[]` — what this GTIN cost across stores/time. Powers price-history views.

### `POST /devices/token`

Register the device's FCM push token. Body: `{ "token": string, "platform"?: "ios" | "android" }`
(defaults to `ios`). Idempotent — re-registering the same token just refreshes `lastSeenAt`. If the
server has no Firebase credentials, push is disabled and registration is still accepted (no-op sends).

### Future (stub in UI only)

- `POST /scan-image` — multipart photo fallback (server decodes the QR, then `/scan`).
- `POST /ask` — natural-language question over the whole dataset (Anthropic API + SQL tools).
