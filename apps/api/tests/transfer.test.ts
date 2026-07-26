import { describe, expect, test } from "bun:test";
import { type Candidate, nearestInTime, transferExtractionSchema } from "../src/service/transfer";

const extraction = {
  status: "transfer",
  transactionId: "E60701190202607241420abc",
  type: "pix",
  amount: 128.4,
  date: "2026-07-24",
  time: "14:20:00",
  destination: { name: "MERCADO BOM PRECO LTDA", institution: "Banco do Brasil", agency: "3054", account: "····8821" },
  origin: { name: "Joao Sena", institution: "Nubank", agency: "0001", account: "····1234" },
  category: "grocery",
  comment: "",
};

describe("transfer extraction schema", () => {
  test("accepts a full reading", () => {
    const parsed = transferExtractionSchema.parse(extraction);
    expect(parsed).toMatchObject({ status: "transfer", amount: 128.4 });
  });

  test("accepts a receipt that says nothing beyond the destination", () => {
    const parsed = transferExtractionSchema.parse({
      ...extraction,
      time: null,
      origin: null,
      destination: { name: "PADARIA CENTRAL", institution: null, agency: null, account: null },
    });
    expect(parsed).toMatchObject({ time: null, origin: null });
  });

  test("accepts a refusal", () => {
    const parsed = transferExtractionSchema.parse({ status: "not_a_transfer", comment: "É uma fatura." });
    expect(parsed.status).toBe("not_a_transfer");
  });

  // The model is told to answer with a number; "R$ 128,40" as a string would silently become NaN
  // money downstream, so it has to fail the contract instead.
  test("rejects an amount that is not a number", () => {
    expect(transferExtractionSchema.safeParse({ ...extraction, amount: "128,40" }).success).toBe(false);
  });

  test("rejects a non-positive amount", () => {
    expect(transferExtractionSchema.safeParse({ ...extraction, amount: 0 }).success).toBe(false);
  });

  test("rejects a date or time in the wrong shape", () => {
    expect(transferExtractionSchema.safeParse({ ...extraction, date: "24/07/2026" }).success).toBe(false);
    expect(transferExtractionSchema.safeParse({ ...extraction, time: "14:20" }).success).toBe(false);
  });

  test("rejects a category outside the contract", () => {
    expect(transferExtractionSchema.safeParse({ ...extraction, category: "mercado" }).success).toBe(false);
  });

  test("rejects an empty transaction id", () => {
    expect(transferExtractionSchema.safeParse({ ...extraction, transactionId: "" }).success).toBe(false);
  });
});

function candidate(slug: string, time: string | null): Candidate {
  return { slug, date: "2026-07-24", time, paidTotal: 128.4, itemCount: 12, storeName: "Bom Preço" };
}

describe("nearestInTime", () => {
  test("no candidates means no match", () => {
    expect(nearestInTime([], "14:20:00")).toBeUndefined();
  });

  test("a single candidate wins regardless of time", () => {
    expect(nearestInTime([candidate("a", null)], "14:20:00")?.slug).toBe("a");
  });

  // Two notes for the same amount on the same day: the one rung up next to the transfer is the one.
  test("picks the purchase closest to the transfer's time", () => {
    const candidates = [
      candidate("morning", "09:05:00"),
      candidate("closest", "14:18:22"),
      candidate("night", "21:40:00"),
    ];
    expect(nearestInTime(candidates, "14:20:00")?.slug).toBe("closest");
  });

  test("a candidate without a time loses to one that has it", () => {
    expect(nearestInTime([candidate("untimed", null), candidate("timed", "23:00:00")], "14:20:00")?.slug).toBe("timed");
  });

  test("without a time on the transfer the latest purchase wins", () => {
    const candidates = [candidate("early", "09:05:00"), candidate("late", "21:40:00")];
    expect(nearestInTime(candidates, null)?.slug).toBe("late");
  });
});
