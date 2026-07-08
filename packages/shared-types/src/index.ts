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

export type PurchaseSource = "nfce" | "manual";

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
