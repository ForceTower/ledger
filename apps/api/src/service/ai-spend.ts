import type { LedgerDb } from "../db";
import { useLog } from "../logger";
import type { AiUsage } from "./ai";

export type AiOperation = "photo_scan" | "entry" | "categorize" | "transfer" | "chat";

/** One successful AI run and what it cost. Failures never reach here — they throw before usage exists. */
export interface AiSpend {
  operation: AiOperation;
  model: string;
  transport: "api" | "agent";
  usage: AiUsage;
  durationMs: number;
  /** Chat only: the Agent SDK session the turn belongs to. */
  sessionId?: string;
  /** Chat only: how many turns the run took. */
  numTurns?: number;
}

/** What the services need to persist spend. {@link AiSpendRecorder} is the real one; tests stub it. */
export interface SpendRecorder {
  record(spend: AiSpend): Promise<void>;
}

/** Best effort — the audit row must never turn a successful AI run into an error. */
export class AiSpendRecorder implements SpendRecorder {
  constructor(private readonly deps: { db: LedgerDb }) {}

  async record(spend: AiSpend): Promise<void> {
    try {
      await this.deps.db
        .insertInto("aiRequests")
        .values({
          operation: spend.operation,
          model: spend.model,
          transport: spend.transport,
          inputTokens: spend.usage.inputTokens,
          outputTokens: spend.usage.outputTokens,
          costUsd: spend.usage.costUsd ?? null,
          durationMs: spend.durationMs,
          sessionId: spend.sessionId ?? null,
          numTurns: spend.numTurns ?? null,
        })
        .execute();
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      useLog().withError(err).error("Failed to record AI spend");
    }
  }
}
