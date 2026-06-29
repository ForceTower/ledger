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
