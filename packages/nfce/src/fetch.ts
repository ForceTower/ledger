import { NfceError } from "./errors";
import type { FetchedReceipt } from "./index";
import type { NfceLink, SefazPortal } from "./sefaz";
import { validateAccessKey } from "./sefaz";

// SEFAZ blocks generic clients; the prototype impersonates mobile Safari and it works.
const USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
// SP's consultation is validated against the desktop rendering (the mobile one strips the
// "Visualizar em Abas" postback the detailed page depends on).
const DESKTOP_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
const DEFAULT_TIMEOUT_MS = 60_000;
const MAX_REDIRECTS = 5;

type FetchImpl = (input: string, init?: RequestInit) => Promise<Response>;

export interface FetchOptions {
  /** Override the global fetch — used by tests to serve fixture HTML without hitting the network. */
  fetchImpl?: FetchImpl;
  timeoutMs?: number;
}

/**
 * Download the simplified + detailed receipt HTML for a validated QR link, using the fetch flow the
 * portal's SEFAZ speaks (`portal.flow`).
 */
export async function fetchReceipt(link: NfceLink, options?: FetchOptions): Promise<FetchedReceipt> {
  switch (link.portal.flow) {
    case "svrs":
      return await fetchSvrsReceipt(link, options);
    case "sp":
      return await fetchSpReceipt(link, options);
    default:
      return await fetchBaReceipt(link, options);
  }
}

/**
 * Bahia's flow. SEFAZ-BA is ASP.NET WebForms, so this is a three-step dance over ONE cookie session:
 *   1. GET the scanned QR URL — the simplified receipt.
 *   2. Replay the page's hidden `__*` inputs as a postback (`__EVENTTARGET=btn_visualizar_abas`) to
 *      reveal the detailed tabs.
 *   3. GET the print page — it carries the per-item EAN the simplified page lacks.
 */
async function fetchBaReceipt(link: NfceLink, options?: FetchOptions): Promise<FetchedReceipt> {
  const fetchImpl = options?.fetchImpl ?? fetch;
  const timeoutMs = options?.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const danfeUrl = `${link.portal.consultBase}NFCEC_consulta_danfe.aspx`;
  const cookies = new Map<string, string>();

  // The `|` separators in the scanned payload must be percent-encoded for the GET to resolve.
  const simpleHtml = await sefazRequest(fetchImpl, link.url.replace(/\|/g, "%7C"), {
    referer: danfeUrl,
    cookies,
    timeoutMs,
  });
  if (!simpleHtml.includes("btn_visualizar_abas")) {
    // The portal validates the QR's CSC signature before showing anything; a store signing with a
    // bad CSC gets its whole payload refused (e.g. "[QRCode v2.00]: 103 - Identificador de CSC
    // inexistente."). The receipt itself usually exists — only this door is closed.
    const qrRejection = /\[QRCode[^\]]*\][:\s]*([^<]+)/.exec(simpleHtml)?.[1]?.trim();
    if (qrRejection !== undefined) {
      throw new NfceError("qr_rejected", `SEFAZ rejected the QR code: ${qrRejection}`);
    }
    throw new NfceError("expired", "SEFAZ did not return the receipt (link expired or not found)");
  }

  return await fetchDetailPages(fetchImpl, link.portal, cookies, timeoutMs, link.accessKey, simpleHtml);
}

/**
 * SVRS (Sefaz Virtual RS) flow. The QR URL serves the simplified receipt directly, and the public
 * consultation answers with the detailed page (per-item EANs) for a bare access key — no postbacks,
 * no captcha:
 *   1. GET the scanned QR URL — the simplified receipt in the national DANFE layout.
 *   2. GET the consultation form to open the cookie session the POST below requires.
 *   3. POST the access key to the NFC-e consultation — the detailed page.
 */
