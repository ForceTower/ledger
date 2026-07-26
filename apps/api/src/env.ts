import { z } from "zod";
import { type CacheClient, createCacheClient } from "./cache";
import { type LedgerDb, makeDb } from "./db";
import { useLog } from "./logger";
import { shutdownOtel } from "./otel";
import { AiClient } from "./service/ai";
import { CategorizerService, DEFAULT_CATEGORIZE_PROMPT } from "./service/categorize";
import { ChatService } from "./service/chat";
import { NotificationService } from "./service/notification";
import { DEFAULT_PHOTO_PROMPT, PhotoScanService } from "./service/photo-scan";
import { PurchaseService } from "./service/purchase";
import { ScanService } from "./service/scan";
import { DEFAULT_TRANSFER_PROMPT, TransferService } from "./service/transfer";

const envVarsSchema = z.object({
  NODE_ENV: z.enum(["development", "production"]).default("development"),
  PORT: z.coerce.number().default(3000),
  DATABASE_URL: z.string(),
  REDIS_URL: z.string().default("redis://localhost:6379"),
  API_TOKEN: z.string().min(1),
  SEFAZ_BASE_URL: z.string().default("http://nfe.sefaz.ba.gov.br/servicos/nfce/modulos/geral/"),
  // Optional: base64 Firebase service account JSON. When unset, push notifications are disabled.
  FIREBASE_SERVICE_ACCOUNT_BASE64: z.string().optional(),
  // AI (scans, the last-resort categorizer, and chat). Credential precedence: when
  // CLAUDE_CODE_OAUTH_TOKEN (`claude setup-token`) is set, everything runs through the Claude
  // Agent SDK and bills the owner's Claude subscription — an API key is ignored. Otherwise
  // ANTHROPIC_API_KEY sends the one-shot reads through the Anthropic API, billed per token
  // (the chat still runs on the Agent SDK, which then uses the same key).
  ANTHROPIC_API_KEY: z.string().optional(),
  CLAUDE_CODE_OAUTH_TOKEN: z.string().optional(),
  CLAUDE_MODEL: z.string().default("claude-haiku-4-5"),
  CLAUDE_CHAT_MODEL: z.string().default("claude-opus-5"),
  // Deciphering an abbreviation the rules missed ("T SCALA MEGA C/3R") is world knowledge about
  // Brazilian brands, so it gets a stronger model than the extraction reads. It only runs for lines
  // nothing else could place — a handful per receipt at most — and it runs while the owner waits.
  CLAUDE_CATEGORIZE_MODEL: z.string().default("claude-sonnet-5"),
  CLAUDE_PHOTO_PROMPT: z.string().default(DEFAULT_PHOTO_PROMPT),
  CLAUDE_TRANSFER_PROMPT: z.string().default(DEFAULT_TRANSFER_PROMPT),
  CLAUDE_CATEGORIZE_PROMPT: z.string().default(DEFAULT_CATEGORIZE_PROMPT),
  CLAUDE_TIMEOUT_MS: z.coerce.number().default(60_000),
  // A chat turn can run several SQL round-trips, so it gets more room than a one-shot scan.
  CLAUDE_CHAT_TIMEOUT_MS: z.coerce.number().default(180_000),
  // The keyword rules and barcode history are free; this gates only the model call behind them.
  CATEGORIZE_WITH_AI: z
    .string()
    .default("true")
    .transform((value) => value !== "false"),
});

export type EnvVars = z.infer<typeof envVarsSchema>;

export interface LedgerEnv {
  vars: EnvVars;
  db: LedgerDb;
  cache: CacheClient;
  service: {
    scan: ScanService;
    photoScan: PhotoScanService;
    transfer: TransferService;
    purchase: PurchaseService;
    categorizer: CategorizerService;
    notifications: NotificationService;
    chat: ChatService;
  };
  isDev: boolean;
  cleanup: () => Promise<void>;
}

let cached: LedgerEnv | undefined;

export async function getEnv(): Promise<LedgerEnv> {
  if (cached) return cached;

  const parsed = envVarsSchema.safeParse(process.env);
  if (!parsed.success) {
    useLog()
      .withMetadata({ issues: z.treeifyError(parsed.error) })
      .error("Invalid environment variables");
    process.exit(1);
  }
  const vars = parsed.data;

  const db = makeDb(vars.DATABASE_URL);
  const cache = createCacheClient(vars.REDIS_URL);
  const purchase = new PurchaseService({ db });
  const ai = new AiClient({
    apiKey: vars.ANTHROPIC_API_KEY || undefined,
    subscriptionToken: vars.CLAUDE_CODE_OAUTH_TOKEN || undefined,
    model: vars.CLAUDE_MODEL,
    timeoutMs: vars.CLAUDE_TIMEOUT_MS,
  });
  const categorizer = new CategorizerService({
    db,
    ai: vars.CATEGORIZE_WITH_AI
      ? new AiClient({
          apiKey: vars.ANTHROPIC_API_KEY || undefined,
          subscriptionToken: vars.CLAUDE_CODE_OAUTH_TOKEN || undefined,
          model: vars.CLAUDE_CATEGORIZE_MODEL,
          timeoutMs: vars.CLAUDE_TIMEOUT_MS,
        })
      : undefined,
    prompt: vars.CLAUDE_CATEGORIZE_PROMPT,
  });
  const scan = new ScanService({ db, cache, purchase, categorizer, sefazBaseUrl: vars.SEFAZ_BASE_URL });
  const photoScan = new PhotoScanService({ ai, prompt: vars.CLAUDE_PHOTO_PROMPT });
  const transfer = new TransferService({ db, cache, ai, purchase, prompt: vars.CLAUDE_TRANSFER_PROMPT });
  const notifications = new NotificationService({ db, serviceAccountBase64: vars.FIREBASE_SERVICE_ACCOUNT_BASE64 });
  const chat = new ChatService({
    db,
    config: { model: vars.CLAUDE_CHAT_MODEL, timeoutMs: vars.CLAUDE_CHAT_TIMEOUT_MS },
  });

  cached = {
    vars,
    db,
    cache,
    service: { scan, photoScan, transfer, purchase, categorizer, notifications, chat },
    isDev: vars.NODE_ENV === "development",
    cleanup: async () => {
      await db.destroy();
      cache.disconnect();
      await shutdownOtel();
    },
  };

  return cached;
}
