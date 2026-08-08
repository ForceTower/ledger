import { describe, expect, test } from "bun:test";
import {
  completeKeyConsult,
  fetchReceipt,
  NfceError,
  type NfceErrorCode,
  startKeyConsult,
  validateNfceUrl,
} from "../src/index";

const VALID_KEY = "29261111111111111111650010000000011123456780";
const VALID_URL = `http://nfe.sefaz.ba.gov.br/servicos/nfce/modulos/geral/NFCEC_consulta_chave_acesso.aspx?p=${VALID_KEY}|2|1|1|A1B2C3`;

const RS_KEY = "43260811222333000181650130001234571379386587";
const RS_URL = `https://dfe-portal.svrs.rs.gov.br/Dfe/QrCodeNFce?p=${RS_KEY}|2|1|1|A1B2C3`;
const RS_SIMPLE_HTML = `<html><body><table id="tabResult"><tr id="Item + 1"></tr></table></body></html>`;

const SP_KEY = "35260844555666000177650040000639241986861830";
const SP_URL = `https://www.nfce.fazenda.sp.gov.br/qrcode?p=${SP_KEY}|2|1|1|A1B2C3`;

const SP_CONSULT_FORM_HTML = `<html><body>
  <form method="post" action="./ConsultaPublica.aspx" id="ctl00">
  <input type="hidden" name="__VIEWSTATE" id="__VIEWSTATE" value="spVs" />
  <input type="hidden" name="__EVENTVALIDATION" id="__EVENTVALIDATION" value="spEv" />
  <input type="hidden" name="ctl00$hdfMsgConfirmacao" value="Deseja prosseguir?" />
  <input type="hidden" name="rAnDoMh0n3yp0t" />
  <input name="ctl00$Conteudo$txtChaveAcesso" type="text" id="Conteudo_txtChaveAcesso" />
  <input name="ctl00$Conteudo$ctlCaptcha$txCodigo" type="text" id="Conteudo_ctlCaptcha_txCodigo" />
  </form>
</body></html>`;
const SP_RESUMIDA_HTML = `<html><body>
  <form method="post" action="ConsultaResponsiva/ConsultaResumidaRJFrame_v400.aspx" id="ctl00">
  <input type="hidden" name="__VIEWSTATE" id="__VIEWSTATE" value="spVs2" />
  <table id="tabResult"><tr id="Item + 1"></tr></table>
  <input type="button" name="btnVisualizarAbas" id="btnVisualizarAbas" />
  </form>
</body></html>`;
const SP_WRONG_CAPTCHA_HTML = `<html><body><script>
  mostraMsgErro('Captcha informado incorretamente. Favor tentar novamente.'); $(function(){openDialog('divErroMaster');});
</script></body></html>`;

const SIMPLE_HTML = `<html><body>
  <input type="hidden" name="__VIEWSTATE" id="__VIEWSTATE" value="vs123" />
  <input type="hidden" name="__EVENTVALIDATION" id="__EVENTVALIDATION" value="ev456" />
  <a id="btn_visualizar_abas" href="#">Visualizar em Abas</a>
</body></html>`;
const FULL_HTML = `<html><body><label>Código EAN Comercial</label><span>7890000000001</span></body></html>`;

const QR_REJECTED_HTML = `<html><body>
  <span id="lbl_invalido">[QRCode v2.00]:  103 - Identificador de CSC inexistente.</span>
</body></html>`;
const CONSULT_FORM_HTML = `<html><body>
  <input type="hidden" name="__VIEWSTATE" id="__VIEWSTATE" value="vsForm" />
  <input type="hidden" name="__EVENTVALIDATION" id="__EVENTVALIDATION" value="evForm" />
  <input name="txt_chave_acesso" type="text" id="txt_chave_acesso" />
  <input name="txt_cod_antirobo" type="text" id="txt_cod_antirobo" />
  <img id="img_captcha" src="../AntiRobo/NFCEC_anti_robo.aspx" />
</body></html>`;
const CAPTCHA_BYTES = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x01, 0x02]);

function wrongCaptchaHtml(message: string): string {
  return `<html><body>
    <input name="txt_cod_antirobo" type="text" id="txt_cod_antirobo" />
    <span id="lbl_invalido">${message}</span>
  </body></html>`;
}

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

  test("throws qr_rejected when SEFAZ refuses the QR payload's signature", async () => {
    const link = validateNfceUrl(VALID_URL);
    const { fetchImpl } = makeStub([html(QR_REJECTED_HTML)]);
    try {
      await fetchReceipt(link, { fetchImpl });
      throw new Error("expected NfceError(qr_rejected)");
    } catch (error) {
      if (!(error instanceof NfceError)) throw error;
      expect(error.code).toBe("qr_rejected");
      expect(error.message).toContain("103 - Identificador de CSC inexistente");
    }
  });
});

