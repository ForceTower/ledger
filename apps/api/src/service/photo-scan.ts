import { CATEGORIES, type PhotoScanResult } from "@ledger/shared-types";
import { z } from "zod";
import { useLog } from "../logger";
import { type AiRunner, validateImage } from "./ai";

/** A photo of a full haul could list dozens of items; cap the output so it stays within the token budget. */
const MAX_ITEMS = 20;

export const DEFAULT_PHOTO_PROMPT =
  "The picture shows either household/grocery items themselves or a printed store receipt listing " +
  "them — both are valid. Identify every item, reading the printed lines when it is a receipt, and " +
  "map each one to the expected fields — including the price and unit count when the picture shows " +
  "them — plus a short comment with anything worth noting about what you see.";

const REJECTION_REASONS = ["no_item", "unclear_image", "inappropriate"] as const;

const identifiedSchema = z.object({
  status: z.literal("identified"),
  items: z
    .array(
      z.object({
        description: z.string().min(1),
        category: z.enum(CATEGORIES),
        confidence: z.number().min(0).max(1),
        unitPrice: z.number().nullable(),
        quantity: z.number().nullable(),
      }),
    )
    .min(1),
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
        items: {
          type: "array",
          items: {
            type: "object",
            properties: {
              description: { type: "string" },
              category: { type: "string", enum: [...CATEGORIES] },
              confidence: { type: "number" },
              unitPrice: { type: ["number", "null"] },
              quantity: { type: ["number", "null"] },
            },
            required: ["description", "category", "confidence", "unitPrice", "quantity"],
            additionalProperties: false,
          },
        },
        comment: { type: "string" },
      },
      required: ["status", "items", "comment"],
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

export class PhotoScanService {
  constructor(private readonly deps: { ai: AiRunner; prompt: string }) {}

  /** Identify the items in a photo. Rejections are results, not errors. */
  async identify(image: File): Promise<PhotoScanResult> {
    const validated = await validateImage(image, "invalid_image");

    const startedAt = Date.now();
    const response = await this.deps.ai.run({
      instructions: this.buildInstructions(),
      image: validated,
      outputSchema: PHOTO_SCAN_JSON_SCHEMA,
    });
    const result = normalizeReadings(this.deps.ai.parse(response.text, photoScanResultSchema));

    useLog()
      .withMetadata({
        status: result.status,
        itemCount: result.status === "identified" ? result.items.length : 0,
        durationMs: Date.now() - startedAt,
        model: this.deps.ai.model,
        transport: response.transport,
        inputTokens: response.usage.inputTokens,
        outputTokens: response.usage.outputTokens,
        costUsd: response.usage.costUsd,
      })
      .info("Photo scan processed");
    return result;
  }

  private buildInstructions(): string {
    return [
      this.deps.prompt,
      "",
      `Valid categories: ${CATEGORIES.join(", ")}.`,
      `Valid rejection reasons: ${REJECTION_REASONS.join(", ")} — use "no_item" when there is neither a`,
      `product nor a purchase receipt in frame, "unclear_image" when it is too blurry/dark/cropped to tell,`,
      `"inappropriate" for people or anything that is neither a household item nor a purchase receipt.`,
      "",
      `List one entry per distinct product, most prominent first, at most ${MAX_ITEMS} entries. Several copies of`,
      "the same product (or repeated receipt lines) are one entry, with the count in quantity. When reading a",
      "receipt, tidy each abbreviated line into a readable product name instead of copying it verbatim. Skip",
      "anything you cannot name with reasonable confidence rather than guessing; if that leaves nothing, refuse",
      "instead of returning an empty list.",
      "",
      "Prices and quantities are read, never guessed:",
      `- unitPrice: what one unit costs in BRL as a number (8.99 for "R$ 8,99"), read off a price tag or a`,
      "  receipt line. For an item sold by weight, put the line's total as unitPrice and 1 as quantity. Null",
      "  when the picture shows no price for the item.",
      "- quantity: how many units, as a whole number — the receipt's quantity column or the copies you can",
      "  count in the picture. Null when unsure.",
      "",
      "Respond with ONLY one JSON object, no markdown fences and no extra text:",
      `- If you can identify at least one item: {"status":"identified","items":[{"description":<string, item`,
      `  name as it would appear on a Brazilian receipt line, pt-BR>,"category":<category>,"confidence":`,
      `  <number 0..1>,"unitPrice":<number|null>,"quantity":<integer|null>}, ...],"comment":<string, pt-BR>}`,
      `- If you must refuse: {"status":"rejected","reason":<rejection reason>,"comment":<string explaining`,
      "  why, pt-BR>}",
    ].join("\n");
  }
}

/**
 * Structured outputs cannot carry min/max, so out-of-range readings (a negative price, a weighed
 * 0.456 as quantity) are dropped to null — a lost prefill, not a failed scan. Prices are rounded
 * to money precision like everywhere else.
 */
function normalizeReadings(result: PhotoScanResult): PhotoScanResult {
  if (result.status !== "identified") return result;
  return {
    ...result,
    items: result.items.map((item) => ({
      ...item,
      unitPrice: item.unitPrice !== null && item.unitPrice > 0 ? Math.round(item.unitPrice * 100) / 100 : null,
      quantity: item.quantity !== null && Number.isInteger(item.quantity) && item.quantity >= 1 ? item.quantity : null,
    })),
  };
}
