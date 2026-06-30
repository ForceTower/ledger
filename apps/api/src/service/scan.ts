import { fetchReceipt, NfceError, validateNfceUrl } from "@ledger/nfce";
import type { ScanResult } from "@ledger/shared-types";
import type { CacheClient } from "../cache";
import type { LedgerDb } from "../db";
import { ledgerErrorFromNfce } from "../error";
import { useLog } from "../logger";

export class ScanService {
  // `cache` is for a Redis lock around the write (the slug sequence must be computed serially).
  constructor(private readonly deps: { db: LedgerDb; cache: CacheClient; sefazBaseUrl: string }) {}

  async scan(url: string): Promise<ScanResult> {
    try {
      const link = validateNfceUrl(url);
      const fetched = await fetchReceipt(link);
      useLog()
        .withMetadata({
          accessKey: link.accessKey,
          uf: link.portal.uf,
          simpleLen: fetched.simpleHtml.length,
          fullLen: fetched.fullHtml.length,
        })
        .info("Fetched NFC-e receipt HTML");
    } catch (error) {
      if (error instanceof NfceError) throw ledgerErrorFromNfce(error);
      throw error;
    }

    // TODO (next increment): parse + categorize the fetched HTML, then upsert store, products,
    //   purchase (dedup on access_key), items, payments in a transaction, and return the real
    //   summary. Until then, return contract-shaped mock data so clients can build against a
    //   running server.
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
