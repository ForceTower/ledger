import { describe, expect, test } from "bun:test";
import { fetchReceipt, NfceError, type NfceErrorCode, validateNfceUrl } from "../src/index";

const VALID_KEY = "29261111111111111111650010000000011123456780";
const VALID_URL = `http://nfe.sefaz.ba.gov.br/servicos/nfce/modulos/geral/NFCEC_consulta_chave_acesso.aspx?p=${VALID_KEY}|2|1|1|A1B2C3`;

const SIMPLE_HTML = `<html><body>
  <input type="hidden" name="__VIEWSTATE" id="__VIEWSTATE" value="vs123" />
  <input type="hidden" name="__EVENTVALIDATION" id="__EVENTVALIDATION" value="ev456" />
  <a id="btn_visualizar_abas" href="#">Visualizar em Abas</a>
</body></html>`;
const FULL_HTML = `<html><body><label>Código EAN Comercial</label><span>7890000000001</span></body></html>`;

interface RecordedCall {
  url: string;
  method: string;
  headers: Headers;
  body: string | undefined;
}

function html(body: string, init: { status?: number; setCookie?: string[]; location?: string } = {}): Response {
  const headers = new Headers();
  for (const cookie of init.setCookie ?? []) headers.append("Set-Cookie", cookie);
  if (init.location !== undefined) headers.set("Location", init.location);
  return new Response(body, { status: init.status ?? 200, headers });
}

function makeStub(responses: Response[]) {
  const calls: RecordedCall[] = [];
  let index = 0;
  const fetchImpl = (input: string, init?: RequestInit): Promise<Response> => {
    calls.push({
      url: input,
      method: init?.method ?? "GET",
      headers: new Headers(init?.headers),
      body: typeof init?.body === "string" ? init.body : undefined,
    });
    const response = responses[index++];
    if (response === undefined) throw new Error(`unexpected fetch call #${index}: ${input}`);
    return Promise.resolve(response);
  };
  const at = (i: number): RecordedCall => {
    const call = calls[i];
    if (call === undefined) throw new Error(`expected fetch call #${i}`);
    return call;
  };
  return { fetchImpl, calls, at };
}

async function expectNfce(fn: () => Promise<unknown>, code: NfceErrorCode) {
  try {
    await fn();
  } catch (error) {
    if (!(error instanceof NfceError)) throw new Error(`expected NfceError, got ${String(error)}`);
    expect(error.code).toBe(code);
    return;
  }
  throw new Error(`expected NfceError(${code})`);
}

describe("fetchReceipt", () => {
  test("walks the three-step flow and returns both pages", async () => {
    const link = validateNfceUrl(VALID_URL);
    const { fetchImpl, calls, at } = makeStub([
      html(SIMPLE_HTML, { setCookie: ["ASP.NET_SessionId=abc; path=/; HttpOnly"] }),
      html("<html>postback</html>"),
      html(FULL_HTML),
    ]);

    const result = await fetchReceipt(link, { fetchImpl });

    expect(result.accessKey).toBe(VALID_KEY);
    expect(result.simpleHtml).toContain("btn_visualizar_abas");
    expect(result.fullHtml).toContain("EAN");

    expect(calls).toHaveLength(3);
    expect(at(0).url).toContain("%7C");
    expect(at(0).url).not.toContain("|");

    expect(at(1).method).toBe("POST");
    expect(at(1).url).toContain("NFCEC_consulta_danfe.aspx");
    expect(at(1).body).toContain("__VIEWSTATE=vs123");
    expect(at(1).body).toContain("__EVENTVALIDATION=ev456");
    expect(at(1).body).toContain("__EVENTTARGET=btn_visualizar_abas");
    expect(at(1).headers.get("cookie")).toContain("ASP.NET_SessionId=abc");

    expect(at(2).url).toContain("Frm_Imprimir_parcial.aspx");
  });

  test("follows redirects and carries cookies across hops", async () => {
    const link = validateNfceUrl(VALID_URL);
    const redirectTarget = "http://nfe.sefaz.ba.gov.br/servicos/nfce/modulos/geral/landing.aspx";
    const { fetchImpl, at } = makeStub([
      html("", { status: 302, location: redirectTarget, setCookie: ["S=sess1; path=/"] }),
      html(SIMPLE_HTML),
      html("<html>postback</html>"),
      html(FULL_HTML),
    ]);

    const result = await fetchReceipt(link, { fetchImpl });

    expect(result.fullHtml).toContain("EAN");
    expect(at(1).url).toBe(redirectTarget);
    expect(at(1).method).toBe("GET");
    expect(at(1).headers.get("cookie")).toContain("S=sess1");
  });

  test("throws expired when the simplified page lacks the tabs button", async () => {
    const link = validateNfceUrl(VALID_URL);
    const { fetchImpl } = makeStub([html("<html>link expired</html>")]);
    await expectNfce(() => fetchReceipt(link, { fetchImpl }), "expired");
  });

  test("throws unavailable when the detailed page has no products", async () => {
    const link = validateNfceUrl(VALID_URL);
    const { fetchImpl } = makeStub([
      html(SIMPLE_HTML),
      html("<html>postback</html>"),
      html("<html>no products here</html>"),
    ]);
    await expectNfce(() => fetchReceipt(link, { fetchImpl }), "unavailable");
  });

  test("wraps network failures as unavailable", async () => {
    const link = validateNfceUrl(VALID_URL);
    const fetchImpl = () => Promise.reject(new Error("ECONNREFUSED"));
    await expectNfce(() => fetchReceipt(link, { fetchImpl }), "unavailable");
  });
});