describe("fetchReceipt — SVRS (RS)", () => {
  test("gets the QR page, opens the consultation session, and posts the access key", async () => {
    const link = validateNfceUrl(RS_URL);
    const { fetchImpl, calls, at } = makeStub([
      html(RS_SIMPLE_HTML),
      html("<html>consultation form</html>", { setCookie: ["ASP.NET_SessionId=svrs1; path=/; HttpOnly"] }),
      html(FULL_HTML),
    ]);

    const result = await fetchReceipt(link, { fetchImpl });

    expect(result.accessKey).toBe(RS_KEY);
    expect(result.simpleHtml).toContain("tabResult");
    expect(result.fullHtml).toContain("EAN");

    expect(calls).toHaveLength(3);
    expect(at(0).url).toContain("%7C");
    expect(at(0).url).not.toContain("|");

    expect(at(1).method).toBe("GET");
    expect(at(1).url).toBe("https://dfe-portal.svrs.rs.gov.br/Dfe/ConsultaPublicaDfe");

    expect(at(2).method).toBe("POST");
    expect(at(2).url).toBe("https://dfe-portal.svrs.rs.gov.br/Nfce/ConsultaPublicaDfe");
    expect(at(2).body).toContain(`ChaveAcessoDfe=${RS_KEY}`);
    expect(at(2).body).toContain("EhConsultaPublicaSiteSefaz=True");
    expect(at(2).headers.get("cookie")).toContain("ASP.NET_SessionId=svrs1");
  });

  test("throws expired when the QR page has no items table", async () => {
    const link = validateNfceUrl(RS_URL);
    const { fetchImpl } = makeStub([html("<html>documento nao encontrado</html>")]);
    await expectNfce(() => fetchReceipt(link, { fetchImpl }), "expired");
  });

  test("throws unavailable when the consultation returns no products", async () => {
    const link = validateNfceUrl(RS_URL);
    const { fetchImpl } = makeStub([
      html(RS_SIMPLE_HTML),
      html("<html>consultation form</html>"),
      html("<html>captcha wall</html>"),
    ]);
    await expectNfce(() => fetchReceipt(link, { fetchImpl }), "unavailable");
  });
});

describe("fetchReceipt — SP", () => {
  test("fetches only the simplified page and returns an empty detailed page", async () => {
    const link = validateNfceUrl(SP_URL);
    const { fetchImpl, calls, at } = makeStub([html(RS_SIMPLE_HTML)]);

    const result = await fetchReceipt(link, { fetchImpl });

    expect(result.accessKey).toBe(SP_KEY);
    expect(result.simpleHtml).toContain("tabResult");
    expect(result.fullHtml).toBe("");

    expect(calls).toHaveLength(1);
    expect(at(0).url).toContain("%7C");
  });

  test("throws expired when the QR page has no items table", async () => {
    const link = validateNfceUrl(SP_URL);
    const { fetchImpl } = makeStub([html("<html>nota nao encontrada</html>")]);
    await expectNfce(() => fetchReceipt(link, { fetchImpl }), "expired");
  });
});

describe("startKeyConsult", () => {
  test("refuses a key from a portal without the captcha consultation flow", async () => {
    const { fetchImpl, calls } = makeStub([]);
    await expectNfce(() => startKeyConsult(RS_KEY, { fetchImpl }), "unavailable");
    expect(calls).toHaveLength(0);
  });

  test("captures the form session and the captcha image", async () => {
    const { fetchImpl, calls, at } = makeStub([
      html(CONSULT_FORM_HTML, { setCookie: ["ASP.NET_SessionId=key1; path=/; HttpOnly"] }),
      new Response(CAPTCHA_BYTES),
    ]);

    const challenge = await startKeyConsult(VALID_KEY, { fetchImpl });

    expect(calls).toHaveLength(2);
    expect(at(0).url).toContain("NFCEC_consulta_chave_acesso.aspx");
    expect(at(1).url).toContain("AntiRobo/NFCEC_anti_robo.aspx");
    expect(at(1).headers.get("cookie")).toContain("ASP.NET_SessionId=key1");

    expect(challenge.captchaImage).toEqual(CAPTCHA_BYTES);
    expect(challenge.session.accessKey).toBe(VALID_KEY);
    expect(challenge.session.fields.get("__VIEWSTATE")).toBe("vsForm");
  });

  test("rejects a malformed access key without touching the network", async () => {
    const { fetchImpl, calls } = makeStub([]);
    await expectNfce(() => startKeyConsult("123", { fetchImpl }), "invalid_url");
    expect(calls).toHaveLength(0);
  });

  test("throws unavailable when SEFAZ does not serve the form", async () => {
    const { fetchImpl } = makeStub([html("<html>maintenance</html>")]);
    await expectNfce(() => startKeyConsult(VALID_KEY, { fetchImpl }), "unavailable");
  });
});

