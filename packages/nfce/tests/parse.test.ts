import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { parseReceipt } from "../src/index";

const FIXTURES = join(import.meta.dir, "fixtures");

function loadFixture(stem: string) {
  const simple = readFileSync(join(FIXTURES, `${stem}.simple.html`), "utf-8");
  const full = readFileSync(join(FIXTURES, `${stem}.full.html`), "utf-8");
  const expected = JSON.parse(readFileSync(join(FIXTURES, `${stem}.json`), "utf-8"));
  return { simple, full, expected };
}

const FIXTURE_STEMS = ["supermarket_weighted", "cash_with_change", "split_payment"];

describe("parseReceipt — fixture equivalence", () => {
  for (const stem of FIXTURE_STEMS) {
    test(`${stem} matches the expected snapshot`, () => {
      const { simple, full, expected } = loadFixture(stem);
      expect(parseReceipt(simple, full)).toEqual(expected);
    });
  }
});

describe("parseReceipt — items and bar codes", () => {
  test("matches EAN by position and leaves weighed items without a bar code", () => {
    const { simple, full } = loadFixture("supermarket_weighted");
    const receipt = parseReceipt(simple, full);

    expect(receipt.items[0]!.barcode).toBe("7896300501094");

    const weighed = receipt.items.find((item) => item.unit === "KG9");
    expect(weighed?.barcode).toBeNull();
    expect(weighed?.quantity).toBeCloseTo(0.816, 3); // preserved, not rounded to 2 decimals
  });

  test("leaves bar codes null when the detailed page is empty", () => {
    const { simple } = loadFixture("supermarket_weighted");
    const receipt = parseReceipt(simple, "");
    expect(receipt.items.every((item) => item.barcode === null)).toBe(true);
  });

  test("falls back to the code→EAN map when the counts differ", () => {
    const simple = `<html><body>
      <table>
        <tr id="Item + 1"><td><span class="txtTit">ARROZ</span><span class="RCod">(Código: A1)</span>
          <span class="Rqtd"><strong>Qtde.:</strong>1</span><span class="RUN"><strong>UN: </strong>UND</span>
          <span class="RvlUnit"><strong>Vl. Unit.:</strong>5,00</span></td>
          <td class="txtTit noWrap">Vl. Total<br><span class="valor">5,00</span></td></tr>
        <tr id="Item + 2"><td><span class="txtTit">FEIJAO</span><span class="RCod">(Código: A2)</span>
          <span class="Rqtd"><strong>Qtde.:</strong>1</span><span class="RUN"><strong>UN: </strong>UND</span>
          <span class="RvlUnit"><strong>Vl. Unit.:</strong>5,00</span></td>
          <td class="txtTit noWrap">Vl. Total<br><span class="valor">5,00</span></td></tr>
      </table></body></html>`;
    // Three pairs but only two items, and in a different order — forces the code→EAN map fallback.
    const full = `<html><body>
      <label>Código do Produto</label><span>A2</span><label>Código EAN Comercial</label><span>7890000000002</span>
      <label>Código do Produto</label><span>A1</span><label>Código EAN Comercial</label><span>7890000000001</span>
      <label>Código do Produto</label><span>A3</span><label>Código EAN Comercial</label><span>7890000000003</span>
      </body></html>`;

    const receipt = parseReceipt(simple, full);
    expect(receipt.items.map((item) => item.barcode)).toEqual(["7890000000001", "7890000000002"]);
  });
});

describe("parseReceipt — totals and payments", () => {
  test("computes change for a single cash payment over the total", () => {
    const { simple, full } = loadFixture("cash_with_change");
    const receipt = parseReceipt(simple, full);
    expect(receipt.payments).toHaveLength(1);
    expect(receipt.payments[0]).toMatchObject({ code: 1, method: "Dinheiro", change: 65.81 });
  });

  test("uses the paid amount as gross on receipts without a discount", () => {
    const { simple, full } = loadFixture("cash_with_change");
    const receipt = parseReceipt(simple, full);
    expect(receipt.totals.discount).toBe(0);
    expect(receipt.totals.gross).toBe(receipt.totals.totalPaid);
  });

  test("keeps every split payment and adds no change", () => {
    const { simple, full } = loadFixture("split_payment");
    const receipt = parseReceipt(simple, full);
    expect(receipt.payments).toHaveLength(2);
    expect(receipt.payments.every((payment) => payment.change === undefined)).toBe(true);
  });
});

describe("parseReceipt — metadata", () => {
  test("derives the receipt number and series from the access key when not printed", () => {
    // key[22:25] = "042" -> series 42, key[25:34] = "000001234" -> number 1234
    const key = "29260311222333000181650420000012340000000000";
    const simple = `<html><body>
      <table>
        <tr id="Item + 1"><td><span class="txtTit">ARROZ</span><span class="RCod">(Código: A1)</span>
          <span class="Rqtd"><strong>Qtde.:</strong>1</span><span class="RUN"><strong>UN: </strong>UND</span>
          <span class="RvlUnit"><strong>Vl. Unit.:</strong>10,00</span></td>
          <td class="txtTit noWrap">Vl. Total<br><span class="valor">10,00</span></td></tr>
      </table>
      <div id="totalNota">
        <div id="linhaTotal"><label>Qtd. total de itens:</label><span>1</span></div>
        <div id="linhaTotal"><label>Valor a pagar R$:</label><span>10,00</span></div>
        <div id="linhaTotal"><label class="tx">10 - Vale Alimentação</label><span>10,00</span></div>
      </div>
      <strong>Emissão: </strong>15/06/2026 09:30:00-03:00
      <span class="chave">${key.replace(/(.{4})/g, "$1 ").trim()}</span>
      </body></html>`;

    const receipt = parseReceipt(simple, "");
    expect(receipt.receipt.accessKey).toBe(key);
    expect(receipt.receipt.series).toBe(42);
    expect(receipt.receipt.number).toBe(1234);
    expect(receipt.date).toBe("2026-06-15");
    expect(receipt.time).toBe("09:30:00");
    expect(receipt.warnings).toEqual([]);
  });

  test("warns about inconsistent receipts instead of throwing", () => {
    const simple = `<html><body>
      <table>
        <tr id="Item + 1"><td><span class="txtTit">ARROZ</span><span class="RCod">(Código: A1)</span>
          <span class="Rqtd"><strong>Qtde.:</strong>1</span><span class="RUN"><strong>UN: </strong>UND</span>
          <span class="RvlUnit"><strong>Vl. Unit.:</strong>5,00</span></td>
          <td class="txtTit noWrap">Vl. Total<br><span class="valor">5,00</span></td></tr>
      </table>
      <div id="totalNota">
        <div id="linhaTotal"><label>Qtd. total de itens:</label><span>2</span></div>
        <div id="linhaTotal"><label>Valor total R$:</label><span>99,00</span></div>
        <div id="linhaTotal"><label>Valor a pagar R$:</label><span>99,00</span></div>
      </div></body></html>`;

    const receipt = parseReceipt(simple, "");
    expect(receipt.warnings.length).toBe(3); // item count, item sum, and missing access key
  });
});
