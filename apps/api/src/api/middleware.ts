import { timingSafeEqual } from "node:crypto";
import type { Next } from "hono";
import status from "http-status";
import { LedgerError } from "../error";
import type { LedgerCtx } from "./index";

function constantTimeEqual(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  // timingSafeEqual requires equal lengths; comparing lengths first leaks nothing useful.
  return bufA.length === bufB.length && timingSafeEqual(bufA, bufB);
}

export async function authMiddleware(c: LedgerCtx, next: Next): Promise<void> {
  const header = c.req.header("Authorization");
  if (!header?.startsWith("Bearer ")) {
    throw new LedgerError(status.UNAUTHORIZED, "Missing or invalid authorization header");
  }

  const token = header.slice(7);
  if (!constantTimeEqual(token, c.env.vars.API_TOKEN)) {
    throw new LedgerError(status.UNAUTHORIZED, "Invalid token");
  }

  await next();
}
