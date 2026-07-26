import {
  createSdkMcpServer,
  type Options,
  query as agentQuery,
  type SDKMessage,
  type SDKUserMessage,
  tool,
} from "@anthropic-ai/claude-agent-sdk";
import { CATEGORIES, type ChatStreamEvent } from "@ledger/shared-types";
import status from "http-status";
import { sql } from "kysely";
import { z } from "zod";
import type { LedgerDb } from "../db";
import { LedgerError } from "../error";
import { useLog } from "../logger";
import { agentSubprocessEnv } from "./ai";

const QUERY_TOOL = "query_database";
/** The Agent SDK namespaces MCP tools as mcp__<server>__<tool>. */
const QUERY_TOOL_FULL_NAME = `mcp__ledger__${QUERY_TOOL}`;

const MAX_ROWS = 200;
const MAX_PAYLOAD_CHARS = 20_000;
const STATEMENT_TIMEOUT_MS = 5_000;
// Each SQL round-trip is a turn; a genuine analysis rarely needs more than a handful.
const MAX_TURNS = 16;

/** The owner's locale — the SEFAZ integration and the app copy are Bahia/pt-BR already. */
const TIMEZONE = "America/Bahia";

export interface ChatConfig {
  model: string;
  timeoutMs: number;
}

export interface ChatParams {
  message: string;
  /** Continues an existing server-side conversation; omit to start a new one. */
  sessionId?: string;
}

/** The Agent SDK's query(), narrowed to what the chat loop consumes so tests can stub it. */
type AgentQueryFn = (args: {
  prompt: string | AsyncIterable<SDKUserMessage>;
  options?: Options;
}) => AsyncIterable<SDKMessage>;

/**
 * Conversational AI over the whole dataset. Each turn runs an agentic loop where the model reads
 * the ledger through a single read-only SQL tool; conversation memory lives in the Agent SDK's
 * server-side session, resumed by id, so clients only ever send the new message.
 */
export class ChatService {
  private readonly runQuery: AgentQueryFn;

  constructor(private readonly deps: { db: LedgerDb; config: ChatConfig; agentQuery?: AgentQueryFn }) {
    this.runQuery = deps.agentQuery ?? agentQuery;
  }

  async *stream(params: ChatParams): AsyncGenerator<ChatStreamEvent> {
    const startedAt = Date.now();
    const abort = new AbortController();
    const timeout = setTimeout(() => abort.abort(), this.deps.config.timeoutMs);

    const server = createSdkMcpServer({
      name: "ledger",
      tools: [
        tool(
          QUERY_TOOL,
          "Run one read-only SQL statement (Postgres) against the ledger database and get the rows " +
            "back as JSON. Only a single SELECT (or WITH … SELECT) is accepted. Results are capped " +
            `at ${MAX_ROWS} rows — aggregate in SQL instead of paging through raw rows.`,
          { sql: z.string().describe("A single SELECT or WITH … SELECT statement, snake_case columns.") },
          async ({ sql: statement }) => ({
            content: [{ type: "text", text: await runReadOnlyQuery(this.deps.db, statement) }],
          }),
        ),
      ],
    });

    try {
      const run = this.runQuery({
        prompt: params.message,
        options: {
          model: this.deps.config.model,
          systemPrompt: buildSystemPrompt(),
          mcpServers: { ledger: server },
          tools: [],
          allowedTools: [QUERY_TOOL_FULL_NAME],
          maxTurns: MAX_TURNS,
          resume: params.sessionId,
          includePartialMessages: true,
          abortController: abort,
          env: agentSubprocessEnv(process.env),
        },
      });

      for await (const message of run) {
        switch (message.type) {
          case "system": {
            if (message.subtype === "init") yield { type: "session", sessionId: message.session_id };
            break;
          }
          case "stream_event": {
            if (message.parent_tool_use_id !== null) break;
            const event = message.event;
            if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
              yield { type: "text", text: event.delta.text };
            }
            break;
          }
          case "assistant": {
            for (const block of message.message.content) {
              if (block.type !== "tool_use" || block.name !== QUERY_TOOL_FULL_NAME) continue;
              const input = z.object({ sql: z.string() }).safeParse(block.input);
              if (input.success) yield { type: "tool", sql: input.data.sql };
            }
            break;
          }
          case "result": {
            if (message.subtype !== "success") {
              useLog()
                .withMetadata({
                  subtype: message.subtype,
                  numTurns: message.num_turns,
                  errors: message.errors.slice(0, 5),
                })
                .error("Chat turn failed");
              throw new LedgerError(status.FAILED_DEPENDENCY, "The AI service is unavailable", "ai_unavailable");
            }
            const usage = {
              inputTokens: message.usage.input_tokens,
              outputTokens: message.usage.output_tokens,
              costUsd: message.total_cost_usd,
            };
            useLog()
              .withMetadata({
                sessionId: message.session_id,
                model: this.deps.config.model,
                numTurns: message.num_turns,
                durationMs: Date.now() - startedAt,
                ...usage,
              })
              .info("Chat turn completed");
            yield { type: "done", sessionId: message.session_id, usage, durationMs: Date.now() - startedAt };
            break;
          }
          default:
            break;
        }
      }
    } catch (error) {
      if (error instanceof LedgerError) throw error;
      const err = error instanceof Error ? error : new Error(String(error));
      useLog().withError(err).error("Chat turn could not run");
      throw new LedgerError(status.FAILED_DEPENDENCY, "The AI service is unavailable", "ai_unavailable");
    } finally {
      clearTimeout(timeout);
    }
  }
}

