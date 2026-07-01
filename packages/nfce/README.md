# @ledger/nfce

The NFC-e fetch + parse + categorize library — the reusable core of ledger. Given a scanned SEFAZ-BA
QR URL it returns a structured, validated, categorized purchase. No HTTP server, no database.

```ts
import { fetchReceipt, parseReceipt, categorize } from "@ledger/nfce";

const { simpleHtml, fullHtml } = await fetchReceipt(qrUrl, { baseUrl });
const receipt = parseReceipt(simpleHtml, fullHtml); // ParsedReceipt
```

## Status: port in progress

This is a TypeScript port of the prototype's Python pipeline (`fetch_nfce.py`, `parse_nfce.py`,
`categorize.py`). `fetch`, `parse`, and `categorize` (full ruleset) are implemented; what remains is
the API/DB ingestion that consumes `ParsedReceipt`. See `docs/architecture.md` (section
_packages/nfce — the port_).

## Equivalence testing

De-risk the port with fixtures: drop the prototype's saved receipt HTML into `tests/fixtures/`
(`<stem>.simple.html` + `<stem>.full.html`) alongside the expected `<stem>.json`, and assert
`parseReceipt(...)` matches. Only cut over from Python once outputs match across all fixtures.

> Fixtures may contain real store/CNPJ data — keep this folder out of the published repo until the
> HTML is anonymized, or use synthetic receipts.
