import type { Category, PurchaseSource } from "@ledger/shared-types";

export { categorize } from "./categorize";
export { fetchReceipt } from "./fetch";
export { parseReceipt } from "./parse";

// The structured output of the parser. The API maps this to the DB and the wire contract.
export interface ParsedItem {
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

export interface ParsedReceipt {
  source: PurchaseSource;
  date: string;
  time: string;
  store: { name: string; legalName: string | null; cnpj: string | null; address: string | null };
  receipt: { number: number | null; series: number | null; accessKey: string };
  items: ParsedItem[];
  totals: { itemCount: number; gross: number; discount: number; totalPaid: number };
  payments: { code: number | null; method: string; amount: number; change?: number }[];
  taxesTotal: number | null;
  warnings: string[];
}

export interface FetchedReceipt {
  accessKey: string;
  simpleHtml: string;
  fullHtml: string;
}
