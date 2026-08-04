# Bank statement import

Design notes for importing bank statements and credit-card invoices, so that money the bank recorded
sits alongside the NFC-e purchases already in the ledger.

Status: **design only** — nothing here is implemented yet. Every example below is synthetic; the
findings come from real exports that are not, and will never be, in this repo.

## Why files, and not an API

- **Open Finance Brasil is closed to individuals.** Registering in the Diretório de Participantes
  requires proof of authorization to operate from the Banco Central — for the sandbox as well as
  production — and the transport is mutual TLS with certificates issued by the Open Finance PKI.
  There is no hobbyist tier to join; without the certificates a client cannot complete a handshake.
- **Aggregators are the only legal route to that data, and they keep a copy.** A regulated
  aggregator (an authorized ITP) can consume Open Finance on an individual's behalf, but the
  owner's full financial history then lives on a third party's servers. That contradicts the rule
  this project is built on: real data lives only in the owner's Postgres.
- **Unofficial bank APIs are gone.** Nubank closed unofficial access to its GraphQL endpoint in
  August 2023; requests now answer `401` with
  `www-authenticate: challenge-platform deep-link="nuapp://dev_auth"`, an in-app device
  authorization a headless client cannot satisfy.

What is left is the export button. Extraction stays manual; ingestion does not have to be.

## Sources

| Source              | Format | Availability                                      |
| ------------------- | ------ | ------------------------------------------------- |
| Checking account    | OFX    | Exported from the bank app/web, often by email    |
| Credit-card invoice | OFX    | **Closed invoices only** — open ones can't export |
| Some card issuers   | XLSX   | No OFX at all; out of scope for v1                |

Two limits worth designing around: some banks keep only a short window of statement history
(60 days is common), and card issuers may expose only the current and one prior closed invoice.
History is lost if exports are not taken regularly, which argues for making import cheap and
routine rather than perfect.

## OFX dialect notes

OFX 1.x is SGML, not XML, and Brazilian exports vary more than the spec implies. These are the
things that break a naive reader.

**The encoding header lies, in both directions.** Real exports have been observed declaring
`ENCODING:UTF-8`/`CHARSET:NONE` and `ENCODING:USASCII`/`CHARSET:1252` while both were actually
UTF-8. Keying off `CHARSET` turns every accented name into mojibake.

> Rule: attempt a strict UTF-8 decode; fall back to cp1252 only when it throws. Ignore the header.

**Both tag dialects appear.** Some files close every tag, others leave leaf tags open:

```
<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20260724000000[-3:BRT]<TRNAMT>-10.00<FITID>abc
<MEMO>Example</STMTTRN>
```

> Rule: a tag carrying text is a leaf whose closing tag is optional; a tag followed immediately by
> another tag is a container. That single rule parses both dialects with no per-bank branching.

**Other variations:** header lines separated by `\n` or by a bare `\r` (split on `[\r\n]+`);
decimal separator usually `.`, occasionally `,`; `DTPOSTED` carries a timezone suffix
(`20260724120000[-3:BRT]`) so only the leading eight digits are the calendar date.

**Account blocks differ by product.** Checking accounts use `BANKACCTFROM` with
`BANKID`/`BRANCHID`/`ACCTID`/`ACCTTYPE`. Card invoices use `CCACCTFROM` carrying **only** an
`ACCTID`, and that id is an opaque uuid rather than an account number. Every field except the
account id must be nullable. Statements nest under `BANKMSGSRSV1 → STMTTRNRS → STMTRS`, invoices
under `CREDITCARDMSGSRSV1 → CCSTMTTRNRS → CCSTMTRS`.

## FITID is not unique

`FITID` is the field OFX designates for deduplication, and the obvious schema is
`UNIQUE(account_id, fitid)`. That constraint is wrong here.

In a real card invoice, **a foreign-currency charge and its IOF line share one FITID**:

```
<FITID>0000aaaa-bbbb-cccc-dddd-eeeeeeeeeeee<TRNAMT>-25.00<MEMO>Example Subscription
<FITID>0000aaaa-bbbb-cccc-dddd-eeeeeeeeeeee<TRNAMT>-0.87<MEMO>IOF de "Example Subscription"
```

This is systematic, not an anomaly — it happens for every international charge, so any account with
a recurring foreign subscription would silently lose one row per month. (The IOF _reversal_ lines,
`IOF de volta de …`, do get their own ids.)

Measured over one real invoice: `fitid` alone collapsed distinct rows; both `fitid + date + amount`
and `date + amount + memo` recovered all of them.

> **Decision: `UNIQUE(account_id, fitid, amount)`.** A pure content hash was rejected because two
> genuinely distinct identical charges on the same day — entirely plausible with ride-hailing or
> small repeated purchases — would be wrongly merged. Keeping `fitid` in the key preserves whatever
> cross-export stability it has, while `amount` breaks the IOF collision.

