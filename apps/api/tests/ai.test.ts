import { describe, expect, test } from "bun:test";
import { z } from "zod";
import { LedgerError } from "../src/error";
import { agentSubprocessEnv, AiClient, MAX_IMAGE_BYTES, validateImage } from "../src/service/ai";

const client = new AiClient({
  apiKey: undefined,
  subscriptionToken: undefined,
  model: "claude-haiku-4-5",
  timeoutMs: 1000,
});
const schema = z.object({ status: z.literal("ok"), count: z.number() });

const HEADERS: Record<string, number[]> = {
  jpg: [0xff, 0xd8, 0xff, 0xe0],
  png: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
  webp: [...Buffer.from("RIFF"), 0, 0, 0, 0, ...Buffer.from("WEBP")],
  pdf: [...Buffer.from("%PDF-1.7")],
};

/** Named .png whatever it holds, because that is what Bun reports for every multipart upload. */
function imageOf(kind: keyof typeof HEADERS, bytes = 64): File {
  const body = new Uint8Array(bytes);
  body.set(HEADERS[kind] ?? []);
  return new File([body], "upload.png", { type: "image/png" });
}

describe("AiClient.parse", () => {
  test("parses a bare JSON answer", () => {
    expect(client.parse('{"status":"ok","count":2}', schema)).toEqual({ status: "ok", count: 2 });
  });

  // The prompts forbid fences, but models add them anyway often enough to handle it.
  test("strips markdown fences the prompt asked the model not to use", () => {
    expect(client.parse('```json\n{"status":"ok","count":2}\n```', schema)).toEqual({ status: "ok", count: 2 });
    expect(client.parse('```\n{"status":"ok","count":2}\n```', schema)).toEqual({ status: "ok", count: 2 });
  });

  test("output that is not JSON is an invalid output, not a crash", () => {
    expect(() => client.parse("Claro! Aqui está:", schema)).toThrow(LedgerError);
    try {
      client.parse("Claro! Aqui está:", schema);
    } catch (error) {
      expect((error as LedgerError).errorCode).toBe("ai_invalid_output");
      expect((error as LedgerError).statusCode).toBe(424);
    }
  });

  test("JSON that misses the contract is an invalid output", () => {
    expect(() => client.parse('{"status":"ok","count":"two"}', schema)).toThrow(LedgerError);
  });
});

describe("agentSubprocessEnv", () => {
  test("a subscription token drops the API key from the subprocess", () => {
    const env = agentSubprocessEnv({ CLAUDE_CODE_OAUTH_TOKEN: "tok", ANTHROPIC_API_KEY: "key", PATH: "/bin" });
    expect(env).toBeDefined();
    expect(env?.CLAUDE_CODE_OAUTH_TOKEN).toBe("tok");
    expect(env?.ANTHROPIC_API_KEY).toBeUndefined();
    expect(env?.PATH).toBe("/bin");
  });

  test("without a token the environment is inherited untouched", () => {
    expect(agentSubprocessEnv({ ANTHROPIC_API_KEY: "key" })).toBeUndefined();
  });
});

describe("validateImage", () => {
  test("reads the real type off the first bytes", async () => {
    expect(await validateImage(imageOf("jpg"), "invalid_input")).toMatchObject({
      extension: "jpg",
      mediaType: "image/jpeg",
    });
    expect(await validateImage(imageOf("png"), "invalid_input")).toMatchObject({
      extension: "png",
      mediaType: "image/png",
    });
    expect(await validateImage(imageOf("webp"), "invalid_input")).toMatchObject({
      extension: "webp",
      mediaType: "image/webp",
    });
  });

  // Bun names a multipart File after its filename, so ".png" vouches for nothing.
  test("a PDF called upload.png is still rejected", async () => {
    expect(imageOf("pdf").type).toBe("image/png");
    try {
      await validateImage(imageOf("pdf"), "invalid_input");
      throw new Error("expected a rejection");
    } catch (error) {
      expect((error as LedgerError).errorCode).toBe("invalid_input");
      expect((error as LedgerError).statusCode).toBe(400);
    }
  });

  test("each endpoint names a bad upload its own way", async () => {
    try {
      await validateImage(imageOf("pdf"), "invalid_image");
      throw new Error("expected a rejection");
    } catch (error) {
      expect((error as LedgerError).errorCode).toBe("invalid_image");
    }
  });

  test("rejects an empty or oversized upload", async () => {
    expect(validateImage(new File([], "upload.png"), "invalid_input")).rejects.toThrow(LedgerError);
    expect(validateImage(imageOf("png", MAX_IMAGE_BYTES + 1), "invalid_input")).rejects.toThrow(LedgerError);
  });
});
