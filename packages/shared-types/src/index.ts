// The wire contract shared by the API and every client. Mirrored in Swift by the iOS app.
// See docs/api-contract.md for the prose version. All fields are English.

/** The runtime list is the source of truth: the AI prompts enumerate it and `Category` derives from it. */
export const CATEGORIES = [
  "produce",
  "meat",
  "dairy_deli",
  "bakery",
  "grocery",
  "beverages",
  "snacks_sweets",
  "frozen",
  "cleaning",
  "hygiene",
  "pet",
  "household",
  "other",
] as const;

export type Category = (typeof CATEGORIES)[number];

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

export type TransferScanErrorCode =
  | "invalid_input"
  | "not_a_transfer"
  | "ai_unavailable"
  | "ai_invalid_output";

/** A purchase the transfer probably paid for: same day, same total. */
export interface TransferMatch {
  purchaseId: string;
  store: string;
  date: string;
  time: string;
  totalPaid: number;
  itemCount: number;
}

/** What `POST /scan/transfer` reads out of a receipt. Reading is not saving — nothing is persisted yet. */
export interface TransferScanResult {
  transfer: Transfer;
  /** The AI's category guess for the transfer as a whole, from the destination's name. */
  category: Category;
  /** A purchase on the same day whose total matches — the transfer probably paid for it. */
  match: TransferMatch | null;
  /** Free-form remark about the extraction (pt-BR). */
  comment: string;
}

/** What `POST /transfers` persists, once the owner has confirmed the category and the match. */
export interface TransferSaveRequest {
  transfer: Transfer;
  category: Category;
  /** The purchase this transfer paid for; keeps the two from being counted twice. */
  linkedPurchaseId: string | null;
}

export interface TransferSaveResult {
  transfer: Transfer;
  /** The purchase the transfer materialized into (`source: "pix"`), so clients can mirror it. */
  purchase: Purchase;
}

export type PhotoScanErrorCode = "invalid_image" | "ai_unavailable" | "ai_invalid_output";

export type PhotoScanRejectionReason = "no_item" | "unclear_image" | "inappropriate";

export interface PhotoScanItem {
  /** Item name as it would appear on a receipt line (pt-BR). */
  description: string;
  category: Category;
  /** Model self-assessment, 0..1. */
  confidence: number;
}

export interface PhotoScanIdentified {
  status: "identified";
  /** One entry per distinct product in the photo, most prominent first. Never empty. */
  items: PhotoScanItem[];
  /** Free-form remark the AI wants to surface about the photo (pt-BR). */
  comment: string;
}

export interface PhotoScanRejected {
  status: "rejected";
  reason: PhotoScanRejectionReason;
  /** Why the item could not be identified (pt-BR). */
  comment: string;
}

export type PhotoScanResult = PhotoScanIdentified | PhotoScanRejected;
