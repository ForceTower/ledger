// The wire contract shared by the API and every client. Mirrored in Swift by the iOS app.
// See docs/api-contract.md for the prose version. All fields are English.

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

export type PurchaseSource = "nfce" | "manual" | "pix";

export interface ApiResponse<T> {
  ok: boolean;
  message: string;
  data: T | null;
  error: unknown;
  errorCode?: string | null;
}

export type ScanErrorCode = "invalid_url" | "expired" | "unavailable" | "parse_failed";

export interface PurchaseSummary {
  id: string;
  store: string;
  date: string;
  time: string;
  totalPaid: number;
  itemCount: number;
  categories: Partial<Record<Category, number>>;
}

export interface ScanResult {
  status: "saved" | "duplicate";
  /** The full purchase (same shape as `GET /purchases/:id`), so clients can render and mirror it. */
  purchase: Purchase;
  warnings: string[];
}

export interface PurchaseItem {
  seq: number;
  description: string;
  code: string;
  barcode: string | null;
  quantity: number;
  unit: string;
  unitPrice: number;
  total: number;
  category: Category;
}

export interface Purchase {
  id: string;
  date: string;
  time: string;
  source: PurchaseSource;
  store: { name: string; legalName: string | null; cnpj: string | null; address: string | null };
  receipt: { number: number | null; series: number | null; accessKey: string } | null;
  items: PurchaseItem[];
  totals: { itemCount: number; gross: number; discount: number; totalPaid: number };
  payments: { code: number | null; method: string; amount: number; change?: number }[];
  taxesTotal: number | null;
}

export interface PurchasePage {
  items: Purchase[];
  /** 1-based. */
  page: number;
  pageSize: number;
  /** Purchases matching the filters, across all pages. */
  total: number;
  hasMore: boolean;
}

export interface PricePoint {
  date: string;
  store: string;
  unitPrice: number;
  purchaseId: string;
}

export type TransferType = "pix";

export interface TransferParty {
  name: string;
  institution: string | null;
  agency: string | null;
  account: string | null;
}

/** A bank-transfer receipt (Pix comprovante) extracted by AI from a screenshot/photo. */
export interface Transfer {
  /** The bank's end-to-end transaction ID (e.g. "E1823…"). Dedup key. */
  transactionId: string;
  type: TransferType;
  amount: number;
  date: string;
  time: string | null;
  destination: TransferParty;
  origin: TransferParty | null;
  /** Slug of the purchase this transfer materialized into; null if detached. */
  purchaseId: string | null;
}

export type PhotoScanErrorCode = "invalid_image" | "ai_unavailable" | "ai_invalid_output";

export type PhotoScanRejectionReason =
  | "no_item"
  | "unclear_image"
  | "multiple_items"
  | "inappropriate";

export interface PhotoScanItem {
  /** Item name as it would appear on a receipt line (pt-BR). */
  description: string;
  category: Category;
  /** Model self-assessment, 0..1. */
  confidence: number;
}

export interface PhotoScanIdentified {
  status: "identified";
  item: PhotoScanItem;
  /** Free-form remark the AI wants to surface about the item (pt-BR). */
  comment: string;
}

export interface PhotoScanRejected {
  status: "rejected";
  reason: PhotoScanRejectionReason;
  /** Why the item could not be identified (pt-BR). */
  comment: string;
}

export type PhotoScanResult = PhotoScanIdentified | PhotoScanRejected;
