import { zValidator as zv } from "@hono/zod-validator";
import { type Context, Hono, type MiddlewareHandler } from "hono";
import status from "http-status";
import { type ZodType, z } from "zod";
import type { LedgerEnv } from "../env";

export type AppEnv = {
  Bindings: LedgerEnv;
};

export type LedgerCtx = Context<AppEnv>;
export type Middleware = MiddlewareHandler<AppEnv>;

export const createHono = () => new Hono<AppEnv>();

export const ok = <T>(message: string, data?: T, init?: ResponseInit): Response => {
  return Response.json({ ok: true, message, data: data ?? null, error: null }, init);
};

interface ErrOptions<T> {
  message: string;
  statusCode: number;
  errorCode?: string;
  errorData?: T | null;
  init?: ResponseInit;
}

export const errFromOptions = <T>(opts: ErrOptions<T>): Response => {
  return Response.json(
    { ok: false, message: opts.message, data: null, error: opts.errorData ?? null, errorCode: opts.errorCode ?? null },
    { status: opts.statusCode, ...opts.init },
  );
};

export const errStatus = (code: number, errorCode?: string): Response => {
  const resolved = status[code as keyof typeof status];
  const message = typeof resolved === "string" ? resolved : String(code);
  return errFromOptions({ message, statusCode: code, errorCode });
};

export const zValidator = <T extends ZodType>(target: "json" | "query" | "param" | "header", schema: T) =>
  zv(target, schema, (result) => {
    if (!result.success) {
      return errFromOptions({
        message: "Invalid request data",
        statusCode: status.BAD_REQUEST,
        errorData: z.treeifyError(result.error),
      });
    }
  });
