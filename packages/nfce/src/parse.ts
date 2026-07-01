import { type HTMLElement, parse } from "node-html-parser";
import { categorize } from "./categorize";
import type { ParsedItem, ParsedReceipt } from "./index";

/**
 * Parse the simplified + detailed receipt HTML into a structured, categorized purchase.
 *
 * Ported from the prototype's parse_nfce.py. Items, totals, payments and metadata come from the
 * simplified page; the detailed (print) page only adds the EAN bar code per item. The parser never
 * throws on inconsistent data — mismatches are surfaced through `warnings` so a flagged purchase is
 * still usable.
 */
export function parseReceipt(simpleHtml: string, fullHtml: string): ParsedReceipt {
  const root = parse(simpleHtml);

  const items = parseItems(root);
  attachBarcodes(items, fullHtml);

  const totals = parseTotals(root);
  const payments = parsePayments(root);
  if (payments.length === 1 && payments[0]!.code === 1 && payments[0]!.amount > totals.totalPaid) {
    payments[0]!.change = round2(payments[0]!.amount - totals.totalPaid);
  }
  const meta = parseMeta(simpleHtml);

  return {
    source: "nfce",
    date: meta.date,
    time: meta.time,
    store: parseStore(root),
    receipt: { number: meta.number, series: meta.series, accessKey: meta.accessKey },
    items,
    totals,
    payments,
    taxesTotal: meta.taxesTotal,
    warnings: collectWarnings(items, totals, meta.accessKey),
  };
}

/** BRL money: "1.234,56" -> 1234.56 (dot groups thousands, comma is the decimal). */
function parseMoney(value: string): number {
  return Number(value.replace(/\./g, "").replace(",", "."));
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/** Decoded text with collapsed whitespace; "" when the node is absent. */
function textOf(node: HTMLElement | null | undefined): string {
  return node ? node.text.replace(/\s+/g, " ").trim() : "";
}

/** The trailing number of a label+value blob, e.g. "Qtde.:0,816" -> "0,816". */
function trailingNumber(text: string): string {
  return /([\d.,]+)\s*$/.exec(text)?.[1] ?? "";
}

function parseItems(root: HTMLElement): ParsedItem[] {
  return root.querySelectorAll('tr[id^="Item"]').map((row, index) => {
    const description = textOf(row.querySelector("span.txtTit"));
    const qty = trailingNumber(textOf(row.querySelector(".Rqtd")));
    const unitPrice = trailingNumber(textOf(row.querySelector(".RvlUnit")));
    const total = textOf(row.querySelector(".valor"));
    return {
      seq: index + 1,
      description,
      code: /C[oó]digo:\s*([^)]+)\)/.exec(textOf(row.querySelector(".RCod")))?.[1]?.trim() ?? "",
      barcode: null,
      quantity: qty ? parseMoney(qty) : 0,
      unit: textOf(row.querySelector(".RUN")).replace(/^.*?:\s*/, ""),
      unitPrice: unitPrice ? parseMoney(unitPrice) : 0,
      total: total ? parseMoney(total) : 0,
      category: categorize(description),
    };
  });
}

/**
 * The detailed page lists products in receipt order, so matching the EAN by position is the primary
 * strategy; the code -> EAN map is only a fallback when the two counts differ.
 */
function attachBarcodes(items: ParsedItem[], fullHtml: string): void {
  const codes = [...fullHtml.matchAll(/C[oó]digo do Produto<\/label>\s*<span[^>]*>([^<]+)<\/span>/g)].map((match) =>
    match[1]!.trim(),
  );
  const eans = [...fullHtml.matchAll(/C[oó]digo EAN Comercial<\/label>\s*<span[^>]*>([^<]*)<\/span>/g)].map((match) =>
    cleanBarcode(match[1]!),
  );

  if (eans.length === items.length) {
    items.forEach((item, index) => {
      item.barcode = eans[index] ?? null;
    });
    return;
  }

  const codeMap = new Map<string, string | null>();
  codes.forEach((code, index) => {
    if (!codeMap.has(code)) codeMap.set(code, eans[index] ?? null);
  });
  for (const item of items) {
    item.barcode = codeMap.get(item.code) ?? null;
  }
}

function cleanBarcode(raw: string): string | null {
  const ean = raw.trim();
  return /^\d{8,14}$/.test(ean) ? ean : null;
}

function parseStore(root: HTMLElement): ParsedReceipt["store"] {
  const legalName = textOf(root.querySelector(".txtTopo"));
  const texts = root.querySelectorAll(".txtCenter .text").map(textOf);
  const cnpjText = texts.find((text) => /CNPJ/i.test(text)) ?? "";
  const addressText = texts.find((text) => !/CNPJ/i.test(text));
  return {
    name: legalName,
    legalName,
    cnpj: /CNPJ:\s*([\d./-]+)/.exec(cnpjText)?.[1] ?? null,
    address: addressText ? titleAddress(addressText) : null,
  };
}

