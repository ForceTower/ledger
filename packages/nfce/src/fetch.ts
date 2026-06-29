import type { FetchedReceipt } from "./index";

export interface FetchOptions {
  /** SEFAZ-BA NFC-e module base URL. */
  baseUrl: string;
}

/**
 * Download the simplified + detailed receipt HTML for a scanned QR URL.
 *
 * The QR URL looks like `…/NFCEC_consulta_chave_acesso.aspx?p=<44-digit-key>|2|1|1|<hash>`. The hash
 * authenticates the request and skips the captcha, so the caller must pass the full scanned payload.
 *
 * TODO: port from the prototype's fetch_nfce.py. The SEFAZ site is ASP.NET WebForms, so:
 *   1. GET the simplified receipt page (the QR URL).
 *   2. Scrape the hidden inputs (`__VIEWSTATE`, `__VIEWSTATEGENERATOR`, `__EVENTVALIDATION`).
 *   3. POST them back to the DANFE page with `__EVENTTARGET=btn_visualizar_abas` to reveal the tabs.
 *   4. GET the print/detailed page — it carries the per-item EAN that the simplified page lacks.
 *   All four requests share ONE cookie session. Bun's fetch has no cookie jar, so capture
 *   `Set-Cookie` from each response and forward it via the `Cookie` header on the next request.
 *
 * Throw a typed error the API can map to errorCode `expired` (link dead / not found) or `unavailable`
 * (SEFAZ unreachable / detailed page missing products).
 */
export async function fetchReceipt(_url: string, _options: FetchOptions): Promise<FetchedReceipt> {
  throw new Error("fetchReceipt not implemented — port from prototype fetch_nfce.py");
}
