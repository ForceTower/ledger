import type { Generated } from "kysely";

// Hand-written to match migration 001. Once the DB is up, prefer regenerating this file from the live
// schema: `bun run db:codegen`. Property names are camelCase (the CamelCasePlugin maps them to the
// snake_case columns).

export type Category =
  | "produce"
  | "meat"
  | "dairy_deli"
  | "bakery"
  | "grocery"
  | "beverages"
  | "snacks_sweets"
  | "frozen"
  | "cleaning"
  | "hygiene"
  | "pet"
  | "household"
  | "other";

export type PurchaseSource = "nfce" | "manual";

export interface StoresTable {
  id: Generated<string>;
  name: string;
  legalName: string | null;
  cnpj: string | null;
  address: string | null;
  createdAt: Generated<Date>;
}

export interface PurchasesTable {
  id: Generated<string>;
  slug: string;
  date: string;
  time: string | null;
  source: PurchaseSource;
  storeId: string | null;
  accessKey: string | null;
  receiptNumber: number | null;
  receiptSeries: number | null;
  grossTotal: number;
  discountTotal: Generated<number>;
  paidTotal: number;
  itemCount: number;
  taxesTotal: number | null;
  sourceHtml: string | null;
  createdAt: Generated<Date>;
}

export interface ProductsTable {
  id: Generated<string>;
  barcode: string;
  canonicalDescription: string | null;
  defaultCategory: Category | null;
  createdAt: Generated<Date>;
}

export interface PurchaseItemsTable {
  id: Generated<string>;
  purchaseId: string;
  productId: string | null;
  seq: number;
  description: string;
  code: string | null;
  barcode: string | null;
  quantity: number;
  unit: string | null;
  unitPrice: number;
  total: number;
  category: Category;
}

export interface PaymentsTable {
  id: Generated<string>;
  purchaseId: string;
  code: number | null;
  method: string;
  amount: number;
  change: number | null;
}

export interface TripsTable {
  id: Generated<string>;
  date: string;
  legs: unknown;
  createdAt: Generated<Date>;
}

export interface DonationsTable {
  id: Generated<string>;
  date: string;
  sourcePurchaseSlug: string | null;
  entries: unknown;
  total: number | null;
  createdAt: Generated<Date>;
}

export type ScanRequestStatus = "saved" | "duplicate" | "failed";

/** Audit trail of every `POST /scan`: the raw QR URL and how processing it went. */
export interface ScanRequestsTable {
  id: Generated<string>;
  url: string;
  status: ScanRequestStatus;
  errorCode: string | null;
  errorMessage: string | null;
  purchaseSlug: string | null;
  warnings: unknown;
  durationMs: number;
  createdAt: Generated<Date>;
}

export interface DeviceTokensTable {
  id: Generated<string>;
  token: string;
  platform: string;
  createdAt: Generated<Date>;
  lastSeenAt: Generated<Date>;
}

export interface Database {
  stores: StoresTable;
  purchases: PurchasesTable;
  products: ProductsTable;
  purchaseItems: PurchaseItemsTable;
  payments: PaymentsTable;
  trips: TripsTable;
  donations: DonationsTable;
  scanRequests: ScanRequestsTable;
  deviceTokens: DeviceTokensTable;
}
