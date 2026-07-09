import { randomUUID } from "node:crypto";
import { unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
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

// `claude -p --output-format json` wraps the answer in a result envelope.
const claudeCliOutputSchema = z.object({
  result: z.string(),
  is_error: z.boolean().optional(),
});

export interface PhotoScanConfig {
  bin: string;
  model: string;
  prompt: string;
  timeoutMs: number;
}

export class PhotoScanService {
  constructor(private readonly config: PhotoScanConfig) {}

  /** Identify the item in a photo by delegating to the Claude CLI. Rejections are results, not errors. */
  async identify(image: File): Promise<PhotoScanResult> {
    const extension = IMAGE_EXTENSIONS[image.type];
    if (!extension) {
      throw new LedgerError(status.BAD_REQUEST, `Unsupported image type: ${image.type || "unknown"}`, "invalid_image");
    }
    if (image.size === 0 || image.size > MAX_IMAGE_BYTES) {
      throw new LedgerError(status.BAD_REQUEST, "Image must be between 1 byte and 10 MB", "invalid_image");
    }

    const imagePath = join(tmpdir(), `ledger-photo-scan-${randomUUID()}.${extension}`);
    const startedAt = Date.now();
    try {
      await Bun.write(imagePath, image);
      const raw = await this.invokeClaude(imagePath);
      const result = this.parseResult(raw);
      useLog()
        .withMetadata({ status: result.status, durationMs: Date.now() - startedAt, model: this.config.model })
        .info("Photo scan processed");
      return result;
    } finally {
      await unlink(imagePath).catch(() => {});
    }
  }

  private buildPrompt(imagePath: string): string {
    return [
      `Read the image at ${imagePath}.`,
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
    ].join("\n");
  }

  private async invokeClaude(imagePath: string): Promise<string> {
    const proc = Bun.spawn(
      [
        this.config.bin,
        "-p",
        this.buildPrompt(imagePath),
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

  private parseResult(stdout: string): PhotoScanResult {
    const envelope = claudeCliOutputSchema.safeParse(safeJsonParse(stdout));
    if (!envelope.success || envelope.data.is_error) {
      useLog()
        .withMetadata({ stdout: stdout.slice(0, 2000) })
        .error("Unexpected Claude CLI envelope");
      throw new LedgerError(status.BAD_GATEWAY, "The AI returned an unexpected response", "ai_invalid_output");
    }

    const parsed = photoScanResultSchema.safeParse(safeJsonParse(stripFences(envelope.data.result)));
    if (!parsed.success) {
      useLog()
        .withMetadata({ result: envelope.data.result.slice(0, 2000), issues: z.treeifyError(parsed.error) })
        .error("Claude output did not match the photo scan contract");
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
