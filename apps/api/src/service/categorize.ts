import type { ParsedItem } from "@ledger/nfce";
import { CATEGORIES, type Category } from "@ledger/shared-types";
import { z } from "zod";
import type { LedgerDb } from "../db";
import { useLog } from "../logger";
import type { AiRunner } from "./ai";
import type { SpendRecorder } from "./ai-spend";

/** One prompt covers a whole receipt; beyond this the descriptions are split across calls. */
const MAX_BATCH = 40;

export const DEFAULT_CATEGORIZE_PROMPT =
  "Each line below is one item from a Brazilian supermarket receipt, printed in the abbreviated " +
  "upper-case Portuguese those receipts use — heavily truncated words, brand names, pack sizes and " +
  "flavours all run together. Work out what each product actually is and file it under the best " +
  "category.";

const answerSchema = z.object({
  items: z.array(z.object({ index: z.number().int(), category: z.enum(CATEGORIES) })),
});

const CATEGORIZE_JSON_SCHEMA = {
  type: "object",
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          index: { type: "integer" },
          category: { type: "string", enum: [...CATEGORIES] },
        },
        required: ["index", "category"],
        additionalProperties: false,
      },
    },
  },
  required: ["items"],
  additionalProperties: false,
};

/**
 * Settles the category of every item on a receipt, cheapest signal first:
 *
 * 1. the keyword rules in `@ledger/nfce`, already applied at parse time — anything but `other` means
 *    they recognised the line, and they win outright;
 * 2. what this barcode was filed under last time, so a product keeps one category across receipts
 *    even when a store prints it differently;
 * 3. the model, asked once per receipt about the lines nothing else could place.
 *
 * Every layer is optional: with no barcode, no history and no model configured the item simply stays
 * `other`, which is what the rules alone would have produced.
 */
export class CategorizerService {
  constructor(private readonly deps: { db: LedgerDb; ai?: AiRunner; prompt: string; spend?: SpendRecorder }) {}

  async resolve(items: ParsedItem[]): Promise<ParsedItem[]> {
    const unresolved = items.filter((item) => item.category === "other");
    if (unresolved.length === 0) return items;

    const remembered = await this.rememberedByBarcode(unresolved);
    const stillUnresolved = unresolved.filter((item) => !(item.barcode && remembered.has(item.barcode)));
    const inferred = await this.inferByDescription(stillUnresolved);

    return items.map((item) => {
      if (item.category !== "other") return item;
      const category = (item.barcode ? remembered.get(item.barcode) : undefined) ?? inferred.get(item.description);
      return category ? { ...item, category } : item;
    });
  }

  /** Categories already learned for these barcodes. `other` is not a memory, so it is not returned. */
  private async rememberedByBarcode(items: ParsedItem[]): Promise<Map<string, Category>> {
    const barcodes = [...new Set(items.map((item) => item.barcode).filter((code) => !!code))];
    if (barcodes.length === 0) return new Map();

    const rows = await this.deps.db
      .selectFrom("products")
      .select(["barcode", "defaultCategory"])
      .where("barcode", "in", barcodes)
      .where("defaultCategory", "is not", null)
      .where("defaultCategory", "!=", "other")
      .execute();

    const remembered = new Map<string, Category>();
    for (const row of rows) {
      if (row.defaultCategory && row.defaultCategory !== "other") remembered.set(row.barcode, row.defaultCategory);
    }
    return remembered;
  }

  /** Ask the model about the lines nothing else could place. A model failure leaves them `other`. */
  private async inferByDescription(items: ParsedItem[]): Promise<Map<string, Category>> {
    const resolved = new Map<string, Category>();
    const { ai } = this.deps;
    const descriptions = [...new Set(items.map((item) => item.description).filter((text) => text.trim() !== ""))];
    if (!ai || descriptions.length === 0) return resolved;

    for (let start = 0; start < descriptions.length; start += MAX_BATCH) {
      const batch = descriptions.slice(start, start + MAX_BATCH);
      try {
        const startedAt = Date.now();
        const response = await ai.run({
          instructions: this.buildInstructions(batch),
          outputSchema: CATEGORIZE_JSON_SCHEMA,
        });
        for (const answer of ai.parse(response.text, answerSchema).items) {
          const description = batch[answer.index];
          if (description !== undefined) resolved.set(description, answer.category);
        }
        const durationMs = Date.now() - startedAt;
        useLog()
          .withMetadata({
            requested: batch.length,
            answered: resolved.size,
            durationMs,
            model: ai.model,
            transport: response.transport,
            inputTokens: response.usage.inputTokens,
            outputTokens: response.usage.outputTokens,
            costUsd: response.usage.costUsd,
          })
          .info("Categorized unmatched items");
        await this.deps.spend?.record({
          operation: "categorize",
          model: ai.model,
          transport: response.transport,
          usage: response.usage,
          durationMs,
        });
      } catch (error) {
        // The rules already produced a usable answer (`other`), so a model outage must not fail a scan.
        useLog().withError(error).withMetadata({ count: batch.length }).warn("Category inference failed");
      }
    }
    return resolved;
  }

  private buildInstructions(descriptions: string[]): string {
    return [
      this.deps.prompt,
      "",
      `Valid categories: ${CATEGORIES.join(", ")}.`,
      'Use "other" only for a line that names no product at all — a subtotal, a bag fee, a person\'s name.',
      'A line you can only partly decipher still belongs in its best-guess category, not in "other".',
      "",
      "Items:",
      ...descriptions.map((description, index) => `${index}. ${description}`),
      "",
      "Respond with ONLY one JSON object, no markdown fences and no extra text, holding one entry per",
      'item above and echoing its index: {"items":[{"index":<integer>,"category":<category>}, ...]}',
    ].join("\n");
  }
}