describe("startKeyConsult — SP", () => {
  test("captures the consultation form (with anti-bot fields) and the captcha image", async () => {
    const { fetchImpl, calls, at } = makeStub([
      html(SP_CONSULT_FORM_HTML, { setCookie: ["ASP.NET_SessionId=sp1; path=/; HttpOnly"] }),
      new Response(CAPTCHA_BYTES),
    ]);

    const challenge = await startKeyConsult(SP_KEY, { fetchImpl });

    expect(calls).toHaveLength(2);
    expect(at(0).url).toBe("https://www.nfce.fazenda.sp.gov.br/NFCeConsultaPublica/Paginas/ConsultaPublica.aspx");
    expect(at(1).url).toContain("Captcha/RandomImageHandler.ashx?r=");
    expect(at(1).headers.get("cookie")).toContain("ASP.NET_SessionId=sp1");
    expect(at(1).headers.get("user-agent")).toContain("Macintosh");

    expect(challenge.captchaImage).toEqual(CAPTCHA_BYTES);
    expect(challenge.session.fields.get("__VIEWSTATE")).toBe("spVs");
    expect(challenge.session.fields.get("ctl00$hdfMsgConfirmacao")).toBe("Deseja prosseguir?");
    expect(challenge.session.fields.has("rAnDoMh0n3yp0t")).toBe(true);
  });
});

describe("completeKeyConsult — SP", () => {
  async function makeSpSession() {
    const { fetchImpl } = makeStub([html(SP_CONSULT_FORM_HTML), new Response(CAPTCHA_BYTES)]);
    return (await startKeyConsult(SP_KEY, { fetchImpl })).session;
  }

  test("posts the key and captcha, then replays the abas postback for the detailed page", async () => {
    const session = await makeSpSession();
    const { fetchImpl, calls, at } = makeStub([html(SP_RESUMIDA_HTML), html(FULL_HTML)]);

    const result = await completeKeyConsult(session, " ab12 ", { fetchImpl });

    expect(result.accessKey).toBe(SP_KEY);
    expect(result.simpleHtml).toContain("tabResult");
    expect(result.fullHtml).toContain("EAN");

    expect(calls).toHaveLength(2);
    expect(at(0).method).toBe("POST");
    expect(at(0).url).toContain("ConsultaPublica.aspx");
    expect(at(0).body).toContain(`txtChaveAcesso=${SP_KEY}`);
    expect(at(0).body).toContain("txCodigo=ab12");
    expect(at(0).body).toContain("btnConsultaResumida=Consultar");
    expect(at(0).body).toContain("rAnDoMh0n3yp0t=");

    expect(at(1).method).toBe("POST");
    expect(at(1).url).toContain("ConsultaResponsiva/ConsultaResumidaRJFrame_v400.aspx");
    expect(at(1).body).toContain("__EVENTTARGET=btnVisualizarAbas");
    expect(at(1).body).toContain("__VIEWSTATE=spVs2");
  });

  test("throws captcha_rejected on SP's error dialog", async () => {
    const session = await makeSpSession();
    const { fetchImpl } = makeStub([html(SP_WRONG_CAPTCHA_HTML)]);
    await expectNfce(() => completeKeyConsult(session, "WRONG", { fetchImpl }), "captcha_rejected");
  });
});

describe("completeKeyConsult", () => {
  async function makeSession() {
    const { fetchImpl } = makeStub([html(CONSULT_FORM_HTML), new Response(CAPTCHA_BYTES)]);
    return (await startKeyConsult(VALID_KEY, { fetchImpl })).session;
  }

  test("posts the key and captcha, then walks the detail flow", async () => {
    const session = await makeSession();
    const { fetchImpl, calls, at } = makeStub([html(SIMPLE_HTML), html("<html>postback</html>"), html(FULL_HTML)]);

    const result = await completeKeyConsult(session, " ab12 ", { fetchImpl });

    expect(result.accessKey).toBe(VALID_KEY);
    expect(result.fullHtml).toContain("EAN");

    expect(calls).toHaveLength(3);
    expect(at(0).method).toBe("POST");
    expect(at(0).url).toContain("NFCEC_consulta_chave_acesso.aspx");
    expect(at(0).body).toContain(`txt_chave_acesso=${VALID_KEY}`);
    expect(at(0).body).toContain("txt_cod_antirobo=ab12");
    expect(at(0).body).toContain("btn_consulta_completa=Consultar");
    expect(at(0).body).toContain("__VIEWSTATE=vsForm");
    expect(at(1).url).toContain("NFCEC_consulta_danfe.aspx");
    expect(at(2).url).toContain("Frm_Imprimir_parcial.aspx");
  });

  test("throws captcha_rejected when the answer is wrong", async () => {
    const session = await makeSession();
    const { fetchImpl } = makeStub([html(wrongCaptchaHtml("Código incorreto tente novamente"))]);
    await expectNfce(() => completeKeyConsult(session, "WRONG", { fetchImpl }), "captcha_rejected");
  });

  test("throws expired when the portal does not know the key", async () => {
    const session = await makeSession();
    const { fetchImpl } = makeStub([
      html(wrongCaptchaHtml("No momento, esta Nota Fiscal de Consumidor não foi encontrada na base.")),
    ]);
    await expectNfce(() => completeKeyConsult(session, "AB12", { fetchImpl }), "expired");
  });

  test("throws unavailable on an unrecognized refusal", async () => {
    const session = await makeSession();
    const { fetchImpl } = makeStub([html(wrongCaptchaHtml("Sistema em manutenção"))]);
    await expectNfce(() => completeKeyConsult(session, "AB12", { fetchImpl }), "unavailable");
  });
});
