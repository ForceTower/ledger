import type { Category } from "@ledger/shared-types";

// NFC-e item descriptions are Portuguese, so the keywords stay Portuguese; the returned category is
// English. Rule: de-accent, match on whole words, longest matching keyword wins.
//
// TODO: port the full ruleset from the prototype's categorize.py (this is a representative starter).
const RULES: Record<Category, string[]> = {
  produce: ["banana", "tomate", "cebola", "batata", "alface", "maca", "laranja", "cenoura"],
  meat: ["bov", "frango", "carne", "linguica", "bacon", "file", "suino", "peixe"],
  dairy_deli: ["leite", "queijo", "iogurte", "manteiga", "presunto", "requeijao", "mussarela"],
  bakery: ["pao", "bolo", "biscoito", "torrada"],
  grocery: ["arroz", "feijao", "acucar", "oleo", "macarrao", "cafe", "sal", "farinha", "molho"],
  beverages: ["refrigerante", "suco", "agua", "cerveja", "vinho", "energetico"],
  snacks_sweets: ["chocolate", "bala", "salgadinho", "doce", "chiclete"],
  frozen: ["congelado", "sorvete", "pizza", "nuggets"],
  cleaning: ["detergente", "sabao", "amaciante", "desinfetante", "agua sanitaria", "esponja"],
  hygiene: ["sabonete", "shampoo", "creme dental", "papel higienico", "fralda", "absorvente"],
  pet: ["racao", "petisco"],
  household: ["pilha", "lampada", "copo", "prato", "guardanapo"],
  other: [],
};

function deaccent(text: string): string {
  return text.normalize("NFKD").replace(/[\u0300-\u036f]/g, "");
}

export function categorize(description: string): Category {
  const haystack = ` ${deaccent(description).toLowerCase()} `;
  let best: { category: Category; length: number } | null = null;
  for (const [category, keywords] of Object.entries(RULES) as [Category, string[]][]) {
    for (const keyword of keywords) {
      if (haystack.includes(` ${keyword} `) && (!best || keyword.length > best.length)) {
        best = { category, length: keyword.length };
      }
    }
  }
  return best?.category ?? "other";
}
