import type { ParsedItem, ParsedReceipt } from "@ledger/nfce";
import type { TransferSaveRequest } from "@ledger/shared-types";
import type { Transaction } from "kysely";
import type { LedgerDb } from "../db";
import type { Database } from "../db";

type Trx = Transaction<Database>;

/**
 * The slug sequence is read-then-insert, so every writer that mints one has to be serialized
 * against the others. Scans and transfers share the lock because they share the sequence.
 */
export const WRITE_LOCK = "scan:write-lock";

export interface IngestResult {
  status: "saved" | "duplicate";
  slug: string;
  warnings: string[];
}

/**
 * Persist a parsed receipt: upsert the store (by CNPJ) and products (by barcode), then insert the
 * purchase with its items and payments in one transaction. The NFC-e access key is the dedup key —
 * rescanning a stored receipt returns its slug with status "duplicate".
 *
 * The slug sequence is read-then-insert, so callers must serialize invocations (the scan flow holds
 * a Redis lock); the unique constraints on slug/access_key backstop a lost lock.
 */
export async function saveParsedReceipt(
  db: LedgerDb,
  parsed: ParsedReceipt,
  opts: { sourceHtml: string },
): Promise<IngestResult> {
  return await db.transaction().execute(async (trx) => {
    const existing = await findSlugByAccessKey(trx, parsed.receipt.accessKey);
    if (existing) return { status: "duplicate", slug: existing, warnings: parsed.warnings };

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

    return { status: "saved", slug, warnings: parsed.warnings };
  });
}

export interface TransferIngestResult {
  status: "saved" | "duplicate";
  /** Slug of the purchase the transfer is attached to — the linked note, or the one just created. */
  slug: string;
}

/**
 * Persist a reviewed transfer. The bank's transaction ID is the dedup key, so re-posting the same
 * receipt returns what is already stored rather than counting it twice.
 *
 * An unlinked transfer materializes its own single-item purchase (`source: "pix"`) so it shows up
 * in the history feed. A linked one attaches to the note it paid for and materializes nothing —
 * that note already accounts for the money.
 *
 * Callers must hold {@link WRITE_LOCK}: the unlinked path mints a slug.
 */
export async function saveTransfer(db: LedgerDb, request: TransferSaveRequest): Promise<TransferIngestResult> {
  const { transfer, category, linkedPurchaseId } = request;

  return await db.transaction().execute(async (trx) => {
    const existing = await trx
      .selectFrom("transfers")
      .leftJoin("purchases", "purchases.id", "transfers.purchaseId")
      .select(["transfers.id as transferId", "purchases.slug"])
      .where("transfers.transactionId", "=", transfer.transactionId)
      .executeTakeFirst();
    if (existing?.slug) return { status: "duplicate", slug: existing.slug };

    const linked = linkedPurchaseId
      ? await trx.selectFrom("purchases").select(["id", "slug"]).where("slug", "=", linkedPurchaseId).executeTakeFirst()
      : undefined;

    const purchase = linked ?? (await materializeTransferPurchase(trx, transfer, category));

    // The transfer outlived the purchase it pointed at (a deleted note nulls the FK). Re-attach it
    // instead of inserting into the unique transaction_id again.
    if (existing) {
      await trx
        .updateTable("transfers")
        .set({ purchaseId: purchase.id })
        .where("id", "=", existing.transferId)
        .execute();
      return { status: "saved", slug: purchase.slug };
    }

    await trx
      .insertInto("transfers")
      .values({
        transactionId: transfer.transactionId,
        transferType: transfer.type,
        amount: transfer.amount,
        date: transfer.date,
        time: transfer.time,
        destinationName: transfer.destination.name,
        destinationInstitution: transfer.destination.institution,
        destinationAgency: transfer.destination.agency,
        destinationAccount: transfer.destination.account,
        originName: transfer.origin?.name ?? null,
        originInstitution: transfer.origin?.institution ?? null,
        purchaseId: purchase.id,
        extracted: JSON.stringify(request),
      })
      .execute();

    return { status: "saved", slug: purchase.slug };
  });
}

async function materializeTransferPurchase(
  trx: Trx,
  transfer: TransferSaveRequest["transfer"],
  category: TransferSaveRequest["category"],
): Promise<{ id: string; slug: string }> {
  const store = await resolveStore(trx, {
    name: transfer.destination.name,
    legalName: null,
    cnpj: null,
    address: null,
  });
  const slug = await nextSlug(trx, transfer.date, slugifyStore(store.name));

  const purchase = await trx
    .insertInto("purchases")
    .values({
      slug,
      date: transfer.date,
      time: transfer.time,
      source: "pix",
      storeId: store.id,
      grossTotal: transfer.amount,
      paidTotal: transfer.amount,
      itemCount: 1,
    })
    .returning("id")
    .executeTakeFirstOrThrow();

  // A transfer buys one unnamed thing: the destination is all the receipt says about it.
  await trx
    .insertInto("purchaseItems")
    .values({
      purchaseId: purchase.id,
      seq: 1,
      description: transfer.destination.name,
      code: transfer.transactionId,
      quantity: 1,
      unit: "un",
      unitPrice: transfer.amount,
      total: transfer.amount,
      category,
    })
    .execute();

  await trx
    .insertInto("payments")
    .values({
      purchaseId: purchase.id,
      method: transfer.type === "pix" ? "Pix" : transfer.type,
      amount: transfer.amount,
    })
    .execute();

  return { id: purchase.id, slug };
}

async function findSlugByAccessKey(trx: Trx, accessKey: string): Promise<string | null> {
  const row = await trx.selectFrom("purchases").select("slug").where("accessKey", "=", accessKey).executeTakeFirst();
  return row?.slug ?? null;
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

  // A known product keeps the description it was first filed under, but an unplaced one is allowed
  // to learn: once anything can categorize this barcode, that answer becomes its memory.
  await trx
    .insertInto("products")
    .values(
      [...descriptionByBarcode.entries()].map(([barcode, item]) => ({
        barcode,
        canonicalDescription: item.description,
        defaultCategory: item.category,
      })),
    )
    .onConflict((oc) =>
      oc
        .column("barcode")
        .doUpdateSet({ defaultCategory: (eb) => eb.ref("excluded.defaultCategory") })
        .where((eb) =>
          eb.and([
            eb.or([eb("products.defaultCategory", "is", null), eb("products.defaultCategory", "=", "other")]),
            eb("excluded.defaultCategory", "!=", "other"),
          ]),
        ),
    )
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