**Open question:** whether a given transaction keeps its FITID across two exports of the same
period. If it does not, dedup needs a content-hash fallback column. Verify by exporting one closed
period twice and diffing before building on this.

## Double counting

The largest correctness risk, and the reason bank rows cannot simply be summed. The same money can
appear three times:

1. **Checking statement** — the card bill payment, one line for the whole invoice.
2. **Card invoice** — the individual purchases that add up to that bill.
3. **`purchases`** — NFC-e receipts, itemized, for a subset of those purchases.

Only layer 2 is spending. Layer 1 is a transfer between the owner's own accounts. Layer 3 is the
itemized detail behind some of layer 2's lines — a scanned supermarket receipt _is_ the card charge,
not a second purchase.

Rules:

- Bank rows are **evidence, never a spending total**. Nothing sums `bank_transactions.amount`
  alongside `purchases.paid_total`.
- Every row is classified with a `kind`; only card purchases are candidate spending.
- A bank row linked to a purchase contributes nothing of its own — the rule `transfers` already
  follows, where a linked transfer adds no spending because the note it paid for accounts for it.
- The chat system prompt has to say this outright, exactly as it already does for `transfers`.

Kinds observed so far, classifiable from the memo prefix: transfer sent, transfer received, card
purchase, card bill payment, investment in/out (bank savings products move money without spending
it), IOF fee, and issuer adjustments.

## Merchant identity

**OFX carries no CNPJ** — not in statements, not in invoices. This was checked directly; the only
identifiers present are counterparty names on transfers, alongside a **masked** CPF
(`•••.xxx.xxx-••`). Masked means it is not a lookup key, but name plus mask is a stable grouping key
for a recurring counterparty, which is enough to answer "everything I ever sent this person".

Card memos are acquirer descriptors truncated to roughly 22 characters, in a
`FACILITATOR*MERCHANT` shape where the prefix is a payment facilitator, delivery app, or marketplace
rather than the merchant. For marketplace lines the suffix names a third-party seller, which says
nothing about what was bought. Truncation destroys information permanently.

Resolution ladder, cheapest and most reliable first:

1. **Reconcile to an existing purchase** by date and amount, and inherit its store — including the
   real CNPJ that came from SEFAZ. Exact, free, offline, and the common case for scanned receipts.
2. **A seeded descriptor table** for national brands whose CNPJs are fixed and public. Handles the
   high-volume recurring merchants with no lookup at all.
3. **A learned descriptor → store table.** Anything confirmed once is never asked again.
4. **AI or search proposal** for what is left — proposing, never deciding.

Two constraints on that last rung. It sends merchant names off the owner's machine, so it is
opt-in per descriptor rather than a background pass. And an inferred merchant must never silently
become a category: inference happens once at import, is confirmed by the owner, and is then
persisted — the same shape as `products.default_category` learning from barcodes, and the same
reason `stores` is user-curated data a receipt never overwrites. A guess that changes between two
runs of the same question is worse than no guess.

## Schema sketch

```
bank_accounts
  id, institution, account_id, branch_id, account_type, name (user-editable),
  currency, created_at
  unique (institution, account_id)

bank_transactions
  id, account_id → bank_accounts, fitid, posted_on, amount (signed), kind,
  description, memo, counterparty_name, counterparty_mask,
  purchase_id → purchases (nullable), transfer_id → transfers (nullable),
  raw jsonb, created_at
  unique (account_id, fitid, amount)
  index on posted_on, purchase_id
```

`raw` keeps the source node for audit, parallel to `purchases.source_html` and `transfers.extracted`.
Money stays `numeric(12,2)`; dates stay `date`, matching the rest of the schema.

## Ingestion

`POST /statements/import` takes the OFX itself and returns counts (`imported`, `duplicate`,
`skipped`). Parsing lives in a package with no HTTP or DB concerns, tested against fixtures, the way
`@ledger/nfce` is — the fixtures being synthetic files covering each dialect quirk above.

A second source can feed the same endpoint later: banks email the export, so a mailbox watcher on
the server can pull the attachment and post it. Extraction stays a button press; everything after it
becomes automatic, and nothing leaves the owner's mailbox and server.

## Open questions

1. **FITID stability across exports** — decides whether a content-hash fallback is needed.
2. **Untested dialects** — only some issuers' real files have been parsed; others are inferred.
3. **Parcelas.** An installment purchase appears on many monthly invoices. Counting it once at
   purchase time (accrual) matches the NFC-e receipt and the current shape of `purchases`; spreading
   it matches what leaves the account. Not yet observed in a sample, and it changes what "spent this
   month" means.
4. **Card issuers with no OFX** — XLSX or PDF only. Deferred.
