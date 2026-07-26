import { describe, expect, test } from "bun:test";
import type { SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import type { ChatStreamEvent } from "@ledger/shared-types";
import { makeDb } from "../src/db";
import { LedgerError } from "../src/error";
import { ChatService, rejectStatement, shapeRows } from "../src/service/chat";

// Never connected: the stubbed agent loop below never runs the SQL tool.
const db = makeDb("postgres://unused:unused@localhost:1/unused");

const SESSION_ID = "11111111-2222-3333-4444-555555555555";

function fakeUsage() {
  return {
    cache_creation: { ephemeral_1h_input_tokens: 0, ephemeral_5m_input_tokens: 0 },
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    inference_geo: "us",
    input_tokens: 100,
    iterations: [],
    output_tokens: 50,
    output_tokens_details: { reasoning_output_tokens: 0, thinking_tokens: 0 },
    server_tool_use: { web_fetch_requests: 0, web_search_requests: 0 },
    service_tier: "standard" as const,
    speed: "standard" as const,
  };
}

function initMessage(): SDKMessage {
  return {
    type: "system",
    subtype: "init",
    apiKeySource: "oauth",
    claude_code_version: "2.0.0",
    cwd: "/",
    tools: [],
    mcp_servers: [{ name: "ledger", status: "connected" }],
    model: "claude-opus-5",
    permissionMode: "default",
    slash_commands: [],
    output_style: "default",
    skills: [],
    plugins: [],
    uuid: crypto.randomUUID(),
    session_id: SESSION_ID,
  };
}

function textDelta(text: string, parentToolUseId: string | null = null): SDKMessage {
  return {
    type: "stream_event",
    event: { type: "content_block_delta", index: 0, delta: { type: "text_delta", text } },
    parent_tool_use_id: parentToolUseId,
    uuid: crypto.randomUUID(),
    session_id: SESSION_ID,
  };
}

function toolUse(name: string, input: unknown): SDKMessage {
  return {
    type: "assistant",
    message: {
      id: "msg_1",
      type: "message",
      role: "assistant",
      model: "claude-opus-5",
      content: [{ type: "tool_use", id: "toolu_1", name, input }],
      stop_reason: "tool_use",
      stop_sequence: null,
      usage: fakeUsage(),
      container: null,
      context_management: null,
      diagnostics: null,
      stop_details: null,
    },
    parent_tool_use_id: null,
    uuid: crypto.randomUUID(),
    session_id: SESSION_ID,
  };
}

function successResult(): SDKMessage {
  return {
    type: "result",
    subtype: "success",
    duration_ms: 1200,
    duration_api_ms: 1000,
    is_error: false,
    num_turns: 2,
    result: "Você gastou R$ 100,00.",
    stop_reason: null,
    total_cost_usd: 0.0123,
    usage: fakeUsage(),
    modelUsage: {},
    permission_denials: [],
    uuid: crypto.randomUUID(),
    session_id: SESSION_ID,
  };
}

function errorResult(): SDKMessage {
  return {
    type: "result",
    subtype: "error_max_turns",
    duration_ms: 1200,
    duration_api_ms: 1000,
    is_error: true,
    num_turns: 16,
    stop_reason: null,
    total_cost_usd: 0.0123,
    usage: fakeUsage(),
    modelUsage: {},
    permission_denials: [],
    errors: ["ran out of turns"],
    uuid: crypto.randomUUID(),
    session_id: SESSION_ID,
  };
}

function serviceFor(messages: SDKMessage[]): ChatService {
  return new ChatService({
    db,
    config: { model: "claude-opus-5", timeoutMs: 5_000 },
    agentQuery: () =>
      (async function* () {
        yield* messages;
      })(),
  });
}

async function collect(service: ChatService, message = "quanto gastei este mês?"): Promise<ChatStreamEvent[]> {
  const events: ChatStreamEvent[] = [];
  for await (const event of service.stream({ message })) events.push(event);
  return events;
}

describe("ChatService.stream", () => {
  test("maps the agent run onto the wire events, in order", async () => {
    const service = serviceFor([
      initMessage(),
      toolUse("mcp__ledger__query_database", { sql: "SELECT sum(paid_total) FROM purchases" }),
      textDelta("Você gastou "),
      textDelta("R$ 100,00."),
      successResult(),
    ]);

    const events = await collect(service);

    expect(events).toHaveLength(5);
    expect(events[0]).toEqual({ type: "session", sessionId: SESSION_ID });
    expect(events[1]).toEqual({ type: "tool", sql: "SELECT sum(paid_total) FROM purchases" });
    expect(events[2]).toEqual({ type: "text", text: "Você gastou " });
    expect(events[3]).toEqual({ type: "text", text: "R$ 100,00." });
    expect(events[4]).toMatchObject({
      type: "done",
      sessionId: SESSION_ID,
      usage: { inputTokens: 100, outputTokens: 50, costUsd: 0.0123 },
    });
  });

  test("ignores subagent deltas and foreign tool calls", async () => {
    const service = serviceFor([
      initMessage(),
      textDelta("internal", "toolu_parent"),
      toolUse("mcp__other__thing", { sql: "SELECT 1" }),
      successResult(),
    ]);

    const events = await collect(service);
    expect(events.map((event) => event.type)).toEqual(["session", "done"]);
  });

  test("a failed run is an ai_unavailable error, not a silent end", async () => {
    const service = serviceFor([initMessage(), errorResult()]);

    const error = await collect(service).catch((caught: unknown) => caught);
    expect(error).toBeInstanceOf(LedgerError);
    expect((error as LedgerError).errorCode).toBe("ai_unavailable");
    expect((error as LedgerError).statusCode).toBe(424);
  });
});

describe("rejectStatement", () => {
  test("accepts a single SELECT, WITH, and a trailing semicolon", () => {
    expect(rejectStatement("SELECT 1")).toBeNull();
    expect(rejectStatement("  with t as (select 1) select * from t;")).toBeNull();
    expect(rejectStatement("-- comment\nSELECT 1")).toBeNull();
    expect(rejectStatement("/* block */ SELECT 1")).toBeNull();
  });

  test("rejects writes, stacked statements, and empty input", () => {
    expect(rejectStatement("DELETE FROM purchases")).not.toBeNull();
    expect(rejectStatement("UPDATE purchases SET paid_total = 0")).not.toBeNull();
    expect(rejectStatement("SELECT 1; DROP TABLE purchases")).not.toBeNull();
    expect(rejectStatement("   ")).not.toBeNull();
    expect(rejectStatement("-- only a comment")).not.toBeNull();
  });
});

describe("shapeRows", () => {
  test("small results pass through with a row count", () => {
    const payload = JSON.parse(shapeRows([{ total: 10 }, { total: 20 }]));
    expect(payload).toEqual({ rowCount: 2, truncated: false, rows: [{ total: 10 }, { total: 20 }] });
  });

  test("caps at 200 rows and flags the truncation", () => {
    const rows = Array.from({ length: 500 }, (_, index) => ({ index }));
    const payload = JSON.parse(shapeRows(rows));
    expect(payload.rowCount).toBe(500);
    expect(payload.truncated).toBe(true);
    expect(payload.rows).toHaveLength(200);
  });

  test("shrinks oversized payloads below the byte cap", () => {
    const rows = Array.from({ length: 200 }, (_, index) => ({ index, blob: "x".repeat(500) }));
    const text = shapeRows(rows);
    expect(text.length).toBeLessThanOrEqual(20_000);
    const payload = JSON.parse(text);
    expect(payload.truncated).toBe(true);
    expect(payload.rows.length).toBeLessThan(200);
  });
});
