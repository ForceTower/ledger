import type { ParsedItem, ParsedReceipt } from "@ledger/nfce";
import type { Category, ScanPurchase, ScanResult } from "@ledger/shared-types";
import type { Transaction } from "kysely";
import { jsonArrayFrom } from "kysely/helpers/postgres";
import type { LedgerDb } from "../db";
import type { Database } from "../db/schema";

type Trx = Transaction<Database>;

/**
 * Persist a parsed receipt: upsert the store (by CNPJ) and products (by barcode), then insert the
 * purchase with its items and payments in one transaction. The NFC-e access key is the dedup key —
 * rescanning a stored receipt returns its summary with status "duplicate".
 *
 * The slug sequence is read-then-insert, so callers must serialize invocations (the scan flow holds
 * a Redis lock); the unique constraints on slug/access_key backstop a lost lock.
 */
export async function saveParsedReceipt(
  db: LedgerDb,
  parsed: ParsedReceipt,
  opts: { sourceHtml: string },
): Promise<ScanResult> {
  return await db.transaction().execute(async (trx) => {
    const existing = await findByAccessKey(trx, parsed.receipt.accessKey);
    if (existing) return { status: "duplicate", purchase: existing, warnings: parsed.warnings };

    const store = await resolveStore(trx, parsed.store);
    const slug = await nextSlug(trx, parsed.date, slugifyStore(store.name));

    const purchase = await trx
      .insertInto("purchases")
      .values({
        slug,
        date: parsed.date,
        time: parsed.time || null,
        source: parsed.source,
        storeId: store.id,
        accessKey: parsed.receipt.accessKey,
        receiptNumber: parsed.receipt.number,
        receiptSeries: parsed.receipt.series,
        grossTotal: parsed.totals.gross,
        discountTotal: parsed.totals.discount,
        paidTotal: parsed.totals.totalPaid,
        itemCount: parsed.totals.itemCount,
        taxesTotal: parsed.taxesTotal,
        sourceHtml: opts.sourceHtml,
      })
      .returning("id")
      .executeTakeFirstOrThrow();

    const productIdByBarcode = await upsertProducts(trx, parsed.items);

    if (parsed.items.length > 0) {
      await trx
        .insertInto("purchaseItems")
        .values(
          parsed.items.map((item) => ({
            purchaseId: purchase.id,
            productId: item.barcode ? (productIdByBarcode.get(item.barcode) ?? null) : null,
            seq: item.seq,
            description: item.description,
            code: item.code || null,
            barcode: item.barcode,
            quantity: item.quantity,
            unit: item.unit || null,
            unitPrice: item.unitPrice,
            total: item.total,
            category: item.category,
          })),
        )
        .execute();
    }

    if (parsed.payments.length > 0) {
      await trx
        .insertInto("payments")
        .values(
          parsed.payments.map((payment) => ({
            purchaseId: purchase.id,
            code: payment.code,
            method: payment.method,
            amount: payment.amount,
            change: payment.change ?? null,
          })),
        )
        .execute();
    }

    return {
      status: "saved",
      purchase: {
        id: slug,
        store: store.name,
        date: parsed.date,
        time: parsed.time,
        totalPaid: parsed.totals.totalPaid,
        itemCount: parsed.totals.itemCount,
        ...itemsSummary(parsed.items),
      },
      warnings: parsed.warnings,
    };
  });
}

async function findByAccessKey(trx: Trx, accessKey: string): Promise<ScanPurchase | null> {
  const row = await trx
    .selectFrom("purchases")
    .leftJoin("stores", "stores.id", "purchases.storeId")
    .select((eb) => [
      "purchases.slug",
      "purchases.date",
      "purchases.time",
      "purchases.paidTotal",
      "purchases.itemCount",
      "stores.name as storeName",
      jsonArrayFrom(
        eb
          .selectFrom("purchaseItems")
          .select([
            "purchaseItems.description",
            "purchaseItems.quantity",
            "purchaseItems.total",
            "purchaseItems.category",
          ])
          .whereRef("purchaseItems.purchaseId", "=", "purchases.id")
          .orderBy("purchaseItems.seq"),
      ).as("items"),
    ])
    .where("purchases.accessKey", "=", accessKey)
    .executeTakeFirst();

  if (!row) return null;
  return {
    id: row.slug,
    store: row.storeName ?? "",
    date: row.date,
    time: row.time ?? "",
    totalPaid: row.paidTotal,
    itemCount: row.itemCount,
    ...itemsSummary(row.items),
  };
}

