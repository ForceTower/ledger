import { promises as fs } from "node:fs";
import path from "node:path";
import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { FileMigrationProvider, Migrator, sql } from "kysely";
import { type LedgerDb, makeDb } from "../src/db";
import { type AiSpend, AiSpendRecorder } from "../src/service/ai-spend";

// Opt-in, same as transfer-service.test.ts:
//   docker compose -f infra/docker/docker-compose.yml up -d postgres
//   TEST_DATABASE_URL=postgres://ledger:ledger@localhost:5433/ledger_test bun test
const connectionString = process.env["TEST_DATABASE_URL"];

function spendFor(overrides: Partial<AiSpend> = {}): AiSpend {
  return {
    operation: "photo_scan",
    model: "claude-haiku-4-5",
    transport: "api",
    usage: { inputTokens: 100, outputTokens: 50, costUsd: undefined },
    durationMs: 1200,
    ...overrides,
  };
}

describe("AiSpendRecorder", () => {
  test("a broken database never turns a successful AI run into an error", async () => {
    const recorder = new AiSpendRecorder({ db: makeDb("postgres://unused:unused@localhost:1/unused") });
    // Resolving without throwing is the whole contract.
    await recorder.record(spendFor());
  });
});

describe.skipIf(!connectionString)("AiSpendRecorder against Postgres", () => {
  const db: LedgerDb = makeDb(connectionString ?? "");
  const recorder = new AiSpendRecorder({ db });

  afterAll(async () => {
    await db.destroy();
  });

  beforeEach(async () => {
    await new Migrator({
      db,
      provider: new FileMigrationProvider({
        fs,
        path,
        migrationFolder: path.resolve(import.meta.dir, "../src/db/migrations"),
      }),
    }).migrateToLatest();
    await sql`truncate ai_requests restart identity cascade`.execute(db);
  });

  test("an unpriced one-shot run lands with a null cost and no chat fields", async () => {
    await recorder.record(spendFor());

    const row = await db.selectFrom("aiRequests").selectAll().executeTakeFirstOrThrow();
    expect(row.operation).toBe("photo_scan");
    expect(row.model).toBe("claude-haiku-4-5");
    expect(row.transport).toBe("api");
    expect(row.inputTokens).toBe(100);
    expect(row.outputTokens).toBe(50);
    expect(row.costUsd).toBeNull();
    expect(row.durationMs).toBe(1200);
    expect(row.sessionId).toBeNull();
    expect(row.numTurns).toBeNull();
    expect(row.createdAt).toBeInstanceOf(Date);
  });

  test("a chat turn keeps its cost, session and turn count", async () => {
    await recorder.record(
      spendFor({
        operation: "chat",
        transport: "agent",
        usage: { inputTokens: 100, outputTokens: 50, costUsd: 0.0123 },
        sessionId: "11111111-2222-3333-4444-555555555555",
        numTurns: 2,
      }),
    );

    const row = await db.selectFrom("aiRequests").selectAll().executeTakeFirstOrThrow();
    expect(row.operation).toBe("chat");
    expect(row.transport).toBe("agent");
    expect(row.costUsd).toBe(0.0123);
    expect(row.sessionId).toBe("11111111-2222-3333-4444-555555555555");
    expect(row.numTurns).toBe(2);
  });
});
