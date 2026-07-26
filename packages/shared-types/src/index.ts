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
  // Not groceries: what a typed lançamento tends to be about, and what no receipt line ever is.
  "transport",
  "dining",
  "health",
  "services",
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

export type ScanErrorCode =
  | "invalid_url"
  | "expired"
  | "unavailable"
  | "parse_failed"
  /** SEFAZ refused the QR payload's CSC signature (store-side misconfiguration). The client should
   * offer the access-key consultation (`POST /scan/key/challenge`) instead. */
  | "qr_rejected"
  /** The captcha answer was wrong. The challenge is spent — request a new one. */
  | "captcha_rejected"
  /** The challenge id is unknown or past its TTL — request a new one. */
  | "challenge_expired";

/** An open SEFAZ access-key consultation: the server holds the portal session, the owner answers
 * the captcha. Returned by `POST /scan/key/challenge`, consumed by `POST /scan/key`. */
export interface KeyScanChallenge {
  challengeId: string;
  /** The anti-robot image (JPEG bytes, base64-encoded) whose characters the owner must type. */
  captchaImage: string;
  /** Seconds before the challenge stops being answerable. */
  expiresIn: number;
}

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

export type EntryScanErrorCode =
  | "invalid_input"
  | "not_an_entry"
  | "ai_unavailable"
  | "ai_invalid_output";

/** One line the AI pulled out of the owner's description. */
export interface EntryDraftItem {
  /** What was bought or paid for, as a receipt line would put it (pt-BR). */
  description: string;
  category: Category;
  /** Whole units; null when the description does not say. */
  quantity: number | null;
  /** BRL for one unit; null when the description carries no price for this line. */
  unitPrice: number | null;
}

/**
 * What `POST /scan/entry` reads out of a typed description ("37,00 de transporte no dia 24 de
 * julho"). Reading is not saving — the owner confirms the draft, then posts it to `POST /purchases`.
 */
export interface EntryDraft {
  /** Resolved against the server's today, so "dia 24 de julho" comes back as a real date. */
  date: string;
  time: string | null;
  /** Where the money went, when the description names it. */
  store: string | null;
  /** "Pix", "Dinheiro", "Cartão de crédito"… as the description put it; null when it does not say. */
  paymentMethod: string | null;
  /** One entry per thing paid for. Never empty. */
  items: EntryDraftItem[];
  /** Free-form remark about the reading (pt-BR). */
  comment: string;
}

export interface PurchaseCreateItem {
  description: string;
  category: Category;
  quantity: number;
  unitPrice: number;
}

/** What `POST /purchases` persists: a purchase the owner typed rather than scanned. */
export interface PurchaseCreateRequest {
  date: string;
  time: string | null;
  store: string;
  paymentMethod: string | null;
  items: PurchaseCreateItem[];
}

export type ChatErrorCode = "ai_unavailable";

export interface ChatUsage {
  inputTokens: number;
  outputTokens: number;
  /** What the turn would cost on the Anthropic API, in USD. Nominal when the server runs on a Claude subscription. */
  costUsd: number | null;
}

/** `POST /chat` streams these as server-sent events; the SSE `event:` field carries `type`. */
export interface ChatSessionEvent {
  type: "session";
  /** Opaque server-side conversation id. Send it back on the next message to continue the conversation. */
  sessionId: string;
}

export interface ChatTextEvent {
  type: "text";
  /** A chunk of the assistant's answer, in order. Concatenate chunks to render the message. */
  text: string;
}

export interface ChatToolEvent {
  type: "tool";
  /** The SQL the assistant is running against the ledger database (read-only). */
  sql: string;
}

export interface ChatDoneEvent {
  type: "done";
  sessionId: string;
  usage: ChatUsage;
  durationMs: number;
}

export interface ChatErrorEvent {
  type: "error";
  /** pt-BR, presentable to the owner. */
  message: string;
  errorCode: ChatErrorCode;
}

export type ChatStreamEvent =
  | ChatSessionEvent
  | ChatTextEvent
  | ChatToolEvent
  | ChatDoneEvent
  | ChatErrorEvent;

export type PhotoScanErrorCode = "invalid_image" | "ai_unavailable" | "ai_invalid_output";

export type PhotoScanRejectionReason = "no_item" | "unclear_image" | "inappropriate";

export interface PhotoScanItem {
  /** Item name as it would appear on a receipt line (pt-BR). */
  description: string;
  category: Category;
  /** Model self-assessment, 0..1. */
  confidence: number;
  /** Price for one unit in BRL, read off a price tag or receipt line; null when the photo does not show one. */
  unitPrice: number | null;
  /** Whole units of this product, read off the receipt or counted in the photo; null when unsure. */
  quantity: number | null;
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
