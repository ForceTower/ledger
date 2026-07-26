import { promises as fs } from "node:fs";
import path from "node:path";
import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { FileMigrationProvider, Migrator, sql } from "kysely";
import { createCacheClient } from "../src/cache";
import { type LedgerDb, makeDb } from "../src/db";
import { LedgerError } from "../src/error";
import type { AiRequest, AiResponse, AiRunner } from "../src/service/ai";
import { PurchaseService } from "../src/service/purchase";
import { TransferService } from "../src/service/transfer";

// Opt-in, same as transfer-ingest.test.ts:
//   docker compose -f infra/docker/docker-compose.yml up -d postgres redis
//   TEST_DATABASE_URL=postgres://ledger:ledger@localhost:5433/ledger_test \
//   TEST_REDIS_URL=redis://localhost:6380 bun test
const connectionString = process.env["TEST_DATABASE_URL"];
const redisUrl = process.env["TEST_REDIS_URL"] ?? "redis://localhost:6380";

const reading = {
  status: "transfer",
  transactionId: "E60701190202607241420abc",
  type: "pix",
  amount: 128.4,
  date: "2026-07-24",
  time: "14:20:00",
  destination: { name: "Mercado Bom Preço", institution: "Banco do Brasil", agency: "3054", account: "····8821" },
  origin: { name: "João Sena", institution: "Nubank", agency: "0001", account: "····1234" },
  category: "grocery",
  comment: "Sugerimos Mercearia pelo nome do destinatário.",
};

/** Answers with whatever the test scripted, and remembers what it was asked. */
function stubAi(answer: unknown): AiRunner & { requests: AiRequest[] } {
  const requests: AiRequest[] = [];
  return {
    requests,
    model: "stub",
    async run(request: AiRequest): Promise<AiResponse> {
      requests.push(request);
      return {
        text: typeof answer === "string" ? answer : JSON.stringify(answer),
        usage: { inputTokens: 0, outputTokens: 0, costUsd: undefined },
        transport: "api",
      };
    },
    parse(text, schema) {
      return schema.parse(JSON.parse(text));
    },
  };
}

