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
  });

  test("longest matching keyword wins", () => {
    // "leite coco" (grocery) beats "leite" (dairy_deli); "leite ferm" (dairy_deli) beats "ferm" (grocery)
    expect(categorize("LEITE COCO SOCOCO")).toBe("grocery");
    expect(categorize("LEITE FERM ACTIVIA")).toBe("dairy_deli");
    // "barra cereais" (snacks_sweets) beats "cereais"; "sco plast" (household) beats "saco"
    expect(categorize("BARRA CEREAIS NUTRY")).toBe("snacks_sweets");
    expect(categorize("SCO PLAST.ZIP P.")).toBe("household");
  });

  test("matches whole words across punctuation and accents", () => {
    expect(categorize("BISC.L.MALTADO")).toBe("snacks_sweets");
    expect(categorize("QJO PARMESAO BURITI")).toBe("dairy_deli");
    expect(categorize("ABÓBORA JAP/CABOTIA")).toBe("produce");
    expect(categorize("JERKEED B.DIANTEIRO")).toBe("meat");
  });
});
