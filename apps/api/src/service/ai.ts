import Anthropic from "@anthropic-ai/sdk";
import { query as agentQuery, type SDKUserMessage } from "@anthropic-ai/claude-agent-sdk";
import status from "http-status";
import { type ZodType, z } from "zod";
import { LedgerError } from "../error";
import { useLog } from "../logger";

export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

const MAX_OUTPUT_TOKENS = 4096;

// Structured-output retries are the only reason a schema-constrained, tool-less run needs a
// second turn; anything past this is the model flailing.
const MAX_AGENT_TURNS = 3;

/** The three base64-source media types the Anthropic API accepts. */
type ApiMediaType = "image/jpeg" | "image/png" | "image/webp";

// Uploads are identified by their first bytes, not by what the request claims: Bun derives a
// multipart File's `type` from the filename, so a .png name would vouch for any content at all.
const SIGNATURES: { mediaType: ApiMediaType; extension: string; matches: (head: Uint8Array) => boolean }[] = [
  { mediaType: "image/jpeg", extension: "jpg", matches: (h) => h[0] === 0xff && h[1] === 0xd8 && h[2] === 0xff },
  {
    mediaType: "image/png",
    extension: "png",
    matches: (h) => h[0] === 0x89 && h[1] === 0x50 && h[2] === 0x4e && h[3] === 0x47,
  },
  {
    mediaType: "image/webp",
    extension: "webp",
    matches: (h) => ascii(h, 0, 4) === "RIFF" && ascii(h, 8, 4) === "WEBP",
  },
];

function ascii(bytes: Uint8Array, start: number, length: number): string {
  return String.fromCharCode(...bytes.slice(start, start + length));
}

// USD per 1M tokens, keyed by model, for logging the cost of each run.
// Cache reads bill at 0.1x input; 5-minute cache writes at 1.25x input.
const MODEL_PRICING: Record<string, { input: number; output: number }> = {
  "claude-haiku-4-5": { input: 1, output: 5 },
  "claude-sonnet-5": { input: 3, output: 15 },
  "claude-opus-4-8": { input: 5, output: 25 },
  "claude-opus-5": { input: 5, output: 25 },
};

export interface AiUsage {
  inputTokens: number;
  outputTokens: number;
  /** Undefined when the model has no entry in MODEL_PRICING. */
  costUsd: number | undefined;
}

export interface AiConfig {
  /**
   * When set, one-shot runs use the Anthropic API, billed per token; otherwise they run through
   * the Claude Agent SDK on CLAUDE_CODE_OAUTH_TOKEN (the owner's Claude subscription) or, with
   * neither credential, whatever `claude` login the host has. The chat is different: it always
   * runs on the Agent SDK and prefers the subscription token — see {@link agentSubprocessEnv}.
   */
  apiKey: string | undefined;
  model: string;
  timeoutMs: number;
}

/** An upload whose bytes really are one of the three types the model can read. */
export interface ValidatedImage {
  file: File;
  extension: string;
  mediaType: ApiMediaType;
}

export interface AiRequest {
  /** The whole instruction, including the JSON shape the model must answer with. */
  instructions: string;
  /** Optional image, sent base64 on either transport. */
  image?: ValidatedImage;
  /** JSON Schema enforced by both transports (API structured outputs / Agent SDK outputFormat). */
  outputSchema: Record<string, unknown>;
}

export interface AiResponse {
  text: string;
  usage: AiUsage;
  transport: "api" | "agent";
}

/** What the services need from the model. {@link AiClient} is the real one; tests stub it. */
export interface AiRunner {
  readonly model: string;
  run(request: AiRequest): Promise<AiResponse>;
  parse<T>(text: string, schema: ZodType<T>): T;
}

/**
 * Check an upload's size and read its real type off its first bytes. `errorCode` is the caller's,
 * since each endpoint names a bad upload differently on the wire.
 */
export async function validateImage(image: File, errorCode: string): Promise<ValidatedImage> {
  if (image.size === 0 || image.size > MAX_IMAGE_BYTES) {
    throw new LedgerError(status.BAD_REQUEST, "Image must be between 1 byte and 10 MB", errorCode);
  }
  // Size is already capped above, so reading it whole to look at the first bytes is bounded.
  const head = new Uint8Array(await image.arrayBuffer()).subarray(0, 12);
  const signature = SIGNATURES.find((candidate) => candidate.matches(head));
  if (!signature) {
    throw new LedgerError(status.BAD_REQUEST, "Image must be a JPEG, PNG or WebP", errorCode);
  }
  return { file: image, extension: signature.extension, mediaType: signature.mediaType };
}

/**
 * One prompt in, one JSON answer out — over the Anthropic API when a key is configured, else the
 * Claude Agent SDK (subscription token, or the host's `claude` login in dev). Callers own the
 * prompt and the schema; this owns the transport, the timeout, and turning either failure mode
 * into the `ai_unavailable` / `ai_invalid_output` contract.
 */
export class AiClient implements AiRunner {
  private readonly anthropic: Anthropic | undefined;

  constructor(private readonly config: AiConfig) {
    this.anthropic = config.apiKey ? new Anthropic({ apiKey: config.apiKey }) : undefined;
  }

  get model(): string {
    return this.config.model;
  }

  async run(request: AiRequest): Promise<AiResponse> {
    return this.anthropic ? await this.runViaApi(this.anthropic, request) : await this.runViaAgentSdk(request);
  }

