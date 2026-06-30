import { NfceError } from "./errors";

/** A state's NFC-e consultation portal. The QR code embeds the state in the access key's first two
 * digits (the IBGE `cUF` code), and the scanned URL must point at one of this portal's hosts. */
export interface SefazPortal {
  uf: string;
  /** IBGE state code — the first two digits of every access key issued by this state. */
  cUF: string;
  name: string;
  /** Allowlisted hosts. Validating against these is also the SSRF guard: the API only ever fetches
   * a URL whose host appears here. */
  hosts: string[];
  /** Base URL of the state's NFC-e "geral" module, used to derive the DANFE and print endpoints. */
  consultBase: string;
}

// Bahia only, for now. Other states use different portals and fetch flows; add them here once their
// flow is implemented and tested.
export const SEFAZ_PORTALS: SefazPortal[] = [
  {
    uf: "BA",
    cUF: "29",
    name: "Bahia",
    hosts: ["nfe.sefaz.ba.gov.br"],
    consultBase: "http://nfe.sefaz.ba.gov.br/servicos/nfce/modulos/geral/",
  },
];

/** A scanned QR string that passed validation: a known SEFAZ portal and a structurally valid key. */
export interface NfceLink {
  /** The full scanned payload, unchanged — the hash after the key authenticates the request. */
  url: string;
  accessKey: string;
  portal: SefazPortal;
}

/**
 * Validate a scanned QR string and resolve the SEFAZ portal it belongs to.
 *
 * Rejects anything that isn't an http(s) URL carrying a 44-digit access key whose state maps to a
 * known portal and whose host is allowlisted for that state. Throws `NfceError("invalid_url")` on
 * any failure.
 */
export function validateNfceUrl(raw: string): NfceLink {
  const trimmed = raw.trim();

  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    throw new NfceError("invalid_url", "Scanned value is not a valid URL");
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new NfceError("invalid_url", `Unsupported URL scheme: ${url.protocol}`);
  }

  const param = url.searchParams.get("p") ?? extractPParam(trimmed) ?? "";
  const accessKey = /^\d{44}/.exec(param)?.[0] ?? "";
  if (accessKey.length !== 44) {
    throw new NfceError("invalid_url", "URL is missing the 44-digit NFC-e access key");
  }

  const cUF = accessKey.slice(0, 2);
  const portal = SEFAZ_PORTALS.find((entry) => entry.cUF === cUF);
  if (!portal) {
    throw new NfceError("invalid_url", `Unsupported SEFAZ state (cUF ${cUF})`);
  }

  const host = url.hostname.toLowerCase();
  if (!portal.hosts.includes(host)) {
    throw new NfceError("invalid_url", `Host ${host} is not a recognized ${portal.uf} SEFAZ endpoint`);
  }

  if (!hasValidCheckDigit(accessKey)) {
    throw new NfceError("invalid_url", "NFC-e access key failed its check-digit validation");
  }

  return { url: trimmed, accessKey, portal };
}

// Fallback for the rare case `new URL` keeps the literal `|` but `searchParams` can't isolate `p`.
function extractPParam(raw: string): string | null {
  return /[?&]p=([^&\s]+)/i.exec(raw)?.[1] ?? null;
}

// Standard NF-e access-key check digit: mod-11 over the first 43 digits, weights 2..9 from the right.
function hasValidCheckDigit(key: string): boolean {
  const body = key.slice(0, 43);
  let sum = 0;
  let weight = 2;
  for (let i = body.length - 1; i >= 0; i--) {
    sum += Number(body.charAt(i)) * weight;
    weight = weight === 9 ? 2 : weight + 1;
  }
  const remainder = sum % 11;
  const dv = remainder <= 1 ? 0 : 11 - remainder;
  return dv === Number(key.charAt(43));
}
