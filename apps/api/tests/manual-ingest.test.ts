import { promises as fs } from "node:fs";
import path from "node:path";
import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import type { PurchaseCreateRequest } from "@ledger/shared-types";
import { FileMigrationProvider, Migrator, sql } from "kysely";
import { type LedgerDb, makeDb } from "../src/db";
import { saveManualPurchase } from "../src/service/ingest";

// Needs a throwaway Postgres, so it stays opt-in:
//   docker compose -f infra/docker/docker-compose.yml up -d postgres
//   TEST_DATABASE_URL=postgres://ledger:ledger@localhost:5433/ledger_test bun test
const connectionString = process.env["TEST_DATABASE_URL"];

const request: PurchaseCreateRequest = {
  date: "2026-07-24",
  time: null,
  store: "Transporte",
  paymentMethod: null,
  items: [{ description: "Transporte", category: "transport", quantity: 1, unitPrice: 37 }],
};

describe.skipIf(!connectionString)("saveManualPurchase", () => {
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
    await sql`truncate transfers, payments, purchase_items, purchases, stores restart identity cascade`.execute(db);
  });

  async function purchaseOf(slug: string) {
    return await db
      .selectFrom("purchases")
      .leftJoin("stores", "stores.id", "purchases.storeId")
      .select([
        "purchases.id",
        "purchases.source",
        "purchases.grossTotal",
        "purchases.paidTotal",
        "purchases.itemCount",
        "purchases.date",
        "purchases.accessKey",
        "stores.name as storeName",
      ])
      .where("purchases.slug", "=", slug)
      .executeTakeFirstOrThrow();
  }

  test("a typed entry becomes a manual purchase under the owner's store", async () => {
    const { slug } = await saveManualPurchase(db, request);
    expect(slug).toBe("2026-07-24_transporte_01");

    const purchase = await purchaseOf(slug);
    expect(purchase).toMatchObject({
      source: "manual",
      grossTotal: 37,
      paidTotal: 37,
      itemCount: 1,
      date: "2026-07-24",
      storeName: "Transporte",
      accessKey: null,
    });

    const items = await db.selectFrom("purchaseItems").selectAll().where("purchaseId", "=", purchase.id).execute();
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({
      seq: 1,
      description: "Transporte",
      category: "transport",
      quantity: 1,
      unit: "un",
      unitPrice: 37,
      total: 37,
    });

    // Nothing said how it was paid, so the purchase carries no payment row.
    expect(await db.selectFrom("payments").selectAll().execute()).toHaveLength(0);
  });

  test("several items are numbered in order and add up to the total", async () => {
    const { slug } = await saveManualPurchase(db, {
      ...request,
      store: "Feira",
      paymentMethod: "Pix",
      items: [
        { description: "Transporte", category: "transport", quantity: 1, unitPrice: 37 },
        { description: "Pão francês", category: "bakery", quantity: 3, unitPrice: 1.15 },
      ],
    });

    const purchase = await purchaseOf(slug);
    expect(purchase).toMatchObject({ itemCount: 2, paidTotal: 40.45 });

    const items = await db
      .selectFrom("purchaseItems")
      .selectAll()
      .where("purchaseId", "=", purchase.id)
      .orderBy("seq")
      .execute();
    expect(items.map((item) => [item.seq, item.total])).toEqual([
      [1, 37],
      [2, 3.45],
    ]);

    const payments = await db.selectFrom("payments").selectAll().execute();
    expect(payments[0]).toMatchObject({ method: "Pix", amount: 40.45 });
  });

  // No access key, no transaction id: only the owner knows whether two identical entries are one
  // purchase, so asking twice writes twice rather than silently swallowing the second.
  test("the same entry twice is two purchases with consecutive slugs", async () => {
    const first = await saveManualPurchase(db, request);
    const second = await saveManualPurchase(db, request);

    expect([first.slug, second.slug]).toEqual(["2026-07-24_transporte_01", "2026-07-24_transporte_02"]);
    expect(await db.selectFrom("stores").selectAll().execute()).toHaveLength(1);
  });

  // The store row is shared with the scan paths, so typing a known store must not fork it.
  test("an existing store is reused rather than duplicated", async () => {
    await db.insertInto("stores").values({ name: "Padaria do Zé" }).execute();
    await saveManualPurchase(db, { ...request, store: "Padaria do Zé" });

    expect(await db.selectFrom("stores").selectAll().execute()).toHaveLength(1);
  });
});