async function fetchSvrsReceipt(link: NfceLink, options?: FetchOptions): Promise<FetchedReceipt> {
  const fetchImpl = options?.fetchImpl ?? fetch;
  const timeoutMs = options?.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const base = link.portal.consultBase;
  const cookies = new Map<string, string>();

  const simpleHtml = await fetchSimplifiedDanfe(fetchImpl, link, cookies, timeoutMs);

  const consultUrl = `${base}Dfe/ConsultaPublicaDfe`;
  await sefazRequest(fetchImpl, consultUrl, { referer: base, cookies, timeoutMs });

  const body = new URLSearchParams({
    sistema: "Dfe",
    EhConsultaPublicaSiteSefaz: "True",
    Ambiente: "1",
    ChaveAcessoDfe: link.accessKey,
  }).toString();
  const fullHtml = await sefazRequest(fetchImpl, `${base}Nfce/ConsultaPublicaDfe`, {
    body,
    referer: consultUrl,
    cookies,
    timeoutMs,
  });
  if (!fullHtml.includes("EAN")) {
    throw new NfceError("unavailable", "SEFAZ detailed page returned no products");
  }

  return { accessKey: link.accessKey, simpleHtml, fullHtml };
}

/**
 * SP's QR flow: the scanned URL serves only the simplified page — the detailed one is behind the
 * captcha-gated key consultation (`startKeyConsult`), which cannot run inside a one-shot fetch.
 * The parser handles an empty detailed page — the receipt just carries no item bar codes.
 */
async function fetchSpReceipt(link: NfceLink, options?: FetchOptions): Promise<FetchedReceipt> {
  const fetchImpl = options?.fetchImpl ?? fetch;
  const timeoutMs = options?.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const cookies = new Map<string, string>();

  const simpleHtml = await fetchSimplifiedDanfe(fetchImpl, link, cookies, timeoutMs);
  return { accessKey: link.accessKey, simpleHtml, fullHtml: "" };
}

/** GET the scanned QR URL and validate it rendered the national DANFE layout's items table
 * (`tabResult`) — its absence means the portal answered with an error page instead of the receipt. */
async function fetchSimplifiedDanfe(
  fetchImpl: FetchImpl,
  link: NfceLink,
  cookies: Map<string, string>,
  timeoutMs: number,
): Promise<string> {
  const simpleHtml = await sefazRequest(fetchImpl, link.url.replace(/\|/g, "%7C"), {
    referer: link.portal.consultBase,
    cookies,
    timeoutMs,
  });
  if (!simpleHtml.includes("tabResult")) {
    throw new NfceError("expired", "SEFAZ did not return the receipt (link expired or not found)");
  }
  return simpleHtml;
}

/** A live SEFAZ cookie session opened by `startKeyConsult`, waiting for the captcha answer. The
 * API holds it between the challenge and completion requests; it is process-local state. */
export interface KeyConsultSession {
  accessKey: string;
  portal: SefazPortal;
  /** ASP.NET session cookies — the captcha answer is only valid inside this session. */
  cookies: Map<string, string>;
  /** Hidden `__*` form fields captured from the consultation form, replayed on completion. */
  fields: Map<string, string>;
}

export interface KeyConsultChallenge {
  session: KeyConsultSession;
  /** The anti-robot image (JPEG) whose characters the owner must read. */
  captchaImage: Uint8Array;
}

/**
 * Open the portal's consulta-por-chave form and grab its anti-robot captcha.
 *
 * For BA this is the fallback for `qr_rejected` links; for SP it is the only way to reach the
 * detailed page (per-item EANs). Both portals serve any authorized receipt by bare access key but
 * gate that flow behind an image captcha only the owner can read. The captcha answer is minted
 * server-side when the image is requested and stored in the ASP.NET session, so the image GET must
 * reuse the form's cookies — and `completeKeyConsult` must reuse both.
 */
export async function startKeyConsult(rawAccessKey: string, options?: FetchOptions): Promise<KeyConsultChallenge> {
  const { accessKey, portal } = validateAccessKey(rawAccessKey);
  switch (portal.flow) {
    case "ba":
      return await startBaKeyConsult(accessKey, portal, options);
    case "sp":
      return await startSpKeyConsult(accessKey, portal, options);
    default:
      // SVRS needs no captcha — its detailed page already comes with the QR flow.
      throw new NfceError(
        "unavailable",
        `Access-key consultation is not supported for ${portal.uf} — scan the QR code`,
      );
  }
}

