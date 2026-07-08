import { fetchReceipt, NfceError, parseReceipt, validateNfceUrl } from "@ledger/nfce";
import type { FetchedReceipt } from "@ledger/nfce";
import type { ScanResult } from "@ledger/shared-types";
import status from "http-status";
import { type CacheClient, withLock } from "../cache";
import type { LedgerDb } from "../db";
import type { ScanRequestStatus } from "../db/schema";
import { LedgerError, ledgerErrorFromNfce } from "../error";
import { useLog } from "../logger";
import { saveParsedReceipt } from "./ingest";
import type { PurchaseService } from "./purchase";

const SCAN_WRITE_LOCK = "scan:write-lock";

interface ScanOutcome {
  status: ScanRequestStatus;
  purchaseSlug?: string;
  warnings?: string[];
  errorCode?: string;
  errorMessage?: string;
}

export class ScanService {
  // `cache` is for a Redis lock around the write (the slug sequence must be computed serially).
  constructor(
    private readonly deps: { db: LedgerDb; cache: CacheClient; purchase: PurchaseService; sefazBaseUrl: string },
  ) {}

  /** Process a scanned QR URL, recording every attempt (and how it went) in `scan_requests`. */
  async scan(url: string): Promise<ScanResult> {
    const startedAt = Date.now();
    try {
      const result = await this.process(url);
      await this.record(url, startedAt, {
        status: result.status,
        purchaseSlug: result.purchase.id,
        warnings: result.warnings,
      });
      return result;
    } catch (error) {
      await this.record(url, startedAt, {
        status: "failed",
        errorCode: error instanceof LedgerError ? (error.errorCode ?? "internal") : "internal",
        errorMessage: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }

  private async process(url: string): Promise<ScanResult> {
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

    const saved = await withLock(this.deps.cache, SCAN_WRITE_LOCK, () =>
      saveParsedReceipt(this.deps.db, parsed, { sourceHtml: fetched.simpleHtml }),
    );

    const purchase = await this.deps.purchase.get(saved.slug);
    if (!purchase) {
      throw new LedgerError(status.INTERNAL_SERVER_ERROR, `Saved purchase ${saved.slug} could not be read back`);
    }

    useLog().withMetadata({ slug: saved.slug, status: saved.status, warnings: saved.warnings }).info("Scan processed");
    return { status: saved.status, purchase, warnings: saved.warnings };
  }

  /** Best effort — the audit row must never turn a processed scan into an error. */
  private async record(url: string, startedAt: number, outcome: ScanOutcome): Promise<void> {
    try {
      await this.deps.db
        .insertInto("scanRequests")
        .values({
          url,
          status: outcome.status,
          errorCode: outcome.errorCode ?? null,
          errorMessage: outcome.errorMessage ?? null,
          purchaseSlug: outcome.purchaseSlug ?? null,
          warnings: outcome.warnings?.length ? JSON.stringify(outcome.warnings) : null,
          durationMs: Date.now() - startedAt,
        })
        .execute();
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      useLog().withError(err).error("Failed to record scan request");
    }
  }
}
