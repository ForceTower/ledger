import { randomUUID } from "node:crypto";
import { unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import Anthropic from "@anthropic-ai/sdk";
import type { PhotoScanResult } from "@ledger/shared-types";
import status from "http-status";
import { z } from "zod";
import { LedgerError } from "../error";
import { useLog } from "../logger";

const IMAGE_EXTENSIONS: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

const MAX_OUTPUT_TOKENS = 1024;

export const DEFAULT_PHOTO_PROMPT =
  "Identify the single household/grocery item in the picture and map it to the expected fields, " +
  "plus a short comment with anything worth noting about the item.";

const CATEGORIES = [
  "produce",
  "meat",
  "dairy_deli",
  "bakery",
  "grocery",
  "beverages",
  "snacks_sweets",
  "frozen",
  "cleaning",
  "hygiene",
  "pet",
  "household",
  "other",
] as const;

const REJECTION_REASONS = ["no_item", "unclear_image", "multiple_items", "inappropriate"] as const;

// Only the base64-source media types the Anthropic API accepts, narrowed from a validated image.type.
const apiMediaTypeSchema = z.enum(["image/jpeg", "image/png", "image/webp"]);

const identifiedSchema = z.object({
  status: z.literal("identified"),
  item: z.object({
    description: z.string().min(1),
    category: z.enum(CATEGORIES),
    confidence: z.number().min(0).max(1),
  }),
  comment: z.string(),
});

const rejectedSchema = z.object({
  status: z.literal("rejected"),
  reason: z.enum(REJECTION_REASONS),
  comment: z.string(),
});

const photoScanResultSchema = z.discriminatedUnion("status", [identifiedSchema, rejectedSchema]);

// JSON Schema mirror of photoScanResultSchema for the API's structured outputs. Structured outputs
// forbids numeric/length constraints (min/max) and requires additionalProperties: false everywhere.
const PHOTO_SCAN_JSON_SCHEMA = {
  anyOf: [
    {
      type: "object",
      properties: {
        status: { type: "string", const: "identified" },
        item: {
          type: "object",
          properties: {
            description: { type: "string" },
            category: { type: "string", enum: [...CATEGORIES] },
            confidence: { type: "number" },
          },
          required: ["description", "category", "confidence"],
          additionalProperties: false,
        },
        comment: { type: "string" },
      },
      required: ["status", "item", "comment"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        status: { type: "string", const: "rejected" },
        reason: { type: "string", enum: [...REJECTION_REASONS] },
        comment: { type: "string" },
      },
      required: ["status", "reason", "comment"],
      additionalProperties: false,
    },
  ],
};

// `claude -p --output-format json` wraps the answer in a result envelope.
const claudeCliOutputSchema = z.object({
  result: z.string(),
  is_error: z.boolean().optional(),
});

export interface PhotoScanConfig {
  /** When set, the Anthropic API is used; otherwise the Claude CLI (`bin`) is invoked on the host. */
  apiKey: string | undefined;
  bin: string;
  model: string;
  prompt: string;
  timeoutMs: number;
}

export class PhotoScanService {
  private readonly anthropic: Anthropic | undefined;

  constructor(private readonly config: PhotoScanConfig) {
    this.anthropic = config.apiKey ? new Anthropic({ apiKey: config.apiKey }) : undefined;
  }

  /** Identify the item in a photo via the Anthropic API when configured, else the Claude CLI. Rejections are results, not errors. */
  async identify(image: File): Promise<PhotoScanResult> {
    const extension = IMAGE_EXTENSIONS[image.type];
    if (!extension) {
      throw new LedgerError(status.BAD_REQUEST, `Unsupported image type: ${image.type || "unknown"}`, "invalid_image");
    }
    if (image.size === 0 || image.size > MAX_IMAGE_BYTES) {
      throw new LedgerError(status.BAD_REQUEST, "Image must be between 1 byte and 10 MB", "invalid_image");
    }

    const startedAt = Date.now();
    const transport = this.anthropic ? "api" : "cli";
    const result = this.anthropic
      ? await this.identifyViaApi(this.anthropic, image)
      : await this.identifyViaCli(image, extension);
    useLog()
      .withMetadata({ status: result.status, durationMs: Date.now() - startedAt, model: this.config.model, transport })
      .info("Photo scan processed");
    return result;
  }

  private async identifyViaApi(client: Anthropic, image: File): Promise<PhotoScanResult> {
    const mediaType = apiMediaTypeSchema.parse(image.type);
    const data = Buffer.from(await image.arrayBuffer()).toString("base64");

    let message: Anthropic.Message;
    try {
      message = await client.messages.create(
        {
          model: this.config.model,
          max_tokens: MAX_OUTPUT_TOKENS,
          output_config: { format: { type: "json_schema", schema: PHOTO_SCAN_JSON_SCHEMA } },
          messages: [
            {
              role: "user",
              content: [
                { type: "image", source: { type: "base64", media_type: mediaType, data } },
                { type: "text", text: this.buildInstructions() },
              ],
            },
          ],
        },
        { timeout: this.config.timeoutMs },
      );
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      useLog().withError(err).error("Anthropic photo scan request failed");
      throw new LedgerError(status.BAD_GATEWAY, "The AI service is unavailable", "ai_unavailable");
    }

    const textBlock = message.content.find((block): block is Anthropic.TextBlock => block.type === "text");
    if (message.stop_reason === "refusal" || textBlock === undefined) {
      useLog()
        .withMetadata({ stopReason: message.stop_reason })
        .error("Anthropic returned no usable photo scan output");
      throw new LedgerError(status.BAD_GATEWAY, "The AI returned an unexpected response", "ai_invalid_output");
    }
    return this.parseModelJson(textBlock.text);
  }

  private async identifyViaCli(image: File, extension: string): Promise<PhotoScanResult> {
    const imagePath = join(tmpdir(), `ledger-photo-scan-${randomUUID()}.${extension}`);
    try {
      await Bun.write(imagePath, image);
      const stdout = await this.invokeClaude(imagePath);
      return this.parseCliResult(stdout);
    } finally {
      await unlink(imagePath).catch(() => {});
    }
  }

  private buildInstructions(imagePath?: string): string {
    const lines: string[] = [];
    if (imagePath !== undefined) {
      lines.push(`Read the image at ${imagePath}.`);
    }
    lines.push(
      this.config.prompt,
      "",
      `Valid categories: ${CATEGORIES.join(", ")}.`,
      `Valid rejection reasons: ${REJECTION_REASONS.join(", ")} — use "no_item" when there is no product in`,
      `frame, "unclear_image" when it is too blurry/dark/cropped to tell, "multiple_items" when you cannot`,
      `tell which item is intended, "inappropriate" for people, documents, or anything that is not a`,
      "household item.",
      "",
      "Respond with ONLY one JSON object, no markdown fences and no extra text:",
      `- If you can identify the item: {"status":"identified","item":{"description":<string, item name as it`,
      `  would appear on a Brazilian receipt line, pt-BR>,"category":<category>,"confidence":<number 0..1>},`,
      `  "comment":<string, pt-BR>}`,
      `- If you must refuse: {"status":"rejected","reason":<rejection reason>,"comment":<string explaining`,
      "  why, pt-BR>}",
    );
    return lines.join("\n");
  }

  private async invokeClaude(imagePath: string): Promise<string> {
    const proc = Bun.spawn(
      [
        this.config.bin,
        "-p",
        this.buildInstructions(imagePath),
        "--model",
        this.config.model,
        "--output-format",
        "json",
        "--allowedTools",
        "Read",
      ],
      { stdout: "pipe", stderr: "pipe", stdin: "ignore" },
    );

    const timeout = setTimeout(() => proc.kill(), this.config.timeoutMs);
    try {
      const [stdout, stderr, exitCode] = await Promise.all([
        new Response(proc.stdout).text(),
        new Response(proc.stderr).text(),
        proc.exited,
      ]);
      if (exitCode !== 0) {
        useLog()
          .withMetadata({ exitCode, stderr: stderr.slice(0, 2000) })
          .error("Claude CLI failed");
        throw new LedgerError(status.BAD_GATEWAY, "The AI service is unavailable", "ai_unavailable");
      }
      return stdout;
    } catch (error) {
      if (error instanceof LedgerError) throw error;
      const err = error instanceof Error ? error : new Error(String(error));
      useLog().withError(err).error("Claude CLI could not be executed");
      throw new LedgerError(status.BAD_GATEWAY, "The AI service is unavailable", "ai_unavailable");
    } finally {
      clearTimeout(timeout);
    }
  }

  private parseCliResult(stdout: string): PhotoScanResult {
    const envelope = claudeCliOutputSchema.safeParse(safeJsonParse(stdout));
    if (!envelope.success || envelope.data.is_error) {
      useLog()
        .withMetadata({ stdout: stdout.slice(0, 2000) })
        .error("Unexpected Claude CLI envelope");
      throw new LedgerError(status.BAD_GATEWAY, "The AI returned an unexpected response", "ai_invalid_output");
    }
    return this.parseModelJson(envelope.data.result);
  }

  private parseModelJson(text: string): PhotoScanResult {
    const parsed = photoScanResultSchema.safeParse(safeJsonParse(stripFences(text)));
    if (!parsed.success) {
      useLog()
        .withMetadata({ result: text.slice(0, 2000), issues: z.treeifyError(parsed.error) })
        .error("Model output did not match the photo scan contract");
      throw new LedgerError(status.BAD_GATEWAY, "The AI returned an unexpected response", "ai_invalid_output");
    }
    return parsed.data;
  }
}

function safeJsonParse(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

/** The prompt forbids fences, but models occasionally add them anyway. */
function stripFences(text: string): string {
  return text
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/, "");
}
