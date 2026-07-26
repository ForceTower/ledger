import { describe, expect, test } from "bun:test";
import { categorize } from "../src/categorize";

describe("categorize", () => {
  test("matches Portuguese keywords to English categories", () => {
    expect(categorize("BACON FATIADO SEARA")).toBe("meat");
    expect(categorize("ARROZ BRANCO 5KG")).toBe("grocery");
    expect(categorize("LEITE INTEGRAL")).toBe("dairy_deli");
  });

  test("falls back to other when nothing matches", () => {
    expect(categorize("XYZ PRODUTO DESCONHECIDO")).toBe("other");
    expect(categorize("ITENS DIVERSOS")).toBe("other");
  });

  test("a longer phrase beats the single words inside it", () => {
    // "leite coco" (grocery) beats "leite"; "leite ferm" (dairy_deli) beats "ferm" (grocery)
    expect(categorize("LEITE COCO SOCOCO")).toBe("grocery");
    expect(categorize("LEITE FERM ACTIVIA")).toBe("dairy_deli");
    // "barra cereais" (snacks_sweets) beats "cereais"; "sco plast" (household) beats "saco"
    expect(categorize("BARRA CEREAIS NUTRY")).toBe("snacks_sweets");
    expect(categorize("SCO PLAST.ZIP P.")).toBe("household");
    // "agua sanit" (cleaning) beats "agua" (beverages)
    expect(categorize("AGUA SANIT YPE 2L")).toBe("cleaning");
  });

  test("matches whole words across punctuation and accents", () => {
    expect(categorize("BISC.L.MALTADO")).toBe("snacks_sweets");
    expect(categorize("QJO PARMESAO BURITI")).toBe("dairy_deli");
    expect(categorize("ABÓBORA JAP/CABOTIA")).toBe("produce");
    expect(categorize("JERKEED B.DIANTEIRO")).toBe("meat");
  });

  test("the product noun leading the line outranks a trailing qualifier", () => {
    // Receipts lead with the noun and trail with brand, size and flavour, so the head wins.
    expect(categorize("DET LIQ YPE 500ML CAP LIMAO")).toBe("cleaning");
    expect(categorize("CIF CREM 450ML LIMAO")).toBe("cleaning");
    expect(categorize("SAL PAR CG 500G ALHO")).toBe("grocery");
    expect(categorize("PAO DE LEITE GB KG KG")).toBe("bakery");
    expect(categorize("BOLACH MANT PAL 200G")).toBe("snacks_sweets");
    expect(categorize("PEG SILIC C INOX ASA")).toBe("household");
    expect(categorize("FARINHA DE BERINJELA")).toBe("grocery");
    // ...but a keyword anywhere still beats no keyword at all.
    expect(categorize("CROCK VITAR 350G PAO")).toBe("bakery");
    expect(categorize("MOR CONG UNI 1,002kg")).toBe("frozen");
  });

  test("a brand outranks a misleading generic noun", () => {
    expect(categorize("TOMATE POMAROLA 400G")).toBe("grocery");
    expect(categorize("MANT C SAL DAVACA 500G")).toBe("dairy_deli");
    expect(categorize("POLPA DANONE 510G MGO")).toBe("dairy_deli");
    expect(categorize("MOLICO 280G TOT CALCIO")).toBe("dairy_deli");
    expect(categorize("CR PANT 240G BAMBU")).toBe("hygiene");
  });

  test("strips the internal code and NCM some issuers prefix onto the description", () => {
    expect(categorize("#1700300#18063210#TAB BC 55% 20")).toBe("snacks_sweets");
    expect(categorize("#1700900#18069000#TRU PIST 13,5 LC")).toBe("snacks_sweets");
    // The prefix must not shift the head, or "pimenta" would win over "tab".
    expect(categorize("#1700300#18063210#TAB PIMENTA 20")).toBe("snacks_sweets");
  });

  test("resolves the abbreviations receipts actually print", () => {
    expect(categorize("QJ PRATO DAVACA FT")).toBe("dairy_deli");
    expect(categorize("RQ NESTLE 200G LIGHT")).toBe("dairy_deli");
    expect(categorize("LTE INT NINHO 1L")).toBe("dairy_deli");
    expect(categorize("FIGAD RES BIG CAR FC")).toBe("meat");
    expect(categorize("POST TILAP COPAC 800")).toBe("meat");
    expect(categorize("CORAC PERDIG 1kg")).toBe("meat");
    expect(categorize("AG INDAIA C/G 500ML")).toBe("beverages");
    expect(categorize("S UVA TINT GER 1,35L")).toBe("beverages");
    expect(categorize("F T FINNA VIT PL 1kg")).toBe("grocery");
    expect(categorize("GRAO BICO KILC 500G")).toBe("grocery");
    expect(categorize("ESP SCT BRT AZ L3P2")).toBe("cleaning");
    expect(categorize("ALC SOL 46 1L EUCALI")).toBe("cleaning");
    expect(categorize("DES HORT QUALI 350ML")).toBe("cleaning");
    expect(categorize("TOAL PAP GOURM 110FL")).toBe("cleaning");
    expect(categorize("PH SUPRA FT 20M C/12")).toBe("hygiene");
    expect(categorize("SBT GRANADO 90G CAMO")).toBe("hygiene");
    expect(categorize("CD COLG PRO A 90G OR")).toBe("hygiene");
    expect(categorize("D OLD SPIC 200ML VIP")).toBe("hygiene");
    expect(categorize("P MANT WYDA 29X7,5")).toBe("household");
    expect(categorize("FOSF FIAT LUX C/200")).toBe("household");
    expect(categorize("ASSAD OPALINE OVAL G")).toBe("household");
  });

  test("keeps desinfetante and desodorante apart", () => {
    expect(categorize("DES HORT QUALI 350ML")).toBe("cleaning");
    expect(categorize("D HAR 750ML MAR L+P-")).toBe("cleaning");
    expect(categorize("DESOD CREM HERBISSIMO 55G TRAD")).toBe("hygiene");
    expect(categorize("D ABOVE 150G CANDY")).toBe("hygiene");
  });
});
