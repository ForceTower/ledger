import { type App, cert, initializeApp } from "firebase-admin/app";
import { getMessaging, type Messaging } from "firebase-admin/messaging";
import { sql } from "../db";
import type { LedgerDb } from "../db";
import { useLog } from "../logger";

const MULTICAST_BATCH_SIZE = 500;

// FCM error codes that mean the token is dead — safe to prune from the DB.
const INVALID_TOKEN_ERROR_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

export interface NotificationPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface SendOutcome {
  successCount: number;
  failureCount: number;
  invalidTokens: string[];
}

export interface NotificationServiceConfig {
  db: LedgerDb;
  // Base64-encoded Firebase service account JSON. When absent, push is disabled and every send is a
  // no-op — the rest of the app runs unchanged (e.g. local dev without Firebase credentials).
  serviceAccountBase64?: string;
}

export class NotificationService {
  private readonly db: LedgerDb;
  private readonly messaging: Messaging | null;

  constructor(cfg: NotificationServiceConfig) {
    this.db = cfg.db;
    if (cfg.serviceAccountBase64) {
      const decoded = Buffer.from(cfg.serviceAccountBase64, "base64").toString("utf-8");
      const serviceAccount = JSON.parse(decoded);
      const app: App = initializeApp({ credential: cert(serviceAccount) }, "ledger");
      this.messaging = getMessaging(app);
    } else {
      this.messaging = null;
    }
  }

  get enabled(): boolean {
    return this.messaging !== null;
  }

  async registerToken(token: string, platform: string): Promise<void> {
    await this.db
      .insertInto("deviceTokens")
      .values({ token, platform })
      .onConflict((oc) => oc.column("token").doUpdateSet({ lastSeenAt: sql`now()`, platform }))
      .execute();
  }

  async sendToAll(payload: NotificationPayload): Promise<SendOutcome> {
    const rows = await this.db.selectFrom("deviceTokens").select("token").execute();
    return this.sendToTokens(
      rows.map((r) => r.token),
      payload,
    );
  }

  async sendToTokens(tokens: string[], payload: NotificationPayload): Promise<SendOutcome> {
    if (!this.messaging || tokens.length === 0) {
      return { successCount: 0, failureCount: 0, invalidTokens: [] };
    }

    let successCount = 0;
    let failureCount = 0;
    const invalidTokens: string[] = [];

    for (let i = 0; i < tokens.length; i += MULTICAST_BATCH_SIZE) {
      const batch = tokens.slice(i, i + MULTICAST_BATCH_SIZE);
      const response = await this.messaging.sendEachForMulticast({
        tokens: batch,
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
      });

      successCount += response.successCount;
      failureCount += response.failureCount;

      response.responses.forEach((res, idx) => {
        if (res.success || !res.error) return;
        const token = batch[idx]!;
        if (INVALID_TOKEN_ERROR_CODES.has(res.error.code)) {
          invalidTokens.push(token);
        } else {
          useLog().withError(res.error).withMetadata({ code: res.error.code }).error("FCM send failed for token");
        }
      });
    }

    if (invalidTokens.length > 0) {
      await this.pruneInvalidTokens(invalidTokens);
    }

    return { successCount, failureCount, invalidTokens };
  }

  private async pruneInvalidTokens(tokens: string[]): Promise<void> {
    await this.db.deleteFrom("deviceTokens").where("token", "in", tokens).execute();
    useLog().withMetadata({ count: tokens.length }).info("Pruned invalid FCM tokens");
  }
}
