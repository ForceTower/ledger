import { app } from "./app";
import { useLog } from "./logger";

const port = Number(Bun.env.PORT) || 3000;

useLog().info(`ledger API starting on http://localhost:${port}`);

// Bun closes a connection that goes `idleTimeout` seconds without traffic, and a request still
// waiting on the model sends nothing meanwhile — at the 10s default it hung up on every AI-backed
// route mid-flight. 120s clears the longest budget any handler can hold (CLAUDE_CHAT_TIMEOUT_MS).
const IDLE_TIMEOUT_SECONDS = 120;

// oxlint-disable-next-line import/no-default-export
export default {
  port,
  idleTimeout: IDLE_TIMEOUT_SECONDS,
  fetch: app.fetch,
};
