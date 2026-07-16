import { z } from "zod";
import { type CacheClient, createCacheClient } from "./cache";
import { type LedgerDb, makeDb } from "./db";
import { useLog } from "./logger";
import { shutdownOtel } from "./otel";
import { NotificationService } from "./service/notification";
import { DEFAULT_PHOTO_PROMPT, PhotoScanService } from "./service/photo-scan";
import { PurchaseService } from "./service/purchase";
import { ScanService } from "./service/scan";

const envVarsSchema = z.object({
  NODE_ENV: z.enum(["development", "production"]).default("development"),
  PORT: z.coerce.number().default(3000),
  DATABASE_URL: z.string(),
  REDIS_URL: z.string().default("redis://localhost:6379"),
  API_TOKEN: z.string().min(1),
  SEFAZ_BASE_URL: z.string().default("http://nfe.sefaz.ba.gov.br/servicos/nfce/modulos/geral/"),
  // Optional: base64 Firebase service account JSON. When unset, push notifications are disabled.
  FIREBASE_SERVICE_ACCOUNT_BASE64: z.string().optional(),
  // Photo scan (POST /scan/photo): when ANTHROPIC_API_KEY is set the Anthropic API is used;
  // otherwise the Claude CLI (CLAUDE_BIN) is invoked on the host.
  ANTHROPIC_API_KEY: z.string().optional(),
  CLAUDE_BIN: z.string().default("claude"),
  CLAUDE_MODEL: z.string().default("claude-haiku-4-5"),
  CLAUDE_PHOTO_PROMPT: z.string().default(DEFAULT_PHOTO_PROMPT),
  CLAUDE_TIMEOUT_MS: z.coerce.number().default(60_000),
});

export type EnvVars = z.infer<typeof envVarsSchema>;

export interface LedgerEnv {
  vars: EnvVars;
  db: LedgerDb;
  cache: CacheClient;
  service: {
    scan: ScanService;
    photoScan: PhotoScanService;
    purchase: PurchaseService;
    notifications: NotificationService;
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
  const scan = new ScanService({ db, cache, purchase, sefazBaseUrl: vars.SEFAZ_BASE_URL });
  const photoScan = new PhotoScanService({
    apiKey: vars.ANTHROPIC_API_KEY || undefined,
    bin: vars.CLAUDE_BIN,
    model: vars.CLAUDE_MODEL,
    prompt: vars.CLAUDE_PHOTO_PROMPT,
    timeoutMs: vars.CLAUDE_TIMEOUT_MS,
  });
  const notifications = new NotificationService({ db, serviceAccountBase64: vars.FIREBASE_SERVICE_ACCOUNT_BASE64 });

  cached = {
    vars,
    db,
    cache,
    service: { scan, photoScan, purchase, notifications },
    isDev: vars.NODE_ENV === "development",
    cleanup: async () => {
      await db.destroy();
      cache.disconnect();
      await shutdownOtel();
    },
  };

  return cached;
}