  /** Validate the model's answer against `schema`, treating anything else as an invalid output. */
  parse<T>(text: string, schema: ZodType<T>): T {
    const parsed = schema.safeParse(safeJsonParse(stripFences(text)));
    if (!parsed.success) {
      useLog()
        .withMetadata({ result: text.slice(0, 2000), issues: z.treeifyError(parsed.error) })
        .error("Model output did not match the contract");
      throw new LedgerError(status.FAILED_DEPENDENCY, "The AI returned an unexpected response", "ai_invalid_output");
    }
    return parsed.data;
  }

  private async buildContent(request: AiRequest): Promise<Anthropic.ContentBlockParam[]> {
    const content: Anthropic.ContentBlockParam[] = [];
    if (request.image) {
      const data = Buffer.from(await request.image.file.arrayBuffer()).toString("base64");
      content.push({ type: "image", source: { type: "base64", media_type: request.image.mediaType, data } });
    }
    content.push({ type: "text", text: request.instructions });
    return content;
  }

  private async runViaApi(client: Anthropic, request: AiRequest): Promise<AiResponse> {
    const content = await this.buildContent(request);

    let message: Anthropic.Message;
    try {
      message = await client.messages.create(
        {
          model: this.config.model,
          max_tokens: MAX_OUTPUT_TOKENS,
          output_config: { format: { type: "json_schema", schema: request.outputSchema } },
          messages: [{ role: "user", content }],
        },
        { timeout: this.config.timeoutMs },
      );
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      useLog().withError(err).error("Anthropic request failed");
      throw new LedgerError(status.FAILED_DEPENDENCY, "The AI service is unavailable", "ai_unavailable");
    }

    const textBlock = message.content.find((block): block is Anthropic.TextBlock => block.type === "text");
    if (message.stop_reason === "refusal" || textBlock === undefined) {
      useLog().withMetadata({ stopReason: message.stop_reason }).error("Anthropic returned no usable output");
      throw new LedgerError(status.FAILED_DEPENDENCY, "The AI returned an unexpected response", "ai_invalid_output");
    }
    return { text: textBlock.text, usage: apiUsage(this.config.model, message.usage), transport: "api" };
  }

  private async runViaAgentSdk(request: AiRequest): Promise<AiResponse> {
    const content = await this.buildContent(request);
    const abort = new AbortController();
    const timeout = setTimeout(() => abort.abort(), this.config.timeoutMs);
    try {
      const run = agentQuery({
        prompt: singleUserMessage(content),
        options: {
          model: this.config.model,
          maxTurns: MAX_AGENT_TURNS,
          tools: [],
          persistSession: false,
          abortController: abort,
          outputFormat: { type: "json_schema", schema: request.outputSchema },
          env: agentSubprocessEnv(process.env),
        },
      });
      for await (const message of run) {
        if (message.type !== "result") continue;
        if (message.subtype !== "success") {
          useLog()
            .withMetadata({ subtype: message.subtype, errors: message.errors.slice(0, 5) })
            .error("Claude Agent SDK run failed");
          throw new LedgerError(status.FAILED_DEPENDENCY, "The AI service is unavailable", "ai_unavailable");
        }
        const text =
          message.structured_output !== undefined ? JSON.stringify(message.structured_output) : message.result;
        return {
          text,
          usage: {
            inputTokens: message.usage.input_tokens,
            outputTokens: message.usage.output_tokens,
            costUsd: message.total_cost_usd,
          },
          transport: "agent",
        };
      }
      useLog().error("Claude Agent SDK run ended without a result message");
      throw new LedgerError(status.FAILED_DEPENDENCY, "The AI service is unavailable", "ai_unavailable");
    } catch (error) {
      if (error instanceof LedgerError) throw error;
      const err = error instanceof Error ? error : new Error(String(error));
      useLog().withError(err).error("Claude Agent SDK could not be executed");
      throw new LedgerError(status.FAILED_DEPENDENCY, "The AI service is unavailable", "ai_unavailable");
    } finally {
      clearTimeout(timeout);
    }
  }
}

/** The Agent SDK takes images only through its streaming input; wrap the blocks as one user turn. */
async function* singleUserMessage(content: Anthropic.ContentBlockParam[]): AsyncGenerator<SDKUserMessage> {
  yield { type: "user", message: { role: "user", content }, parent_tool_use_id: null };
}

/**
 * The Agent SDK itself prefers an API key over a subscription token, which would quietly bill the
 * API on a server configured for the owner's Claude plan. Strip the key from every Agent SDK
 * subprocess whenever the token exists; without a token, inherit the environment untouched.
 */
export function agentSubprocessEnv(
  env: Record<string, string | undefined>,
): Record<string, string | undefined> | undefined {
  if (!env.CLAUDE_CODE_OAUTH_TOKEN) return undefined;
  return { ...env, ANTHROPIC_API_KEY: undefined };
}

function apiUsage(model: string, usage: Anthropic.Usage): AiUsage {
  const price = MODEL_PRICING[model];
  const cacheRead = usage.cache_read_input_tokens ?? 0;
  const cacheWrite = usage.cache_creation_input_tokens ?? 0;
  const costUsd = price
    ? Math.round(
        ((usage.input_tokens * price.input +
          cacheRead * price.input * 0.1 +
          cacheWrite * price.input * 1.25 +
          usage.output_tokens * price.output) /
          1_000_000) *
          1e6,
      ) / 1e6
    : undefined;
  return { inputTokens: usage.input_tokens, outputTokens: usage.output_tokens, costUsd };
}

function safeJsonParse(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

/** The prompts forbid fences, but models occasionally add them anyway. */
function stripFences(text: string): string {
  return text
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/, "");
}
