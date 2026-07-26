import {
  completeKeyConsult,
  fetchReceipt,
  type KeyConsultSession,
  NfceError,
  parseReceipt,
  startKeyConsult,
  validateNfceUrl,
} from "@ledger/nfce";
import type { FetchedReceipt } from "@ledger/nfce";
import type { KeyScanChallenge, ScanResult } from "@ledger/shared-types";
import status from "http-status";
import { type CacheClient, withLock } from "../cache";
import type { LedgerDb } from "../db";
import type { ScanRequestStatus } from "../db";
import { LedgerError, ledgerErrorFromNfce } from "../error";
import { useLog } from "../logger";
import type { CategorizerService } from "./categorize";
import { saveParsedReceipt, WRITE_LOCK } from "./ingest";
import type { PurchaseService } from "./purchase";

interface ScanOutcome {
  status: ScanRequestStatus;
  purchaseSlug?: string;
  warnings?: string[];
  errorCode?: string;
  errorMessage?: string;
}

/** How long an unanswered captcha challenge stays valid. SEFAZ's own session outlives this; the
 * bound exists so abandoned sessions don't pile up. */
const CHALLENGE_TTL_MS = 5 * 60 * 1000;
const CHALLENGE_TTL_SECONDS = CHALLENGE_TTL_MS / 1000;

interface PendingChallenge {
  session: KeyConsultSession;
  expiresAt: number;
}

export class ScanService {
  /** Open SEFAZ sessions awaiting their captcha answer. Process-local by design — there is one
   * API process, and a SEFAZ cookie session cannot be resumed elsewhere anyway. */
  private readonly challenges = new Map<string, PendingChallenge>();

  // `cache` is for a Redis lock around the write (the slug sequence must be computed serially).
  constructor(
    private readonly deps: {
      db: LedgerDb;
      cache: CacheClient;
      purchase: PurchaseService;
      categorizer: CategorizerService;
      sefazBaseUrl: string;
    },
  ) {}

  /** Process a scanned QR URL, recording every attempt (and how it went) in `scan_requests`. */
  async scan(url: string): Promise<ScanResult> {
    return await this.recorded(url, () => this.process(url));
  }

  /** Open a SEFAZ access-key consultation and hand back its anti-robot captcha for the owner to
   * read. The fallback when SEFAZ refuses a QR payload (`qr_rejected`). */
  async startKeyChallenge(accessKey: string): Promise<KeyScanChallenge> {
    this.sweepChallenges();
    try {
      const { session, captchaImage } = await startKeyConsult(accessKey);
      const challengeId = crypto.randomUUID();
      this.challenges.set(challengeId, { session, expiresAt: Date.now() + CHALLENGE_TTL_MS });
      useLog().withMetadata({ challengeId, accessKey }).info("Started access-key challenge");
      return {
        challengeId,
        captchaImage: Buffer.from(captchaImage).toString("base64"),
        expiresIn: CHALLENGE_TTL_SECONDS,
      };
    } catch (error) {
      if (error instanceof NfceError) throw ledgerErrorFromNfce(error);
      throw error;
    }
  }

  /** Answer a challenge's captcha and run the receipt through the normal save path. */
  async completeKeyChallenge(challengeId: string, captcha: string): Promise<ScanResult> {
    this.sweepChallenges();
    const pending = this.challenges.get(challengeId);
    if (pending === undefined) {
      throw new LedgerError(status.GONE, "Challenge not found or expired — request a new captcha", "challenge_expired");
    }
    // One shot per challenge: SEFAZ invalidates the shown image on every attempt, so a retry
    // needs a fresh session and a fresh image either way.
    this.challenges.delete(challengeId);

    return await this.recorded(`access-key:${pending.session.accessKey}`, async () => {
      let fetched: FetchedReceipt;
      try {
        fetched = await completeKeyConsult(pending.session, captcha);
        useLog()
          .withMetadata({
            accessKey: pending.session.accessKey,
            uf: pending.session.portal.uf,
            simpleLen: fetched.simpleHtml.length,
            fullLen: fetched.fullHtml.length,
          })
          .info("Fetched NFC-e receipt HTML via access key");
      } catch (error) {
        if (error instanceof NfceError) throw ledgerErrorFromNfce(error);
        throw error;
      }
      return await this.ingest(fetched);
    });
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

    return await this.ingest(fetched);
  }

  /** Parse the fetched pages and persist — shared by the QR and access-key paths. */
  private async ingest(fetched: FetchedReceipt): Promise<ScanResult> {
    const parsed = parseReceipt(fetched.simpleHtml, fetched.fullHtml);
    if (parsed.items.length === 0 || !parsed.date) {
      throw new LedgerError(status.UNPROCESSABLE_ENTITY, "Could not parse the receipt page", "parse_failed");
    }
    // The key printed in the HTML can be garbled (the parser only warns); the one from the
    // validated QR URL is always 44 digits, and it is our dedup key.
    if (!/^\d{44}$/.test(parsed.receipt.accessKey)) {
      parsed.receipt.accessKey = fetched.accessKey;
    }

    parsed.items = await this.deps.categorizer.resolve(parsed.items);

    const saved = await withLock(this.deps.cache, WRITE_LOCK, () =>
      saveParsedReceipt(this.deps.db, parsed, { sourceHtml: fetched.simpleHtml }),
    );

    const purchase = await this.deps.purchase.get(saved.slug);
    if (!purchase) {
      throw new LedgerError(status.INTERNAL_SERVER_ERROR, `Saved purchase ${saved.slug} could not be read back`);
    }

    useLog().withMetadata({ slug: saved.slug, status: saved.status, warnings: saved.warnings }).info("Scan processed");
    return { status: saved.status, purchase, warnings: saved.warnings };
  }

  /** Run a scan attempt and record how it went in `scan_requests`, success or failure. */
  private async recorded(url: string, run: () => Promise<ScanResult>): Promise<ScanResult> {
    const startedAt = Date.now();
    try {
      const result = await run();
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

  private sweepChallenges(): void {
    const now = Date.now();
    for (const [id, challenge] of this.challenges) {
      if (challenge.expiresAt <= now) this.challenges.delete(id);
    }
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
