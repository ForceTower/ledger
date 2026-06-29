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
});
