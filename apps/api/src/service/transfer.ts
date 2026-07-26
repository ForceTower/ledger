import {
  CATEGORIES,
  type TransferMatch,
  type TransferSaveRequest,
  type TransferSaveResult,
  type TransferScanResult,
} from "@ledger/shared-types";
import status from "http-status";
import { z } from "zod";
import { type CacheClient, withLock } from "../cache";
import type { LedgerDb } from "../db";
import { LedgerError } from "../error";
import { useLog } from "../logger";
import { type AiRunner, validateImage } from "./ai";
import { saveTransfer, WRITE_LOCK } from "./ingest";
import type { PurchaseService } from "./purchase";

/** A receipt's text is short; anything longer is someone pasting the wrong thing. */
const MAX_TEXT_LENGTH = 8000;

export const DEFAULT_TRANSFER_PROMPT =
  "Read this bank transfer receipt (a Brazilian Pix comprovante) and pull out the amount, who it " +
  "went to, when it happened, and the bank's end-to-end transaction ID.";

const partySchema = z.object({
  name: z.string().min(1),
  institution: z.string().nullable(),
  agency: z.string().nullable(),
  account: z.string().nullable(),
});

const extractedSchema = z.object({
  status: z.literal("transfer"),
  transactionId: z.string().min(1),
  type: z.literal("pix"),
  amount: z.number().positive(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  time: z
    .string()
    .regex(/^\d{2}:\d{2}:\d{2}$/)
    .nullable(),
  destination: partySchema,
  origin: partySchema.nullable(),
  category: z.enum(CATEGORIES),
  comment: z.string(),
});

const notATransferSchema = z.object({
  status: z.literal("not_a_transfer"),
  comment: z.string(),
});

export const transferExtractionSchema = z.discriminatedUnion("status", [extractedSchema, notATransferSchema]);

// Nested under `result` for the same reason as the photo scan: a tool input_schema, which is how the
// Agent SDK hands this to the model, must be an object and rejects a top-level anyOf.
const transferEnvelopeSchema = z.object({ result: transferExtractionSchema });

type TransferExtraction = z.infer<typeof transferExtractionSchema>;

// JSON Schema mirror of transferExtractionSchema for the API's structured outputs. Structured
// outputs forbids format/pattern constraints and requires additionalProperties: false everywhere.
const PARTY_JSON_SCHEMA = {
  type: "object",
  properties: {
    name: { type: "string" },
    institution: { type: ["string", "null"] },
    agency: { type: ["string", "null"] },
    account: { type: ["string", "null"] },
  },
  required: ["name", "institution", "agency", "account"],
  additionalProperties: false,
};

const TRANSFER_UNION = {
  anyOf: [
    {
      type: "object",
      properties: {
        status: { type: "string", const: "transfer" },
        transactionId: { type: "string" },
        type: { type: "string", const: "pix" },
        amount: { type: "number" },
        date: { type: "string" },
        time: { type: ["string", "null"] },
        destination: PARTY_JSON_SCHEMA,
        origin: { anyOf: [PARTY_JSON_SCHEMA, { type: "null" }] },
        category: { type: "string", enum: [...CATEGORIES] },
        comment: { type: "string" },
      },
      required: [
        "status",
        "transactionId",
        "type",
        "amount",
        "date",
        "time",
        "destination",
        "origin",
        "category",
        "comment",
      ],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        status: { type: "string", const: "not_a_transfer" },
        comment: { type: "string" },
      },
      required: ["status", "comment"],
      additionalProperties: false,
    },
  ],
};

const TRANSFER_JSON_SCHEMA = {
  type: "object",
  properties: { result: TRANSFER_UNION },
  required: ["result"],
  additionalProperties: false,
};

export interface TransferInput {
  image?: File;
  text?: string;
}

export class TransferService {
  constructor(
    private readonly deps: {
      db: LedgerDb;
      cache: CacheClient;
      ai: AiRunner;
      purchase: PurchaseService;
      prompt: string;
    },
  ) {}

  /**
   * Read a receipt without saving it: the owner still has to confirm the category and decide
   * whether it pays for a note already in the history.
   */
  async interpret(input: TransferInput): Promise<TransferScanResult> {
    const image = input.image ? await validateImage(input.image, "invalid_input") : undefined;
    const text = input.text?.trim();
    if (!image && !text) {
      throw new LedgerError(status.BAD_REQUEST, "A transfer receipt image or its text is required", "invalid_input");
    }
    if (text && text.length > MAX_TEXT_LENGTH) {
      throw new LedgerError(
        status.BAD_REQUEST,
        `Receipt text must be at most ${MAX_TEXT_LENGTH} characters`,
        "invalid_input",
      );
    }

    const startedAt = Date.now();
    const response = await this.deps.ai.run({
      instructions: this.buildInstructions(text),
      image,
      outputSchema: TRANSFER_JSON_SCHEMA,
    });
    const extraction = this.deps.ai.parse(response.text, transferEnvelopeSchema).result;

    useLog()
      .withMetadata({
        status: extraction.status,
        hasImage: image !== undefined,
        hasText: text !== undefined,
        durationMs: Date.now() - startedAt,
        model: this.deps.ai.model,
        transport: response.transport,
        inputTokens: response.usage.inputTokens,
        outputTokens: response.usage.outputTokens,
        costUsd: response.usage.costUsd,
      })
      .info("Transfer scan processed");

    if (extraction.status === "not_a_transfer") {
      throw new LedgerError(status.UNPROCESSABLE_ENTITY, extraction.comment, "not_a_transfer");
    }

    const transfer = toTransfer(extraction);
    return {
      transfer,
      category: extraction.category,
      match: await this.findMatch(transfer.date, transfer.amount, transfer.time),
      comment: extraction.comment,
    };
  }

