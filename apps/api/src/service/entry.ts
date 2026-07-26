import { CATEGORIES, type EntryDraft } from "@ledger/shared-types";
import status from "http-status";
import { z } from "zod";
import { LedgerError } from "../error";
import { useLog } from "../logger";
import { type AiRunner, validateImage } from "./ai";

/** A typed description is a sentence or two; anything longer is a pasted receipt, which still fits. */
const MAX_TEXT_LENGTH = 8000;

/** One description can list a few things bought together, never a whole haul. */
const MAX_ITEMS = 20;

export const DEFAULT_ENTRY_PROMPT =
  "The owner is telling you, in their own words, about money they spent — something like " +
  '"37,00 de transporte no dia 24 de julho". Turn it into a ledger entry: how much, on what, ' +
  "where, and when.";

const draftSchema = z.object({
  status: z.literal("entry"),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  time: z
    .string()
    .regex(/^\d{2}:\d{2}:\d{2}$/)
    .nullable(),
  store: z.string().nullable(),
  paymentMethod: z.string().nullable(),
  items: z
    .array(
      z.object({
        description: z.string().min(1),
        category: z.enum(CATEGORIES),
        quantity: z.number().nullable(),
        unitPrice: z.number().nullable(),
      }),
    )
    .min(1),
  comment: z.string(),
});

const notAnEntrySchema = z.object({
  status: z.literal("not_an_entry"),
  comment: z.string(),
});

export const entryExtractionSchema = z.discriminatedUnion("status", [draftSchema, notAnEntrySchema]);

// Nested under `result` for the same reason as the photo and transfer reads: the Agent SDK hands
// this to the model as a tool input_schema, which must be an object and rejects a top-level anyOf.
const entryEnvelopeSchema = z.object({ result: entryExtractionSchema });

// JSON Schema mirror of entryExtractionSchema for the API's structured outputs, which forbids
// format/pattern/min/max constraints and requires additionalProperties: false everywhere.
const ENTRY_UNION = {
  anyOf: [
    {
      type: "object",
      properties: {
        status: { type: "string", const: "entry" },
        date: { type: "string" },
        time: { type: ["string", "null"] },
        store: { type: ["string", "null"] },
        paymentMethod: { type: ["string", "null"] },
        items: {
          type: "array",
          items: {
            type: "object",
            properties: {
              description: { type: "string" },
              category: { type: "string", enum: [...CATEGORIES] },
              quantity: { type: ["number", "null"] },
              unitPrice: { type: ["number", "null"] },
            },
            required: ["description", "category", "quantity", "unitPrice"],
            additionalProperties: false,
          },
        },
        comment: { type: "string" },
      },
      required: ["status", "date", "time", "store", "paymentMethod", "items", "comment"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        status: { type: "string", const: "not_an_entry" },
        comment: { type: "string" },
      },
      required: ["status", "comment"],
      additionalProperties: false,
    },
  ],
};

const ENTRY_JSON_SCHEMA = {
  type: "object",
  properties: { result: ENTRY_UNION },
  required: ["result"],
  additionalProperties: false,
};

export interface EntryInput {
  text?: string;
  /** Optional evidence for what the description says — a print, a receipt photo, a price tag. */
  image?: File;
}

/**
 * Reads the owner's own account of a purchase into a draft they can correct. Nothing is persisted
 * here: confirming the draft is a `POST /purchases`, which is a different call entirely.
 */
export class EntryService {
  constructor(
    private readonly deps: {
      ai: AiRunner;
      prompt: string;
      /** The ledger's home timezone, so "hoje" means the owner's today rather than the server's. */
      timeZone: string;
      now?: () => Date;
    },
  ) {}

  async interpret(input: EntryInput): Promise<EntryDraft> {
    const image = input.image ? await validateImage(input.image, "invalid_input") : undefined;
    const text = input.text?.trim();
    if (!image && !text) {
      throw new LedgerError(status.BAD_REQUEST, "A description of the purchase is required", "invalid_input");
    }
    if (text && text.length > MAX_TEXT_LENGTH) {
      throw new LedgerError(
        status.BAD_REQUEST,
        `The description must be at most ${MAX_TEXT_LENGTH} characters`,
        "invalid_input",
      );
    }

    const startedAt = Date.now();
    const response = await this.deps.ai.run({
      instructions: this.buildInstructions(text),
      image,
      outputSchema: ENTRY_JSON_SCHEMA,
    });
    const extraction = this.deps.ai.parse(response.text, entryEnvelopeSchema).result;

    useLog()
      .withMetadata({
        status: extraction.status,
        itemCount: extraction.status === "entry" ? extraction.items.length : 0,
        hasImage: image !== undefined,
        hasText: text !== undefined,
        durationMs: Date.now() - startedAt,
        model: this.deps.ai.model,
        transport: response.transport,
        inputTokens: response.usage.inputTokens,
        outputTokens: response.usage.outputTokens,
        costUsd: response.usage.costUsd,
      })
      .info("Entry description processed");

    if (extraction.status === "not_an_entry") {
      throw new LedgerError(status.UNPROCESSABLE_ENTITY, extraction.comment, "not_an_entry");
    }
    return normalizeDraft(extraction);
  }