/**
 * The stores row is user-curated data — the owner renames stores at will — so a CNPJ match wins
 * and its name is never overwritten from a receipt. New stores are seeded with the printed
 * razão social until the owner renames them.
 */
async function resolveStore(trx: Trx, store: ParsedReceipt["store"]): Promise<{ id: string; name: string }> {
  const existing = await trx
    .selectFrom("stores")
    .select(["id", "name"])
    .where((eb) =>
      store.cnpj ? eb("cnpj", "=", store.cnpj) : eb.and([eb("cnpj", "is", null), eb("name", "=", store.name)]),
    )
    .executeTakeFirst();
  if (existing) return existing;

  return await trx
    .insertInto("stores")
    .values({ name: store.name, legalName: store.legalName, cnpj: store.cnpj, address: store.address })
    .returning(["id", "name"])
    .executeTakeFirstOrThrow();
}

async function upsertProducts(trx: Trx, items: ParsedItem[]): Promise<Map<string, string>> {
  const descriptionByBarcode = new Map<string, ParsedItem>();
  for (const item of items) {
    if (item.barcode && !descriptionByBarcode.has(item.barcode)) descriptionByBarcode.set(item.barcode, item);
  }
  if (descriptionByBarcode.size === 0) return new Map();

  await trx
    .insertInto("products")
    .values(
      [...descriptionByBarcode.entries()].map(([barcode, item]) => ({
        barcode,
        canonicalDescription: item.description,
        defaultCategory: item.category,
      })),
    )
    .onConflict((oc) => oc.column("barcode").doNothing())
    .execute();

  const rows = await trx
    .selectFrom("products")
    .select(["id", "barcode"])
    .where("barcode", "in", [...descriptionByBarcode.keys()])
    .execute();
  return new Map(rows.map((row) => [row.barcode, row.id]));
}

/** Next free slug for the day at this store: "2026-03-26_atacadao_01", "…_02", … */
async function nextSlug(trx: Trx, date: string, storeSlug: string): Promise<string> {
  const prefix = `${date}_${storeSlug}_`;
  const escapedPrefix = prefix.replace(/[\\%_]/g, (ch) => `\\${ch}`);
  const rows = await trx.selectFrom("purchases").select("slug").where("slug", "like", `${escapedPrefix}%`).execute();

  let max = 0;
  for (const { slug } of rows) {
    const seq = Number(slug.slice(prefix.length));
    if (Number.isInteger(seq) && seq > max) max = seq;
  }
  return `${prefix}${String(max + 1).padStart(2, "0")}`;
}

function slugifyStore(name: string): string {
  const slug = name
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return slug || "store";
}

interface SummaryItem {
  description: string;
  quantity: number;
  total: number;
  category: Category;
}

// The contract leaves the preview size open; the app shows a snippet, so send the 3 biggest items.
const PREVIEW_COUNT = 3;

function itemsSummary(items: SummaryItem[]): Pick<ScanPurchase, "categories" | "itemsPreview"> {
  const categories: Partial<Record<Category, number>> = {};
  for (const item of items) {
    categories[item.category] = (categories[item.category] ?? 0) + 1;
  }
  const itemsPreview = [...items]
    .sort((a, b) => b.total - a.total)
    .slice(0, PREVIEW_COUNT)
    .map(({ description, quantity, total }) => ({ description, quantity, total }));
  return { categories, itemsPreview };
}