  /** Persist a reviewed transfer. Idempotent on the transaction ID. */
  async save(request: TransferSaveRequest): Promise<TransferSaveResult> {
    const saved = await withLock(this.deps.cache, WRITE_LOCK, () => saveTransfer(this.deps.db, request));

    const purchase = await this.deps.purchase.get(saved.slug);
    if (!purchase) {
      throw new LedgerError(status.INTERNAL_SERVER_ERROR, `Saved purchase ${saved.slug} could not be read back`);
    }

    useLog()
      .withMetadata({ transactionId: request.transfer.transactionId, status: saved.status, slug: saved.slug })
      .info("Transfer saved");
    return { transfer: { ...request.transfer, purchaseId: saved.slug }, purchase };
  }

  /**
   * A purchase from the same day for exactly this amount is almost certainly what the transfer
   * paid for. Pix purchases are skipped — a transfer never pays for another transfer — and so are
   * notes another transfer already claims.
   */
  private async findMatch(date: string, amount: number, time: string | null): Promise<TransferMatch | null> {
    const candidates = await this.deps.db
      .selectFrom("purchases")
      .leftJoin("stores", "stores.id", "purchases.storeId")
      .select([
        "purchases.slug",
        "purchases.date",
        "purchases.time",
        "purchases.paidTotal",
        "purchases.itemCount",
        "stores.name as storeName",
      ])
      .where("purchases.date", "=", date)
      .where("purchases.paidTotal", "=", amount)
      .where("purchases.source", "!=", "pix")
      .where(({ not, exists, selectFrom }) =>
        not(
          exists(selectFrom("transfers").select("transfers.id").whereRef("transfers.purchaseId", "=", "purchases.id")),
        ),
      )
      .execute();

    const best = nearestInTime(candidates, time);
    if (!best) return null;
    return {
      purchaseId: best.slug,
      store: best.storeName ?? "",
      date: best.date,
      time: best.time ?? "",
      totalPaid: best.paidTotal,
      itemCount: best.itemCount,
    };
  }

  private buildInstructions(text: string | undefined): string {
    const lines = [this.deps.prompt];
    if (text) {
      lines.push(
        "",
        "The owner also pasted this text from their banking app. Where the text and the image disagree,",
        "trust the text — it is copied, not read off a screenshot:",
        "---",
        text,
        "---",
      );
    }
    lines.push(
      "",
      `Valid categories: ${CATEGORIES.join(", ")}. Pick the one that fits what the money was most likely`,
      `spent on, judging by the destination's name — a supermarket is "grocery", a bakery is "bakery",`,
      `a butcher is "meat". Use "other" when the name tells you nothing.`,
      "",
      "Rules for the fields:",
      `- transactionId: the bank's end-to-end ID (Pix E2E, usually starting with "E" and 32 characters`,
      "  long). It is the dedup key, so copy it exactly; if the receipt truly has none, build one from",
      "  the date, amount and destination instead of inventing a random string.",
      `- amount: a number in BRL, e.g. 128.4 for "R$ 128,40". Never a string.`,
      `- date: "YYYY-MM-DD". time: "HH:MM:SS" or null if the receipt does not say.`,
      "- destination/origin: name as printed; institution, agency and account null when absent. Keep any",
      '  masking the bank used (e.g. "····1234") rather than guessing the digits.',
      "- Refuse if this is a receipt for something else, an invoice, or unreadable — do not guess an amount.",
      "",
      'Respond with ONLY one JSON object, no markdown fences and no extra text, shaped {"result":<answer>}',
      "where <answer> is one of:",
      `- If it is a transfer receipt: {"status":"transfer","transactionId":<string>,"type":"pix","amount":`,
      `  <number>,"date":<string>,"time":<string|null>,"destination":{"name":<string>,"institution":`,
      `  <string|null>,"agency":<string|null>,"account":<string|null>},"origin":<same shape|null>,`,
      `  "category":<category>,"comment":<string, pt-BR, anything worth flagging about the reading>}`,
      `- If it is not: {"status":"not_a_transfer","comment":<string explaining why, pt-BR>}`,
    );
    return lines.join("\n");
  }
}

export interface Candidate {
  slug: string;
  date: string;
  time: string | null;
  paidTotal: number;
  itemCount: number;
  storeName: string | null;
}

/** The closest purchase in time wins; without a time on either side, the latest one does. */
export function nearestInTime(candidates: Candidate[], time: string | null): Candidate | undefined {
  if (candidates.length <= 1) return candidates[0];
  const target = seconds(time);
  if (target === null) {
    return [...candidates].sort((a, b) => (seconds(b.time) ?? -1) - (seconds(a.time) ?? -1))[0];
  }
  return [...candidates].sort((a, b) => distance(a.time, target) - distance(b.time, target))[0];
}

function distance(time: string | null, target: number): number {
  const value = seconds(time);
  return value === null ? Number.POSITIVE_INFINITY : Math.abs(value - target);
}

function seconds(time: string | null): number | null {
  const match = time?.match(/^(\d{2}):(\d{2})(?::(\d{2}))?/);
  if (!match) return null;
  return Number(match[1]) * 3600 + Number(match[2]) * 60 + Number(match[3] ?? 0);
}

function toTransfer(extraction: Extract<TransferExtraction, { status: "transfer" }>) {
  return {
    transactionId: extraction.transactionId,
    type: extraction.type,
    // The model can hand back more precision than money has; the DB column is numeric(12,2).
    amount: Math.round(extraction.amount * 100) / 100,
    date: extraction.date,
    time: extraction.time,
    destination: extraction.destination,
    origin: extraction.origin,
    purchaseId: null,
  };
}
