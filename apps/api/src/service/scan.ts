import { fetchReceipt, NfceError, parseReceipt, validateNfceUrl } from "@ledger/nfce";
import type { FetchedReceipt } from "@ledger/nfce";
import type { ScanResult } from "@ledger/shared-types";
import status from "http-status";
import { type CacheClient, withLock } from "../cache";
import type { LedgerDb } from "../db";
import { LedgerError, ledgerErrorFromNfce } from "../error";
import { useLog } from "../logger";
import { saveParsedReceipt } from "./ingest";

const SCAN_WRITE_LOCK = "scan:write-lock";

export class ScanService {
  // `cache` is for a Redis lock around the write (the slug sequence must be computed serially).
  constructor(private readonly deps: { db: LedgerDb; cache: CacheClient; sefazBaseUrl: string }) {}

  async scan(url: string): Promise<ScanResult> {
    let fetched: FetchedReceipt;
    try {
      const link = validateNfceUrl(url);
      fetched = await fetchReceipt(link);
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

    const parsed = parseReceipt(fetched.simpleHtml, fetched.fullHtml);
    if (parsed.items.length === 0 || !parsed.date) {
      throw new LedgerError(status.UNPROCESSABLE_ENTITY, "Could not parse the receipt page", "parse_failed");
    }
    // The key printed in the HTML can be garbled (the parser only warns); the one from the
    // validated QR URL is always 44 digits, and it is our dedup key.
    if (!/^\d{44}$/.test(parsed.receipt.accessKey)) {
      parsed.receipt.accessKey = fetched.accessKey;
    }

    const result = await withLock(this.deps.cache, SCAN_WRITE_LOCK, () =>
      saveParsedReceipt(this.deps.db, parsed, { sourceHtml: fetched.simpleHtml }),
    );

    useLog()
      .withMetadata({ slug: result.purchase.id, status: result.status, warnings: result.warnings })
      .info("Scan processed");
    return result;
  }
}