describe.skipIf(!connectionString)("TransferService", () => {
  const db: LedgerDb = makeDb(connectionString ?? "");
  const cache = createCacheClient(redisUrl);
  const purchase = new PurchaseService({ db });

  /** `answer` is the union the model picks; the wire shape nests it under `result`. */
  function makeService(answer: unknown) {
    const ai = stubAi({ result: answer });
    return { ai, service: new TransferService({ db, cache, ai, purchase, prompt: "read it" }) };
  }

  afterAll(async () => {
    await db.destroy();
    cache.disconnect();
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
    await sql`truncate transfers, payments, purchase_items, purchases, stores restart identity cascade`.execute(db);
  });

  async function insertPurchase(overrides: {
    slug: string;
    time: string;
    paidTotal?: number;
    source?: "nfce" | "pix";
    date?: string;
  }) {
    const store = await db
      .insertInto("stores")
      .values({ name: "Mercado Bom Preço" })
      .returning("id")
      .executeTakeFirstOrThrow();
    return await db
      .insertInto("purchases")
      .values({
        slug: overrides.slug,
        date: overrides.date ?? "2026-07-24",
        time: overrides.time,
        source: overrides.source ?? "nfce",
        storeId: store.id,
        grossTotal: overrides.paidTotal ?? 128.4,
        paidTotal: overrides.paidTotal ?? 128.4,
        itemCount: 12,
      })
      .returning("id")
      .executeTakeFirstOrThrow();
  }

  test("pasted text alone is enough, and the text reaches the prompt", async () => {
    const { ai, service } = makeService(reading);
    const result = await service.interpret({ text: "Comprovante de Pix\nValor: R$ 128,40" });

    expect(result.transfer.transactionId).toBe(reading.transactionId);
    expect(result.transfer.amount).toBe(128.4);
    expect(result.category).toBe("grocery");
    expect(result.match).toBeNull();
    expect(ai.requests[0]?.instructions).toContain("Valor: R$ 128,40");
    expect(ai.requests[0]?.image).toBeUndefined();
  });

  test("neither a print nor text is a bad request, not an AI call", async () => {
    const { ai, service } = makeService(reading);
    try {
      await service.interpret({});
      throw new Error("expected a rejection");
    } catch (error) {
      expect((error as LedgerError).errorCode).toBe("invalid_input");
      expect((error as LedgerError).statusCode).toBe(400);
    }
    expect(ai.requests).toHaveLength(0);
  });

  test("a receipt for something else comes back as not_a_transfer", async () => {
    const { service } = makeService({ status: "not_a_transfer", comment: "Isso é uma fatura de cartão." });
    try {
      await service.interpret({ text: "fatura" });
      throw new Error("expected a rejection");
    } catch (error) {
      expect((error as LedgerError).errorCode).toBe("not_a_transfer");
      expect((error as LedgerError).statusCode).toBe(422);
      expect((error as LedgerError).message).toBe("Isso é uma fatura de cartão.");
    }
  });

  // Money has two decimal places; the model does not always agree.
  test("an over-precise amount is rounded to cents", async () => {
    const { service } = makeService({ ...reading, amount: 128.40000000000001 });
    const result = await service.interpret({ text: "pix" });
    expect(result.transfer.amount).toBe(128.4);
  });

  test("finds the note from the same day for the same total", async () => {
    await insertPurchase({ slug: "2026-07-24_bom_preco_01", time: "14:18:22" });
    const { service } = makeService(reading);

    const result = await service.interpret({ text: "pix" });
    expect(result.match).toMatchObject({
      purchaseId: "2026-07-24_bom_preco_01",
      store: "Mercado Bom Preço",
      totalPaid: 128.4,
      itemCount: 12,
    });
  });

  test("a different day or a different total is not a match", async () => {
    await insertPurchase({ slug: "2026-07-23_bom_preco_01", time: "14:18:22", date: "2026-07-23" });
    await insertPurchase({ slug: "2026-07-24_bom_preco_01", time: "14:18:22", paidTotal: 99.9 });
    const { service } = makeService(reading);

    expect((await service.interpret({ text: "pix" })).match).toBeNull();
  });

  // A transfer never pays for another transfer's purchase.
  test("purchases materialized from a transfer are not offered as matches", async () => {
    await insertPurchase({ slug: "2026-07-24_bom_preco_01", time: "14:18:22", source: "pix" });
    const { service } = makeService(reading);

    expect((await service.interpret({ text: "pix" })).match).toBeNull();
  });

  test("a note another transfer already claims is not offered again", async () => {
    const claimed = await insertPurchase({ slug: "2026-07-24_bom_preco_01", time: "14:18:22" });
    await db
      .insertInto("transfers")
      .values({
        transactionId: "E-someone-else",
        transferType: "pix",
        amount: 128.4,
        date: "2026-07-24",
        destinationName: "Mercado Bom Preço",
        purchaseId: claimed.id,
      })
      .execute();
    const { service } = makeService(reading);

    expect((await service.interpret({ text: "pix" })).match).toBeNull();
  });

  test("saving reads the purchase back the way the app will see it", async () => {
    const { service } = makeService(reading);
    const scanned = await service.interpret({ text: "pix" });

    const saved = await service.save({ transfer: scanned.transfer, category: "grocery", linkedPurchaseId: null });

    expect(saved.transfer.purchaseId).toBe(saved.purchase.id);
    expect(saved.purchase).toMatchObject({
      source: "pix",
      date: "2026-07-24",
      time: "14:20:00",
      receipt: null,
      store: { name: "Mercado Bom Preço" },
      totals: { itemCount: 1, gross: 128.4, discount: 0, totalPaid: 128.4 },
    });
    expect(saved.purchase.items).toHaveLength(1);
    expect(saved.purchase.items[0]).toMatchObject({
      description: "Mercado Bom Preço",
      category: "grocery",
      total: 128.4,
    });
    expect(saved.purchase.payments[0]).toMatchObject({ method: "Pix", amount: 128.4 });
  });

  test("saving a linked transfer returns the note it was linked to", async () => {
    await insertPurchase({ slug: "2026-07-24_bom_preco_01", time: "14:18:22" });
    const { service } = makeService(reading);
    const scanned = await service.interpret({ text: "pix" });

    const saved = await service.save({
      transfer: scanned.transfer,
      category: "grocery",
      linkedPurchaseId: "2026-07-24_bom_preco_01",
    });

    expect(saved.purchase.id).toBe("2026-07-24_bom_preco_01");
    expect(saved.purchase.source).toBe("nfce");
    expect(await db.selectFrom("purchases").selectAll().execute()).toHaveLength(1);
  });
});
