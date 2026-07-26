import { describe, expect, test } from "bun:test";
import { LedgerError } from "../src/error";
import type { AiRequest, AiResponse, AiRunner } from "../src/service/ai";
import { EntryService } from "../src/service/entry";

const reading = {
  status: "entry",
  date: "2026-07-24",
  time: null,
  store: null,
  paymentMethod: null,
  items: [{ description: "Transporte", category: "transport", quantity: 1, unitPrice: 37 }],
  comment: "Considerei 24 de julho deste ano.",
};

/** Answers with whatever the test scripted, and remembers what it was asked. */
function stubAi(answer: unknown): AiRunner & { requests: AiRequest[] } {
  const requests: AiRequest[] = [];
  return {
    requests,
    model: "stub",
    async run(request: AiRequest): Promise<AiResponse> {
      requests.push(request);
      return {
        text: typeof answer === "string" ? answer : JSON.stringify(answer),
        usage: { inputTokens: 0, outputTokens: 0, costUsd: undefined },
        transport: "api",
      };
    },
    parse(text, schema) {
      return schema.parse(JSON.parse(text));
    },
  };
}

/** `answer` is the union the model picks; the wire shape nests it under `result`. */
function makeService(answer: unknown, now = new Date("2026-07-26T12:00:00Z")) {
  const ai = stubAi({ result: answer });
  return {
    ai,
    service: new EntryService({ ai, prompt: "read it", timeZone: "America/Bahia", now: () => now }),
  };
}

describe("EntryService", () => {
  test("the description reaches the prompt and comes back as a draft", async () => {
    const { ai, service } = makeService(reading);
    const draft = await service.interpret({ text: "37,00 de transporte no dia 24 de julho" });

    expect(draft.date).toBe("2026-07-24");
    expect(draft.items).toEqual([{ description: "Transporte", category: "transport", quantity: 1, unitPrice: 37 }]);
    expect(ai.requests[0]?.instructions).toContain("37,00 de transporte no dia 24 de julho");
    expect(ai.requests[0]?.image).toBeUndefined();
  });

  // Without this the model resolves "ontem" against its training cutoff, not the owner's calendar.
  test("the owner's today is in the prompt, in the ledger's timezone", async () => {
    // 01:30 UTC is still the 25th in Bahia (UTC-3).
    const { ai, service } = makeService(reading, new Date("2026-07-26T01:30:00Z"));
    await service.interpret({ text: "37 de transporte ontem" });

    expect(ai.requests[0]?.instructions).toContain("Today is 2026-07-25");
    expect(ai.requests[0]?.instructions).toContain("America/Bahia");
  });

  test("an empty description is a bad request, not an AI call", async () => {
    const { ai, service } = makeService(reading);
    try {
      await service.interpret({ text: "   " });
      throw new Error("expected a rejection");
    } catch (error) {
      expect((error as LedgerError).errorCode).toBe("invalid_input");
      expect((error as LedgerError).statusCode).toBe(400);
    }
    expect(ai.requests).toHaveLength(0);
  });

  test("text that is not about spending comes back as not_an_entry", async () => {
    const { service } = makeService({ status: "not_an_entry", comment: "Isso parece uma lista de compras." });
    try {
      await service.interpret({ text: "comprar pão amanhã" });
      throw new Error("expected a rejection");
    } catch (error) {
      expect((error as LedgerError).errorCode).toBe("not_an_entry");
      expect((error as LedgerError).statusCode).toBe(422);
      expect((error as LedgerError).message).toBe("Isso parece uma lista de compras.");
    }
  });

  test("several things in one sentence are several items", async () => {
    const { service } = makeService({
      ...reading,
      items: [
        { description: "Transporte", category: "transport", quantity: 1, unitPrice: 37 },
        { description: "Pão francês", category: "bakery", quantity: 1, unitPrice: 20 },
      ],
    });
    const draft = await service.interpret({ text: "37 de transporte e 20 de padaria" });
    expect(draft.items).toHaveLength(2);
    expect(draft.items[1]?.category).toBe("bakery");
  });

  // Structured outputs cannot carry min/max, so the service is what keeps nonsense out of the draft.
  test("nonsense prices and counts drop to null instead of failing the read", async () => {
    const { service } = makeService({
      ...reading,
      items: [{ description: "Transporte", category: "transport", quantity: 2.5, unitPrice: -3 }],
    });
    const draft = await service.interpret({ text: "transporte" });
    expect(draft.items[0]).toMatchObject({ quantity: null, unitPrice: null });
  });

  test("an over-precise price is rounded to cents", async () => {
    const { service } = makeService({
      ...reading,
      items: [{ description: "Transporte", category: "transport", quantity: 1, unitPrice: 37.00000000000001 }],
    });
    const draft = await service.interpret({ text: "transporte" });
    expect(draft.items[0]?.unitPrice).toBe(37);
  });

  test("a store the description never named stays null", async () => {
    const { service } = makeService({ ...reading, store: "  " });
    expect((await service.interpret({ text: "transporte" })).store).toBeNull();
  });

  test("the words win over an attached image, and the prompt says so", async () => {
    const { ai, service } = makeService(reading);
    await service.interpret({ text: "37 de transporte" });
    expect(ai.requests[0]?.instructions).toContain("the words win");
  });
});
