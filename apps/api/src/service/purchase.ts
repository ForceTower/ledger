import type { PricePoint, Purchase, PurchasePage } from "@ledger/shared-types";
import { type InferResult, sql } from "kysely";
import { jsonArrayFrom } from "kysely/helpers/postgres";
import type { LedgerDb } from "../db";

// The history feed exists so the app can mirror the whole dataset into its local store; full
// purchases are heavy, so the page is deliberately small.
const PAGE_SIZE = 5;

export interface PurchaseFilters {
  page?: number;
  from?: string;
  to?: string;
  store?: string;
}

export class PurchaseService {
  constructor(private readonly deps: { db: LedgerDb }) {}

  async list(filters: PurchaseFilters): Promise<PurchasePage> {
    const page = filters.page ?? 1;

    const { total } = await filteredPurchases(this.deps.db, filters)
      .select((eb) => eb.fn.countAll<number>().as("total"))
      .executeTakeFirstOrThrow();

    const rows = await fullSelect(filteredPurchases(this.deps.db, filters))
      .orderBy("purchases.date", "desc")
      .orderBy(sql`purchases.time desc nulls last`)
      .orderBy("purchases.slug", "desc")
      .limit(PAGE_SIZE)
      .offset((page - 1) * PAGE_SIZE)
      .execute();

    return {
      items: rows.map(toPurchase),
      page,
      pageSize: PAGE_SIZE,
      total,
      hasMore: page * PAGE_SIZE < total,
    };
  }

  async get(id: string): Promise<Purchase | null> {
    const row = await fullSelect(filteredPurchases(this.deps.db, {}))
      .where("purchases.slug", "=", id)
      .executeTakeFirst();
    return row ? toPurchase(row) : null;
  }

  async prices(barcode: string): Promise<PricePoint[]> {
    // TODO: select date, store name, unit_price, purchase slug from purchase_items where barcode matches.
    return MOCK_PRICES.filter((p) => p.purchaseId.length > 0 && barcode.length > 0);
  }
}

function filteredPurchases(db: LedgerDb, filters: PurchaseFilters) {
  let query = db.selectFrom("purchases").leftJoin("stores", "stores.id", "purchases.storeId");
  if (filters.from) query = query.where("purchases.date", ">=", filters.from);
  if (filters.to) query = query.where("purchases.date", "<=", filters.to);
  if (filters.store) query = query.where("stores.name", "=", filters.store);
  return query;
}

function fullSelect(base: ReturnType<typeof filteredPurchases>) {
  return base.select((eb) => [
    "purchases.slug",
    "purchases.date",
    "purchases.time",
    "purchases.source",
    "purchases.accessKey",
    "purchases.receiptNumber",
    "purchases.receiptSeries",
    "purchases.grossTotal",
    "purchases.discountTotal",
    "purchases.paidTotal",
    "purchases.itemCount",
    "purchases.taxesTotal",
    "stores.name as storeName",
    "stores.legalName as storeLegalName",
    "stores.cnpj as storeCnpj",
    "stores.address as storeAddress",
    jsonArrayFrom(
      eb
        .selectFrom("purchaseItems")
        .select([
          "purchaseItems.seq",
          "purchaseItems.description",
          "purchaseItems.code",
          "purchaseItems.barcode",
          "purchaseItems.quantity",
          "purchaseItems.unit",
          "purchaseItems.unitPrice",
          "purchaseItems.total",
          "purchaseItems.category",
        ])
        .whereRef("purchaseItems.purchaseId", "=", "purchases.id")
        .orderBy("purchaseItems.seq"),
    ).as("items"),
    jsonArrayFrom(
      eb
        .selectFrom("payments")
        .select(["payments.code", "payments.method", "payments.amount", "payments.change"])
        .whereRef("payments.purchaseId", "=", "purchases.id")
        .orderBy("payments.amount", "desc"),
    ).as("payments"),
  ]);
}

type PurchaseRow = InferResult<ReturnType<typeof fullSelect>>[number];

function toPurchase(row: PurchaseRow): Purchase {
  return {
    id: row.slug,
    date: row.date,
    time: row.time ?? "",
    source: row.source,
    store: {
      name: row.storeName ?? "",
      legalName: row.storeLegalName,
      cnpj: row.storeCnpj,
      address: row.storeAddress,
    },
    receipt: row.accessKey ? { number: row.receiptNumber, series: row.receiptSeries, accessKey: row.accessKey } : null,
    items: row.items.map((item) => ({ ...item, code: item.code ?? "", unit: item.unit ?? "" })),
    totals: {
      itemCount: row.itemCount,
      gross: row.grossTotal,
      discount: row.discountTotal,
      totalPaid: row.paidTotal,
    },
    payments: row.payments.map((payment) => ({
      code: payment.code,
      method: payment.method,
      amount: payment.amount,
      change: payment.change ?? undefined,
    })),
    taxesTotal: row.taxesTotal,
  };
}

const MOCK_PRICES: PricePoint[] = [
  { date: "2026-03-26", store: "Atacadão", unitPrice: 23.9, purchaseId: "2026-03-26_atacadao_01" },
];
