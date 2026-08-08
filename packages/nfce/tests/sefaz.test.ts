import { describe, expect, test } from "bun:test";
import { NfceError, validateAccessKey, validateNfceUrl } from "../src/index";

// Synthetic BA key: cUF 29, dummy CNPJ/series/number, check digit (0) computed for this body.
const VALID_KEY = "29261111111111111111650010000000011123456780";
const BA_BASE = "http://nfe.sefaz.ba.gov.br/servicos/nfce/modulos/geral/NFCEC_consulta_chave_acesso.aspx";
const VALID_URL = `${BA_BASE}?p=${VALID_KEY}|2|1|1|A1B2C3`;

// Synthetic RS key: cUF 43, dummy CNPJ/series/number, check digit (7) computed for this body.
const RS_KEY = "43260811222333000181650130001234571379386587";
const RS_URL = `https://dfe-portal.svrs.rs.gov.br/Dfe/QrCodeNFce?p=${RS_KEY}|2|1|1|A1B2C3`;

function expectInvalidUrl(fn: () => unknown) {
  try {
    fn();
  } catch (error) {
    if (!(error instanceof NfceError)) throw new Error(`expected NfceError, got ${String(error)}`);
    expect(error.code).toBe("invalid_url");
    return;
  }
  throw new Error("expected validateNfceUrl to throw");
}

describe("validateNfceUrl", () => {
  test("accepts a well-formed Bahia NFC-e URL", () => {
    const link = validateNfceUrl(VALID_URL);
    expect(link.accessKey).toBe(VALID_KEY);
    expect(link.portal.uf).toBe("BA");
    expect(link.url).toBe(VALID_URL);
  });

  test("accepts a well-formed RS (SVRS) NFC-e URL", () => {
    const link = validateNfceUrl(RS_URL);
    expect(link.accessKey).toBe(RS_KEY);
    expect(link.portal.uf).toBe("RS");
    expect(link.portal.flow).toBe("svrs");
  });

  test("rejects an RS key served from another state's host", () => {
    expectInvalidUrl(() => validateNfceUrl(`${BA_BASE}?p=${RS_KEY}|2|1|1|A1B2C3`));
  });

  test("trims surrounding whitespace", () => {
    expect(validateNfceUrl(`  ${VALID_URL}\n`).accessKey).toBe(VALID_KEY);
  });

  test("rejects a URL with no p= parameter", () => {
    expectInvalidUrl(() => validateNfceUrl(`${BA_BASE}?foo=bar`));
  });

  test("rejects a key that is not 44 digits", () => {
    expectInvalidUrl(() => validateNfceUrl(`${BA_BASE}?p=12345|2|1|1|HASH`));
  });

  test("rejects a host that is not an allowlisted SEFAZ endpoint", () => {
    expectInvalidUrl(() => validateNfceUrl(`http://evil.example.com/x?p=${VALID_KEY}|2|1|1|HASH`));
  });

  test("rejects a key from an unsupported state", () => {
    const spKey = `35${VALID_KEY.slice(2)}`;
    expectInvalidUrl(() => validateNfceUrl(`${BA_BASE}?p=${spKey}|2|1|1|HASH`));
  });

  test("rejects a key whose check digit is wrong", () => {
    const tampered = `${VALID_KEY.slice(0, 43)}9`;
    expectInvalidUrl(() => validateNfceUrl(`${BA_BASE}?p=${tampered}|2|1|1|HASH`));
  });

  test("rejects a non-http(s) scheme", () => {
    expectInvalidUrl(() => validateNfceUrl(`ftp://nfe.sefaz.ba.gov.br/x?p=${VALID_KEY}`));
  });

  test("rejects a value that is not a URL", () => {
    expectInvalidUrl(() => validateNfceUrl("not a url"));
  });
});

describe("validateAccessKey", () => {
  test("accepts a well-formed Bahia key, trimming whitespace", () => {
    const { accessKey, portal } = validateAccessKey(` ${VALID_KEY} `);
    expect(accessKey).toBe(VALID_KEY);
    expect(portal.uf).toBe("BA");
  });

  test("rejects a key that is not 44 digits", () => {
    expectInvalidUrl(() => validateAccessKey("12345"));
  });

  test("rejects a key from an unsupported state", () => {
    expectInvalidUrl(() => validateAccessKey(`35${VALID_KEY.slice(2)}`));
  });

  test("rejects a key whose check digit is wrong", () => {
    expectInvalidUrl(() => validateAccessKey(`${VALID_KEY.slice(0, 43)}9`));
  });
});
