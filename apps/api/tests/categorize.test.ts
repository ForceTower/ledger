import { promises as fs } from "node:fs";
import path from "node:path";
import { categorize, type ParsedItem } from "@ledger/nfce";
import type { Category } from "@ledger/shared-types";
import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { FileMigrationProvider, Migrator, sql } from "kysely";
import { type LedgerDb, makeDb } from "../src/db";
import type { AiRequest, AiResponse, AiRunner } from "../src/service/ai";
import { CategorizerService } from "../src/service/categorize";

// Opt-in, same as transfer-service.test.ts:
//   docker compose -f infra/docker/docker-compose.yml up -d postgres
//   TEST_DATABASE_URL=postgres://ledger:ledger@localhost:5433/ledger_test bun test
const connectionString = process.env["TEST_DATABASE_URL"];

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

/** A receipt line as it reaches the resolver: rules already applied, no barcode unless asked for. */
function item(description: string, barcode: string | null = null): ParsedItem {
  return {
    seq: 1,
    description,
    code: "",
    barcode,
    quantity: 1,
    unit: "UN",
    unitPrice: 1,
    total: 1,
    category: categorize(description),
  };
}

describe("CategorizerService without a database", () => {
  // Only rememberedByBarcode touches the db, and it returns early when no item carries a barcode.
  const db: LedgerDb = makeDb("");

  test("leaves what the rules already placed alone, and never asks the model about it", async () => {
    const ai = stubAi({ items: [] });
    const service = new CategorizerService({ db, ai, prompt: "sort them" });

    const resolved = await service.resolve([item("BACON FATIADO SEARA"), item("ARROZ BCO POP T1 1kg")]);

    expect(resolved.map((each) => each.category)).toEqual(["meat", "grocery"]);
    expect(ai.requests).toHaveLength(0);
  });

  test("asks the model only about the lines the rules could not place", async () => {
    const ai = stubAi({ items: [{ index: 0, category: "hygiene" }] });
    const service = new CategorizerService({ db, ai, prompt: "sort them" });

    const resolved = await service.resolve([item("BACON FATIADO SEARA"), item("T SCALA MEGA C/3R")]);

    expect(resolved.map((each) => each.category)).toEqual(["meat", "hygiene"]);
    expect(ai.requests).toHaveLength(1);
    expect(ai.requests[0]?.instructions).toContain("T SCALA MEGA C/3R");
    expect(ai.requests[0]?.instructions).not.toContain("BACON");
  });

  test("keeps the rules' answer when no model is configured", async () => {
    const service = new CategorizerService({ db, prompt: "sort them" });

    const resolved = await service.resolve([item("T SCALA MEGA C/3R")]);

    expect(resolved[0]?.category).toBe("other");
  });

  test("keeps the rules' answer when the model fails", async () => {
    const ai = stubAi("not json at all");
    const service = new CategorizerService({ db, ai, prompt: "sort them" });

    const resolved = await service.resolve([item("T SCALA MEGA C/3R")]);

    expect(resolved[0]?.category).toBe("other");
  });

  test("ignores an answer whose index matches no item", async () => {
    const ai = stubAi({ items: [{ index: 7, category: "hygiene" }] });
    const service = new CategorizerService({ db, ai, prompt: "sort them" });

    const resolved = await service.resolve([item("T SCALA MEGA C/3R")]);

    expect(resolved[0]?.category).toBe("other");
  });
});

describe.skipIf(!connectionString)("CategorizerService barcode memory", () => {
  const db: LedgerDb = makeDb(connectionString ?? "");

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
    await sql`truncate products, payments, purchase_items, purchases, stores restart identity cascade`.execute(db);
  });

  async function rememberProduct(barcode: string, defaultCategory: Category): Promise<void> {
    await db.insertInto("products").values({ barcode, canonicalDescription: null, defaultCategory }).execute();
  }

  test("reuses what the barcode was filed under before, without asking the model", async () => {
    await rememberProduct("7891000101506", "dairy_deli");
    const ai = stubAi({ items: [] });
    const service = new CategorizerService({ db, ai, prompt: "sort them" });

    const resolved = await service.resolve([item("T SCALA MEGA C/3R", "7891000101506")]);

    expect(resolved[0]?.category).toBe("dairy_deli");
    expect(ai.requests).toHaveLength(0);
  });

  test("a barcode remembered as other is no memory, so the model still gets asked", async () => {
    await rememberProduct("7891000101506", "other");
    const ai = stubAi({ items: [{ index: 0, category: "hygiene" }] });
    const service = new CategorizerService({ db, ai, prompt: "sort them" });

    const resolved = await service.resolve([item("T SCALA MEGA C/3R", "7891000101506")]);

    expect(resolved[0]?.category).toBe("hygiene");
    expect(ai.requests).toHaveLength(1);
  });
});
