import { promises as fs } from "node:fs";
import path from "node:path";
import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import type { TransferSaveRequest } from "@ledger/shared-types";
import { FileMigrationProvider, Migrator, sql } from "kysely";
import { type LedgerDb, makeDb } from "../src/db";
import { saveTransfer } from "../src/service/ingest";

// Needs a throwaway Postgres, so it stays opt-in:
//   docker compose -f infra/docker/docker-compose.yml up -d postgres
//   TEST_DATABASE_URL=postgres://ledger:ledger@localhost:5433/ledger_test bun test
const connectionString = process.env["TEST_DATABASE_URL"];

const transfer: TransferSaveRequest["transfer"] = {
  transactionId: "E60701190202607241420abc",
  type: "pix",
  amount: 128.4,
  date: "2026-07-24",
  time: "14:20:00",
  destination: { name: "Mercado Bom Preço", institution: "Banco do Brasil", agency: "3054", account: "····8821" },
  origin: { name: "João Sena", institution: "Nubank", agency: "0001", account: "····1234" },
  purchaseId: null,
};

const request: TransferSaveRequest = { transfer, category: "grocery", linkedPurchaseId: null };

describe.skipIf(!connectionString)("saveTransfer", () => {
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
        "purchases.paidTotal",
        "purchases.itemCount",
        "purchases.date",
        "stores.name as storeName",
      ])
      .where("purchases.slug", "=", slug)
      .executeTakeFirstOrThrow();
  }

  test("an unlinked transfer materializes its own pix purchase", async () => {
    const saved = await saveTransfer(db, request);

    expect(saved.status).toBe("saved");
    expect(saved.slug).toBe("2026-07-24_mercado_bom_preco_01");

    const purchase = await purchaseOf(saved.slug);
    expect(purchase).toMatchObject({
      source: "pix",
      paidTotal: 128.4,
      itemCount: 1,
      date: "2026-07-24",
      storeName: "Mercado Bom Preço",
    });

    const items = await db.selectFrom("purchaseItems").selectAll().where("purchaseId", "=", purchase.id).execute();
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({
      description: "Mercado Bom Preço",
      category: "grocery",
      quantity: 1,
      total: 128.4,
      code: transfer.transactionId,
    });

    const payments = await db.selectFrom("payments").selectAll().where("purchaseId", "=", purchase.id).execute();
    expect(payments).toHaveLength(1);
    expect(payments[0]).toMatchObject({ method: "Pix", amount: 128.4 });

    const row = await db.selectFrom("transfers").selectAll().executeTakeFirstOrThrow();
    expect(row).toMatchObject({
      transactionId: transfer.transactionId,
      transferType: "pix",
      amount: 128.4,
      destinationName: "Mercado Bom Preço",
      destinationAccount: "····8821",
      originName: "João Sena",
      purchaseId: purchase.id,
    });
  });

  test("the owner's category is what the line item gets", async () => {
    const saved = await saveTransfer(db, { ...request, category: "bakery" });
    const purchase = await purchaseOf(saved.slug);
    const item = await db
      .selectFrom("purchaseItems")
      .selectAll()
      .where("purchaseId", "=", purchase.id)
      .executeTakeFirstOrThrow();
    expect(item.category).toBe("bakery");
  });

  // The whole point of linking: the note already counts the money, so the transfer must not add more.
  test("a linked transfer attaches to the note and materializes nothing", async () => {
    const store = await db
      .insertInto("stores")
      .values({ name: "Mercado Bom Preço", cnpj: "12345678000190" })
      .returning("id")
      .executeTakeFirstOrThrow();
    await db
      .insertInto("purchases")
      .values({
        slug: "2026-07-24_mercado_bom_preco_01",
        date: "2026-07-24",
        time: "14:18:22",
        source: "nfce",
        storeId: store.id,
        accessKey: "5226071234567800019065001000012345678901234",
        grossTotal: 128.4,
        paidTotal: 128.4,
        itemCount: 12,
      })
      .execute();

    const saved = await saveTransfer(db, { ...request, linkedPurchaseId: "2026-07-24_mercado_bom_preco_01" });

    expect(saved.slug).toBe("2026-07-24_mercado_bom_preco_01");
    const purchases = await db.selectFrom("purchases").selectAll().execute();
    expect(purchases).toHaveLength(1);
    expect(purchases[0]?.source).toBe("nfce");

    const row = await db.selectFrom("transfers").selectAll().executeTakeFirstOrThrow();
    expect(row.purchaseId).toBe(purchases[0]?.id ?? "");
  });

  test("re-posting the same transaction id counts it once", async () => {
    const first = await saveTransfer(db, request);
    const second = await saveTransfer(db, request);

    expect(second).toEqual({ status: "duplicate", slug: first.slug });
    expect(await db.selectFrom("transfers").selectAll().execute()).toHaveLength(1);
    expect(await db.selectFrom("purchases").selectAll().execute()).toHaveLength(1);
  });

  // Two transfers to the same destination on the same day are two purchases, not a slug collision.
  test("a second transfer the same day gets the next slug", async () => {
    const first = await saveTransfer(db, request);
    const second = await saveTransfer(db, {
      ...request,
      transfer: { ...transfer, transactionId: "E60701190202607241900xyz", amount: 42.5, time: "19:00:00" },
    });

    expect(first.slug).toBe("2026-07-24_mercado_bom_preco_01");
    expect(second.slug).toBe("2026-07-24_mercado_bom_preco_02");
  });

  // The store row is shared with the NFC-e path, so a Pix to a known store must not fork it.
  test("an existing store with no CNPJ is reused rather than duplicated", async () => {
    await saveTransfer(db, request);
    await saveTransfer(db, {
      ...request,
      transfer: { ...transfer, transactionId: "E60701190202607251000def", date: "2026-07-25" },
    });

    const stores = await db.selectFrom("stores").selectAll().execute();
    expect(stores).toHaveLength(1);
  });
});
