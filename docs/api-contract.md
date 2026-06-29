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
  source: "nfce" | "manual";
  store: { name: string; legalName: string | null; cnpj: string | null; address: string | null };
  receipt: { number: number | null; series: number | null; accessKey: string } | null;
  items: PurchaseItem[];
  totals: { itemCount: number; gross: number; discount: number; totalPaid: number };
  payments: { code: number | null; method: string; amount: number; change?: number }[];
  taxesTotal: number | null;
}

interface PricePoint {
  date: string;
  store: string;
  unitPrice: number;
  purchaseId: string;
}
```

## Endpoints

### `GET /`

Liveness. `200` with `data: "ledger API"`. No auth.

### `GET /health`

`200` `{ ok: true, data: { db: true } }` when the DB is reachable; `503` otherwise.

### `POST /scan`

Body: `{ "url": string }` — the full scanned NFC-e QR string (`…?p=<44-digit-key>|2|1|1|<hash>`).
The hash is required; the app sends the whole scanned payload.

Outcomes are normal results, not errors:

```jsonc
// 200 — saved, or already existed (status distinguishes)
{
  "ok": true,
  "message": "Purchase saved.",
  "data": {
    "status": "saved", // "saved" | "duplicate"
    "purchase": {
      // PurchaseSummary + itemsPreview
      "id": "2026-03-26_atacadao_01",
      "store": "Atacadão",
      "date": "2026-03-26",
      "time": "14:44:08",
      "totalPaid": 208.75,
      "itemCount": 10,
      "categories": { "meat": 4, "grocery": 6 },
      "itemsPreview": [{ "description": "Bacon Fatiado Seara", "quantity": 1.0, "total": 23.9 }],
    },
    "warnings": [], // non-empty = saved but validation flagged something
  },
  "error": null,
}
```

Genuine failures use the failure envelope with an `errorCode`:

| errorCode      | HTTP | meaning                                                 |
| -------------- | ---- | ------------------------------------------------------- |
| `invalid_url`  | 400  | URL has no `p=` with a 44-digit key (bad/incomplete QR) |
| `expired`      | 502  | SEFAZ link expired / receipt not found                  |
| `unavailable`  | 502  | SEFAZ unreachable or returned no products               |
| `parse_failed` | 422  | fetched the page but could not parse it                 |

### `GET /purchases?from=&to=&store=`

`data: PurchaseSummary[]`, newest first. All query params optional.

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