  private buildInstructions(text: string | undefined): string {
    const lines = [this.deps.prompt, "", `Today is ${this.today()} in ${this.deps.timeZone}.`];
    if (text) {
      lines.push("", "This is what the owner wrote:", "---", text, "---");
    }
    if (!text) {
      lines.push("", "The owner sent no words at all — read the attached image on its own.");
    } else {
      lines.push(
        "",
        "Any attached image is supporting evidence (a receipt, a bank print, a price tag). Where the",
        "image and the words disagree, the words win: the owner typed them on purpose.",
      );
    }
    lines.push(
      "",
      `Valid categories: ${CATEGORIES.join(", ")}. Pick what the money was spent on — a bus fare or a`,
      `ride app is "transport", a restaurant or delivery is "dining", a pharmacy or a consultation is`,
      `"health", a haircut or a subscription is "services". Groceries keep their aisle ("produce",`,
      `"bakery", "meat"…). Use "other" only when nothing fits.`,
      "",
      "Rules for the fields:",
      `- date: "YYYY-MM-DD". Resolve whatever the owner wrote against today — "hoje", "ontem",`,
      `  "sexta passada", "dia 24 de julho". A bare day (with or without a month) is the most recent`,
      "  such date that is not in the future. Default to today when the description says nothing.",
      `- time: "HH:MM:SS", or null when the description does not mention one.`,
      '- store: where the money went, when it is named or obvious ("Uber", "Padaria do Zé").',
      "  Null when the description names no place — do not invent one from the category.",
      `- paymentMethod: as written — "Pix", "Dinheiro", "Cartão de crédito", "Cartão de débito". Null`,
      "  when the description does not say how it was paid.",
      `- items: one entry per thing paid for, so "37 de transporte e 20 de padaria" is two entries.`,
      `  description is a short pt-BR name for it, capitalized like a receipt line ("Transporte",`,
      `  "Pão francês"). At most ${MAX_ITEMS} entries.`,
      `- unitPrice: BRL for ONE unit as a number — 37 for "37,00", 1234.56 for "R$ 1.234,56". When the`,
      "  owner gives a total for several units, divide it by the quantity. Null when no price is given.",
      "- quantity: whole units, as a number. Null when the description does not count them.",
      "- Refuse when the text is not about spending money at all (a question, a shopping list, a note",
      "  to self) — never invent an amount to have something to return.",
      "",
      'Respond with ONLY one JSON object, no markdown fences and no extra text, shaped {"result":<answer>}',
      "where <answer> is one of:",
      `- If it describes a purchase: {"status":"entry","date":<string>,"time":<string|null>,"store":`,
      `  <string|null>,"paymentMethod":<string|null>,"items":[{"description":<string, pt-BR>,"category":`,
      `  <category>,"quantity":<integer|null>,"unitPrice":<number|null>}, ...],"comment":<string, pt-BR,`,
      "  anything worth flagging about the reading, e.g. a date or price you had to infer>}",
      `- If it does not: {"status":"not_an_entry","comment":<string explaining why, pt-BR>}`,
    );
    return lines.join("\n");
  }

  /** The owner's calendar day, not the server's: a UTC box is already tomorrow by 21:00 in Brazil. */
  private today(): string {
    const now = this.deps.now?.() ?? new Date();
    const day = new Intl.DateTimeFormat("en-CA", {
      timeZone: this.deps.timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(now);
    const weekday = new Intl.DateTimeFormat("en-US", { timeZone: this.deps.timeZone, weekday: "long" }).format(now);
    return `${day} (a ${weekday})`;
  }
}

/**
 * Structured outputs cannot carry min/max, so nonsense readings (a negative price, 2.5 as a unit
 * count) drop to null — a lost prefill the owner fills in, not a failed read. An unnamed store
 * comes back as null rather than as an empty string the client would have to special-case.
 */
function normalizeDraft(extraction: z.infer<typeof draftSchema>): EntryDraft {
  return {
    date: extraction.date,
    time: extraction.time,
    store: extraction.store?.trim() || null,
    paymentMethod: extraction.paymentMethod?.trim() || null,
    items: extraction.items.slice(0, MAX_ITEMS).map((item) => ({
      description: item.description.trim(),
      category: item.category,
      quantity: item.quantity !== null && Number.isInteger(item.quantity) && item.quantity >= 1 ? item.quantity : null,
      unitPrice: item.unitPrice !== null && item.unitPrice > 0 ? Math.round(item.unitPrice * 100) / 100 : null,
    })),
    comment: extraction.comment,
  };
}
