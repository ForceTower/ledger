import type { ParsedReceipt } from "./index";

/**
 * Parse the simplified + detailed receipt HTML into a structured, categorized purchase.
 *
 * TODO: port from the prototype's parse_nfce.py. Key points:
 *   - Items, totals, payments come from the simplified page; the detailed page only adds the EAN.
 *   - Match EAN to items by position (the detailed page lists products in receipt order); fall back to
 *     a code -> EAN map when counts differ.
 *   - BRL money parsing: "1.234,56" -> 1234.56.
 *   - Derive receipt number/series from the 44-digit access key when not printed.
 *   - Compute `change` when a single cash payment exceeds the total.
 *   - Categorize each item via ./categorize (Portuguese description -> English category).
 *   - Validate: item count and the sum of item totals vs. the receipt total -> push to `warnings`
 *     (never throw on a mismatch; a flagged-but-saved purchase is still useful).
 */
export function parseReceipt(_simpleHtml: string, _fullHtml: string): ParsedReceipt {
  throw new Error("parseReceipt not implemented — port from prototype parse_nfce.py");
}
