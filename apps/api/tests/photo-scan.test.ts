import type { PhotoScanItem } from "@ledger/shared-types";
import { describe, expect, test } from "bun:test";
import type { AiRequest, AiResponse, AiRunner } from "../src/service/ai";
import type { AiSpend } from "../src/service/ai-spend";
import { PhotoScanService } from "../src/service/photo-scan";

// FF D8 FF is the JPEG signature validateImage sniffs for.
const jpeg = new File([new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00])], "photo.jpg");

const item: PhotoScanItem = {
  description: "Café Torrado e Moído 500g",
  category: "grocery",
  confidence: 0.92,
  unitPrice: 18.9,
  quantity: 2,
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

/** `answer` is the union the model picks; the wire shape nests it under `result` (see the service). */
function makeService(answer: unknown) {
  const ai = stubAi({ result: answer });
  return { ai, service: new PhotoScanService({ ai, prompt: "identify it" }) };
}

describe("PhotoScanService", () => {
  test("passes through the price and quantity the model read", async () => {
    const { service } = makeService({ status: "identified", items: [item], comment: "" });

    const result = await service.identify(jpeg);
    expect(result).toEqual({ status: "identified", items: [item], comment: "" });
  });

  test("tells the model to read prices and quantities rather than guess them", async () => {
    const { ai, service } = makeService({ status: "identified", items: [item], comment: "" });

    await service.identify(jpeg);
    expect(ai.requests[0]?.instructions).toContain("unitPrice");
    expect(ai.requests[0]?.instructions).toContain("read, never guessed");
  });

  test("drops out-of-range readings to null instead of failing the scan", async () => {
    const { service } = makeService({
      status: "identified",
      items: [
        { ...item, unitPrice: -2, quantity: 0 },
        { ...item, unitPrice: 7.999, quantity: 0.456 },
      ],
      comment: "",
    });

    const result = await service.identify(jpeg);
    if (result.status !== "identified") throw new Error("expected an identified result");
    expect(result.items[0]).toEqual({ ...item, unitPrice: null, quantity: null });
    expect(result.items[1]).toEqual({ ...item, unitPrice: 8, quantity: null });
  });

  test("asks for a schema the Agent SDK can hand to the model as a tool input_schema", async () => {
    // A tool input_schema must be an object and rejects a top-level anyOf/oneOf/allOf, so the union
    // travels nested. Sending one flat made every photo scan fail with ai_invalid_output.
    const { ai, service } = makeService({ status: "identified", items: [item], comment: "" });

    await service.identify(jpeg);
    const schema = ai.requests[0]?.outputSchema;
    expect(schema?.["type"]).toBe("object");
    expect(schema?.["anyOf"]).toBeUndefined();
    expect(schema?.["oneOf"]).toBeUndefined();
    expect(schema?.["allOf"]).toBeUndefined();
  });

  test("readings the model could not make arrive as null", async () => {
    const { service } = makeService({
      status: "identified",
      items: [{ ...item, unitPrice: null, quantity: null }],
      comment: "",
    });

    const result = await service.identify(jpeg);
    if (result.status !== "identified") throw new Error("expected an identified result");
    expect(result.items[0]).toEqual({ ...item, unitPrice: null, quantity: null });
  });

  test("records what the run cost", async () => {
    const recorded: AiSpend[] = [];
    const ai = stubAi({ result: { status: "identified", items: [item], comment: "" } });
    const service = new PhotoScanService({
      ai,
      prompt: "identify it",
      spend: {
        record: async (spend) => {
          recorded.push(spend);
        },
      },
    });

    await service.identify(jpeg);
    expect(recorded).toHaveLength(1);
    expect(recorded[0]).toMatchObject({
      operation: "photo_scan",
      model: "stub",
      transport: "api",
      usage: { inputTokens: 0, outputTokens: 0, costUsd: undefined },
    });
  });
});