async function startBaKeyConsult(
  accessKey: string,
  portal: SefazPortal,
  options?: FetchOptions,
): Promise<KeyConsultChallenge> {
  const fetchImpl = options?.fetchImpl ?? fetch;
  const timeoutMs = options?.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const consultUrl = `${portal.consultBase}NFCEC_consulta_chave_acesso.aspx`;
  const cookies = new Map<string, string>();

  const formHtml = await sefazRequest(fetchImpl, consultUrl, { referer: consultUrl, cookies, timeoutMs });
  if (!formHtml.includes("txt_chave_acesso")) {
    throw new NfceError("unavailable", "SEFAZ did not return the access-key consultation form");
  }

  const captchaUrl = new URL("../AntiRobo/NFCEC_anti_robo.aspx", consultUrl).toString();
  const captchaResponse = await sefazFetch(fetchImpl, captchaUrl, { referer: consultUrl, cookies, timeoutMs });
  const captchaImage = new Uint8Array(await captchaResponse.arrayBuffer());
  if (captchaImage.length === 0) {
    throw new NfceError("unavailable", "SEFAZ returned an empty captcha image");
  }

  return { session: { accessKey, portal, cookies, fields: hiddenFields(formHtml) }, captchaImage };
}

// SP's consultation lives under this module path; the flow was reverse-engineered against it. The
// desktop user agent matters: the mobile rendering strips the "Visualizar em Abas" postback.
const SP_CONSULT_PATH = "NFCeConsultaPublica/Paginas/ConsultaPublica.aspx";
const SP_FRAME_PATH = "NFCeConsultaPublica/Paginas/ConsultaResponsiva/ConsultaResumidaRJFrame_v400.aspx";
const SP_CAPTCHA_PATH = "NFCeConsultaPublica/Captcha/RandomImageHandler.ashx";

async function startSpKeyConsult(
  accessKey: string,
  portal: SefazPortal,
  options?: FetchOptions,
): Promise<KeyConsultChallenge> {
  const fetchImpl = options?.fetchImpl ?? fetch;
  const timeoutMs = options?.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const consultUrl = `${portal.consultBase}${SP_CONSULT_PATH}`;
  const cookies = new Map<string, string>();

  const formHtml = await sefazRequest(fetchImpl, consultUrl, {
    referer: consultUrl,
    cookies,
    timeoutMs,
    userAgent: DESKTOP_USER_AGENT,
  });
  if (!formHtml.includes("txtChaveAcesso")) {
    throw new NfceError("unavailable", "SEFAZ did not return the access-key consultation form");
  }

  const captchaUrl = `${portal.consultBase}${SP_CAPTCHA_PATH}?r=${Math.random()}`;
  const captchaResponse = await sefazFetch(fetchImpl, captchaUrl, {
    referer: consultUrl,
    cookies,
    timeoutMs,
    userAgent: DESKTOP_USER_AGENT,
  });
  const captchaImage = new Uint8Array(await captchaResponse.arrayBuffer());
  if (captchaImage.length === 0) {
    throw new NfceError("unavailable", "SEFAZ returned an empty captcha image");
  }

  // SP's form carries anti-bot hidden fields beyond the `__*` set (including one with a randomized
  // name); the whole set must be replayed on completion.
  return { session: { accessKey, portal, cookies, fields: allHiddenFields(formHtml) }, captchaImage };
}

/**
 * Answer the captcha and download the receipt pages, mirroring `fetchReceipt`'s output.
 *
 * A wrong answer throws `captcha_rejected`; the portal invalidates the shown image on every
 * attempt, so retrying requires a fresh `startKeyConsult`. A key the portal does not know yet
 * throws `expired` — same meaning as the QR flow's "not found".
 */
