import type { ScanResult } from "@ledger/shared-types";
import type { CacheClient } from "../cache";
import type { LedgerDb } from "../db";
import { LedgerError } from "../error";

const ACCESS_KEY_IN_URL = /[?&]p=\d{44}/;

export class ScanService {
  // `cache` is for a Redis lock around the write (the slug sequence must be computed serially).
  constructor(private readonly deps: { db: LedgerDb; cache: CacheClient; sefazBaseUrl: string }) {}

  async scan(url: string): Promise<ScanResult> {
    if (!ACCESS_KEY_IN_URL.test(url)) {
      throw new LedgerError(400, "QR URL is missing the 44-digit access key", "invalid_url");
    }

    // TODO: the real flow —
    //   1. fetch the simplified + detailed receipt via @ledger/nfce (deps.sefazBaseUrl)
    //   2. parse + categorize into a structured purchase
    //   3. upsert store, products, purchase (dedup on access_key), items, payments in a transaction
    //   4. return { status: "saved" | "duplicate", purchase: summary, warnings }
    // Until then, return contract-shaped mock data so clients can build against a running server.
    return MOCK_SCAN_RESULT;
  }
}

const MOCK_SCAN_RESULT: ScanResult = {
  status: "saved",
  purchase: {
    id: "2026-03-26_atacadao_01",
    store: "Atacadão",
    date: "2026-03-26",
    time: "14:44:08",
    totalPaid: 208.75,
    itemCount: 10,
    categories: { meat: 4, grocery: 6 },
    itemsPreview: [
      { description: "Bov. Acém s/ Osso", quantity: 1.252, total: 43.69 },
      { description: "Bacon Fatiado Seara", quantity: 1, total: 23.9 },
    ],
  },
  warnings: [],
};
