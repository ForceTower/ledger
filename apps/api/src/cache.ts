import Redis from "ioredis";
import { useLog } from "./logger";

export type CacheClient = Redis;

export function createCacheClient(redisUrl: string): CacheClient {
  const client = new Redis(redisUrl, {
    maxRetriesPerRequest: 3,
    retryStrategy: (times) => (times > 3 ? null : Math.min(times * 200, 2000)),
  });
  // Without an error listener ioredis would throw on connection failures. Log instead so a missing
  // Redis (e.g. local dev without the container) degrades gracefully rather than crashing the process.
  client.on("error", (err) => useLog().withError(err).error("Redis client error"));
  return client;
}

const LOCK_TTL_MS = 10_000;
const ACQUIRE_TIMEOUT_MS = 12_000;
const ACQUIRE_RETRY_MS = 150;

// Delete the key only if we still own it, so an expired lock never releases the next holder's.
const RELEASE_SCRIPT = `if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("del", KEYS[1]) end return 0`;

/**
 * Run `fn` under a best-effort Redis mutex. When Redis is unreachable (local dev without the
 * container) or the lock stays contended past the timeout, `fn` runs anyway — callers rely on DB
 * unique constraints as the backstop, and losing serialization beats failing the request.
 */
export async function withLock<T>(cache: CacheClient, key: string, fn: () => Promise<T>): Promise<T> {
  const token = crypto.randomUUID();
  const acquired = await acquireLock(cache, key, token);
  try {
    return await fn();
  } finally {
    // Release failures are fine: the TTL reclaims the lock.
    if (acquired) await cache.eval(RELEASE_SCRIPT, 1, key, token).catch(() => {});
  }
}

async function acquireLock(cache: CacheClient, key: string, token: string): Promise<boolean> {
  const deadline = Date.now() + ACQUIRE_TIMEOUT_MS;
  try {
    do {
      if ((await cache.set(key, token, "PX", LOCK_TTL_MS, "NX")) === "OK") return true;
      await new Promise((resolve) => setTimeout(resolve, ACQUIRE_RETRY_MS));
    } while (Date.now() < deadline);
    useLog().withMetadata({ key }).warn("Lock still held at timeout; proceeding without it");
  } catch (error) {
    useLog().withError(error).warn("Redis unavailable; proceeding without lock");
  }
  return false;
}