const ADDRESS_CONNECTORS = new Set(["da", "de", "do", "das", "dos", "e"]);

/**
 * Match the dataset's address style: Title Case, lowercase connectors, and an uppercase trailing UF
 * (the two-letter state code is the last token).
 */
function titleAddress(address: string): string {
  const parts = address
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
  return parts
    .map((part, partIndex) => {
      const words = part.split(/\s+/);
      return words
        .map((word, wordIndex) => {
          const lower = word.toLowerCase();
          const isFirst = partIndex === 0 && wordIndex === 0;
          const isLast = partIndex === parts.length - 1 && wordIndex === words.length - 1;
          if (ADDRESS_CONNECTORS.has(lower) && !isFirst) return lower;
          if (isLast && /^[a-z]{2}$/i.test(word)) return word.toUpperCase();
          return word.charAt(0).toUpperCase() + lower.slice(1);
        })
        .join(" ");
    })
    .join(", ");
}

function parseTotals(root: HTMLElement): ParsedReceipt["totals"] {
  const values = new Map<string, string>();
  for (const row of root.querySelectorAll('[id="linhaTotal"]')) {
    const label = textOf(row.querySelector("label"));
    if (label && !values.has(label)) values.set(label, textOf(row.querySelector("span")));
  }
  const qty = values.get("Qtd. total de itens:");
  const gross = values.get("Valor total R$:");
  const discount = values.get("Descontos R$:");
  const paid = values.get("Valor a pagar R$:");
  // Receipts with no discount omit the "Valor total" and "Descontos" lines entirely.
  const totalPaid = paid ? parseMoney(paid) : 0;
  return {
    itemCount: qty ? Math.trunc(parseMoney(qty)) : 0,
    gross: gross ? parseMoney(gross) : totalPaid,
    discount: discount ? parseMoney(discount) : 0,
    totalPaid,
  };
}

function parsePayments(root: HTMLElement): ParsedReceipt["payments"] {
  const payments: ParsedReceipt["payments"] = [];
  for (const label of root.querySelectorAll("label.tx")) {
    const match = /^\s*(\d+)\s*-\s*(.+?)\s*$/.exec(textOf(label));
    if (!match) continue;
    payments.push({
      code: Number(match[1]),
      method: match[2]!,
      amount: parseMoney(textOf(label.nextElementSibling)),
    });
  }
  return payments;
}

function parseMeta(simpleHtml: string) {
  const accessKey = (/class="chave">([\d\s]{44,80})/.exec(simpleHtml)?.[1] ?? "").replace(/\D/g, "");

  let number = /N[uú]mero:\s*<\/strong>\s*(\d+)/.exec(simpleHtml)?.[1] ?? null;
  let series = /S[eé]rie:\s*<\/strong>\s*(\d+)/.exec(simpleHtml)?.[1] ?? null;
  if (accessKey.length === 44) {
    number ??= String(Number(accessKey.slice(25, 34)));
    series ??= String(Number(accessKey.slice(22, 25)));
  }

  const emission = /Emiss[ãa]o:\s*<\/strong>\s*(\d{2})\/(\d{2})\/(\d{4})\s+(\d{2}:\d{2}:\d{2})/.exec(simpleHtml);

  const taxes =
    /Tributos[^<]*<\/label>\s*<span[^>]*>\s*R?\$?\s*([\d.,]+)/.exec(simpleHtml)?.[1] ??
    /[Tt]ributos[^R]{0,60}R\$\s*([\d.,]+)/.exec(simpleHtml)?.[1] ??
    null;

  return {
    accessKey,
    number: number ? Number(number) : null,
    series: series ? Number(series) : null,
    date: emission ? `${emission[3]}-${emission[2]}-${emission[1]}` : "",
    time: emission?.[4] ?? "",
    taxesTotal: taxes ? parseMoney(taxes) : null,
  };
}

function collectWarnings(items: ParsedItem[], totals: ParsedReceipt["totals"], accessKey: string): string[] {
  const warnings: string[] = [];
  if (items.length !== totals.itemCount) {
    warnings.push(`parsed ${items.length} items but receipt total says ${totals.itemCount}`);
  }
  const itemsSum = round2(items.reduce((sum, item) => sum + item.total, 0));
  if (Math.abs(itemsSum - totals.gross) > 0.05) {
    warnings.push(`item sum ${itemsSum.toFixed(2)} does not match gross total ${totals.gross.toFixed(2)}`);
  }
  if (!/^\d{44}$/.test(accessKey)) {
    warnings.push("access key is missing or not 44 digits");
  }
  return warnings;
}
