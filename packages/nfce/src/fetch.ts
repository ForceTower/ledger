import { NfceError } from "./errors";
import type { FetchedReceipt } from "./index";
import type { NfceLink } from "./sefaz";

// SEFAZ blocks generic clients; the prototype impersonates mobile Safari and it works.
const USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
const DEFAULT_TIMEOUT_MS = 60_000;
const MAX_REDIRECTS = 5;

type FetchImpl = (input: string, init?: RequestInit) => Promise<Response>;

export interface FetchOptions {
  /** Override the global fetch — used by tests to serve fixture HTML without hitting the network. */
  fetchImpl?: FetchImpl;
  timeoutMs?: number;
}

/**
 * Download the simplified + detailed receipt HTML for a validated QR link.
 *
 * SEFAZ is ASP.NET WebForms, so this is a three-step dance over ONE cookie session:
 *   1. GET the scanned QR URL — the simplified receipt.
 *   2. Replay the page's hidden `__*` inputs as a postback (`__EVENTTARGET=btn_visualizar_abas`) to
 *      reveal the detailed tabs.
 *   3. GET the print page — it carries the per-item EAN the simplified page lacks.
 */
export async function fetchReceipt(link: NfceLink, options?: FetchOptions): Promise<FetchedReceipt> {
  const fetchImpl = options?.fetchImpl ?? fetch;
  const timeoutMs = options?.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const danfeUrl = `${link.portal.consultBase}NFCEC_consulta_danfe.aspx`;
  const printUrl = `${link.portal.consultBase}Frm_Imprimir_parcial.aspx?imprimir_nfe=1&print=true`;

  const cookies = new Map<string, string>();
  const request = (url: string, body?: string) =>
    sefazRequest(fetchImpl, url, { body, referer: danfeUrl, cookies, timeoutMs });

  // The `|` separators in the scanned payload must be percent-encoded for the GET to resolve.
  const simpleHtml = await request(link.url.replace(/\|/g, "%7C"));
  if (!simpleHtml.includes("btn_visualizar_abas")) {
    throw new NfceError("expired", "SEFAZ did not return the receipt (link expired or not found)");
  }

  const fields = hiddenFields(simpleHtml);
  fields.set("__EVENTTARGET", "btn_visualizar_abas");
  fields.set("__EVENTARGUMENT", "");
  await request(danfeUrl, new URLSearchParams([...fields]).toString());

  const fullHtml = await request(printUrl);
  if (!fullHtml.includes("EAN")) {
    throw new NfceError("unavailable", "SEFAZ detailed page returned no products");
  }

  return { accessKey: link.accessKey, simpleHtml, fullHtml };
}

interface RequestState {
  body?: string;
  referer: string;
  cookies: Map<string, string>;
  timeoutMs: number;
}

// Bun's fetch has no cookie jar, so carry the session by hand: capture `Set-Cookie` from every hop
// (including redirects) and replay it as a single `Cookie` header.
async function sefazRequest(fetchImpl: FetchImpl, url: string, state: RequestState): Promise<string> {
  const { body, referer, cookies, timeoutMs } = state;
  let currentUrl = url;

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const sendBody = hop === 0 ? body : undefined;
    const headers: Record<string, string> = { "User-Agent": USER_AGENT, Referer: referer };
    if (sendBody !== undefined) headers["Content-Type"] = "application/x-www-form-urlencoded";
    if (cookies.size > 0) headers.Cookie = serializeCookies(cookies);

    let response: Response;
    try {
      response = await fetchImpl(currentUrl, {
        method: sendBody === undefined ? "GET" : "POST",
        headers,
        body: sendBody,
        redirect: "manual",
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (error) {
      throw new NfceError("unavailable", `SEFAZ request failed: ${currentUrl}`, error);
    }

    captureCookies(response, cookies);

    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("location");
      if (location === null) break;
      currentUrl = new URL(location, currentUrl).toString();
      continue;
    }
    if (!response.ok) {
      throw new NfceError("unavailable", `SEFAZ returned HTTP ${response.status} for ${currentUrl}`);
    }
    return await response.text();
  }

  throw new NfceError("unavailable", `Too many redirects fetching ${url}`);
}

function captureCookies(response: Response, jar: Map<string, string>): void {
  for (const raw of response.headers.getSetCookie()) {
    const pair = raw.split(";")[0];
    if (pair === undefined) continue;
    const eq = pair.indexOf("=");
    if (eq <= 0) continue;
    jar.set(pair.slice(0, eq).trim(), pair.slice(eq + 1).trim());
  }
}

function serializeCookies(jar: Map<string, string>): string {
  return Array.from(jar, ([name, value]) => `${name}=${value}`).join("; ");
}

function hiddenFields(html: string): Map<string, string> {
  const fields = new Map<string, string>();
  for (const match of html.matchAll(/name="(__[A-Z]+)"[^>]*value="([^"]*)"/g)) {
    const name = match[1];
    const value = match[2];
    if (name !== undefined && value !== undefined) fields.set(name, decodeHtml(value));
  }
  return fields;
}

function decodeHtml(value: string): string {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}