export async function completeKeyConsult(
  session: KeyConsultSession,
  captchaAnswer: string,
  options?: FetchOptions,
): Promise<FetchedReceipt> {
  return session.portal.flow === "sp"
    ? await completeSpKeyConsult(session, captchaAnswer, options)
    : await completeBaKeyConsult(session, captchaAnswer, options);
}

async function completeBaKeyConsult(
  session: KeyConsultSession,
  captchaAnswer: string,
  options?: FetchOptions,
): Promise<FetchedReceipt> {
  const fetchImpl = options?.fetchImpl ?? fetch;
  const timeoutMs = options?.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const consultUrl = `${session.portal.consultBase}NFCEC_consulta_chave_acesso.aspx`;

  const fields = new Map(session.fields);
  fields.set("__EVENTTARGET", "");
  fields.set("__EVENTARGUMENT", "");
  fields.set("__LASTFOCUS", "");
  fields.set("txt_chave_acesso", session.accessKey);
  fields.set("txt_cod_antirobo", captchaAnswer.trim());
  fields.set("btn_consulta_completa", "Consultar");

  // Success 302s into the DANFE page; failures re-render the form with the reason in lbl_invalido.
  const landing = await sefazRequest(fetchImpl, consultUrl, {
    body: new URLSearchParams([...fields]).toString(),
    referer: consultUrl,
    cookies: session.cookies,
    timeoutMs,
  });
  if (!landing.includes("btn_visualizar_abas")) {
    throw keyConsultError(landing);
  }

  return await fetchDetailPages(fetchImpl, session.portal, session.cookies, timeoutMs, session.accessKey, landing);
}

function keyConsultError(html: string): NfceError {
  const reason = /id="lbl_invalido"[^>]*>([^<]*)/.exec(html)?.[1]?.trim() ?? "";
  if (/código incorreto/i.test(reason)) {
    return new NfceError("captcha_rejected", "SEFAZ refused the captcha answer");
  }
  if (/não foi encontrada/i.test(reason)) {
    return new NfceError("expired", "SEFAZ has no receipt under this access key (yet)");
  }
  return new NfceError("unavailable", `SEFAZ refused the access-key consultation: ${reason || "unknown reason"}`);
}

/**
 * SP's completion: POST key + captcha to the consultation form, then replay the "Visualizar em
 * Abas" postback to reach the detailed tabs. The consultation answers with the simplified receipt
 * (same national layout the QR page serves), so this yields both pages from a bare access key.
 *
 * SEFAZ rotates the session cookie during these hops — `sefazFetch` captures every `Set-Cookie`
 * into the session's jar, which is what keeps the captcha blessing attached to later requests.
 */
async function completeSpKeyConsult(
  session: KeyConsultSession,
  captchaAnswer: string,
  options?: FetchOptions,
): Promise<FetchedReceipt> {
  const fetchImpl = options?.fetchImpl ?? fetch;
  const timeoutMs = options?.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const consultUrl = `${session.portal.consultBase}${SP_CONSULT_PATH}`;

  const fields = new Map(session.fields);
  fields.set("__EVENTTARGET", "");
  fields.set("__EVENTARGUMENT", "");
  fields.set("ctl00$Conteudo$txtChaveAcesso", session.accessKey);
  fields.set("ctl00$Conteudo$ctlCaptcha$txCodigo", captchaAnswer.trim());
  fields.set("ctl00$Conteudo$btnConsultaResumida", "Consultar");

  const landing = await sefazRequest(fetchImpl, consultUrl, {
    body: new URLSearchParams([...fields]).toString(),
    referer: consultUrl,
    cookies: session.cookies,
    timeoutMs,
    userAgent: DESKTOP_USER_AGENT,
  });
  if (!landing.includes("tabResult")) {
    throw spKeyConsultError(landing);
  }

  const abasFields = allHiddenFields(landing);
  abasFields.set("__EVENTTARGET", "btnVisualizarAbas");
  abasFields.set("__EVENTARGUMENT", "");
  // The postback 302s back into the consultation page, which now renders the detailed tabs.
  const fullHtml = await sefazRequest(fetchImpl, `${session.portal.consultBase}${SP_FRAME_PATH}`, {
    body: new URLSearchParams([...abasFields]).toString(),
    referer: consultUrl,
    cookies: session.cookies,
    timeoutMs,
    userAgent: DESKTOP_USER_AGENT,
  });
  if (!fullHtml.includes("EAN")) {
    throw new NfceError("unavailable", "SEFAZ detailed page returned no products");
  }

  return { accessKey: session.accessKey, simpleHtml: landing, fullHtml };
}