/**
 * Cheap gate before the real wall: the statement also runs inside a READ ONLY transaction, so
 * even something that slips past this (a semicolon inside a string literal reads as stacking, for
 * instance) cannot write. Rejections are returned as tool-result text for the model to correct.
 */
export function rejectStatement(statement: string): string | null {
  const stripped = statement
    .replace(/--[^\n]*/g, " ")
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .trim()
    .replace(/;\s*$/, "");
  if (stripped.length === 0) return "Empty statement.";
  if (stripped.includes(";")) return "Send exactly one statement — no stacked statements.";
  if (!/^(select|with)\b/i.test(stripped)) return "Only SELECT (or WITH … SELECT) statements are allowed.";
  return null;
}

/** Execute the model's SQL and shape the outcome — rows or error — as tool-result JSON. */
export async function runReadOnlyQuery(db: LedgerDb, statement: string): Promise<string> {
  const rejection = rejectStatement(statement);
  if (rejection) return JSON.stringify({ error: rejection });
  try {
    const result = await db
      .transaction()
      .setAccessMode("read only")
      .execute(async (trx) => {
        await sql.raw(`SET LOCAL statement_timeout = ${STATEMENT_TIMEOUT_MS}`).execute(trx);
        return await sql.raw<Record<string, unknown>>(statement).execute(trx);
      });
    return shapeRows(result.rows);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return JSON.stringify({ error: message });
  }
}

/** Cap what a query can push into the model's context: MAX_ROWS rows, MAX_PAYLOAD_CHARS bytes. */
export function shapeRows(allRows: Record<string, unknown>[]): string {
  let rows = allRows.slice(0, MAX_ROWS);
  for (;;) {
    const payload = JSON.stringify({ rowCount: allRows.length, truncated: rows.length < allRows.length, rows });
    if (payload.length <= MAX_PAYLOAD_CHARS || rows.length <= 1) return payload;
    rows = rows.slice(0, Math.ceil(rows.length / 2));
  }
}

function buildSystemPrompt(): string {
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: TIMEZONE, dateStyle: "short" }).format(new Date());
  return [
    "You are the assistant inside ledger, a self-hosted household-spending tracker. You answer the",
    "owner's questions about their own purchase history, which lives in a Postgres database you can",
    `read through the ${QUERY_TOOL} tool.`,
    "",
    "## Data access",
    "- One SELECT (or WITH … SELECT) per call; snake_case column names in SQL, camelCase keys in the",
    "  returned rows.",
    `- Results are capped at ${MAX_ROWS} rows. Aggregate in SQL (SUM, GROUP BY, date_trunc) instead of`,
    "  fetching raw rows; always ORDER BY and LIMIT.",
    "- Money columns are numeric BRL. Dates are DATE columns; purchases happen in the owner's",
    `  timezone (${TIMEZONE}).`,
    "",
    "## Schema",
    "- stores — id, name, legal_name, cnpj, address.",
    "- purchases — one receipt/shopping trip: id, slug (human id, e.g. 2026-03-26_atacadao_01), date,",
    "  time, source ('nfce' scanned receipt | 'manual' | 'pix' materialized transfer), store_id,",
    "  gross_total, discount_total, paid_total, item_count, taxes_total. Spending analyses sum",
    "  paid_total.",
    "- purchase_items — line items: purchase_id, seq, description (pt-BR, as printed), code, barcode",
    "  (GTIN, null for weighed produce), quantity, unit, unit_price, total, category, product_id.",
    "- products — barcode (unique GTIN), canonical_description, default_category. Price history joins",
    "  purchase_items on barcode.",
    "- payments — purchase_id, code, method (pt-BR label, e.g. 'Cartão de Crédito'), amount, change.",
    "- transfers — Pix receipts: transaction_id, amount, date, time, destination_name and other",
    "  destination_*/origin_* fields, purchase_id. A transfer's spending is already counted by the",
    "  purchase it points at — never add transfers.amount on top of purchases.paid_total.",
    "- trips — transport costs to the store: date, legs (jsonb array of {mode, cost, ...}).",
    "- donations — donated items: date, entries (jsonb), total, source_purchase_slug.",
    "",
    `Item/product categories: ${CATEGORIES.join(", ")}.`,
    "",
    "## Style",
    "- Answer in Brazilian Portuguese. Format money as R$ 1.234,56 and dates as DD/MM/YYYY in prose.",
    "- Be concise: lead with the answer, then at most a few supporting numbers. For breakdowns use",
    "  short dash lists (one item per line) — never Markdown tables or headings; the app renders only",
    "  inline styling like **bold**.",
    "- If a question is ambiguous, state the interpretation you chose in one clause and answer it.",
    "- When the data cannot answer the question, say so instead of guessing.",
    "",
    `Today is ${today}.`,
  ].join("\n");
}