// SP reports failures by injecting the message into a jQuery error dialog.
function spKeyConsultError(html: string): NfceError {
  const reason = /\('([^']+)'\);\s*\$\(function\(\)\s*\{\s*openDialog\('divErroMaster'\)/.exec(html)?.[1]?.trim() ?? "";
  if (/captcha informado incorretamente/i.test(reason)) {
    return new NfceError("captcha_rejected", "SEFAZ refused the captcha answer");
  }
  if (/não\s+(foi\s+)?(encontrada|localizada)/i.test(reason)) {
    return new NfceError("expired", "SEFAZ has no receipt under this access key (yet)");
  }
  return new NfceError("unavailable", `SEFAZ refused the access-key consultation: ${reason || "unknown reason"}`);
}

/** The back half both flows share: reveal the detailed tabs, then grab the print page. */
async function fetchDetailPages(
  fetchImpl: FetchImpl,
  portal: SefazPortal,
  cookies: Map<string, string>,
  timeoutMs: number,
  accessKey: string,
  simpleHtml: string,
): Promise<FetchedReceipt> {
  const danfeUrl = `${portal.consultBase}NFCEC_consulta_danfe.aspx`;
  const printUrl = `${portal.consultBase}Frm_Imprimir_parcial.aspx?imprimir_nfe=1&print=true`;
  const request = (url: string, body?: string) =>
    sefazRequest(fetchImpl, url, { body, referer: danfeUrl, cookies, timeoutMs });

  const fields = hiddenFields(simpleHtml);
  fields.set("__EVENTTARGET", "btn_visualizar_abas");
  fields.set("__EVENTARGUMENT", "");
  await request(danfeUrl, new URLSearchParams([...fields]).toString());

  const fullHtml = await request(printUrl);
  if (!fullHtml.includes("EAN")) {
    throw new NfceError("unavailable", "SEFAZ detailed page returned no products");
  }

  return { accessKey, simpleHtml, fullHtml };
}

interface RequestState {
  body?: string;
  referer: string;
  cookies: Map<string, string>;
  timeoutMs: number;
  userAgent?: string;
}

async function sefazRequest(fetchImpl: FetchImpl, url: string, state: RequestState): Promise<string> {
  const response = await sefazFetch(fetchImpl, url, state);
  return await response.text();
}

// Bun's fetch has no cookie jar, so carry the session by hand: capture `Set-Cookie` from every hop
// (including redirects) and replay it as a single `Cookie` header.
async function sefazFetch(fetchImpl: FetchImpl, url: string, state: RequestState): Promise<Response> {
  const { body, referer, cookies, timeoutMs } = state;
  let currentUrl = url;

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const sendBody = hop === 0 ? body : undefined;
    const headers: Record<string, string> = { "User-Agent": state.userAgent ?? USER_AGENT, Referer: referer };
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
    return response;
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

/** Every hidden input, valued or not — SP validates fields beyond the `__*` set. */
function allHiddenFields(html: string): Map<string, string> {
  const fields = new Map<string, string>();
  for (const match of html.matchAll(/<input[^>]*type="hidden"[^>]*name="([^"]+)"[^>]*?(?:value="([^"]*)")?\s*\/?>/g)) {
    const name = match[1];
    if (name !== undefined) fields.set(name, decodeHtml(match[2] ?? ""));
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
