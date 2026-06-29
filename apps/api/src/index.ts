import { app } from "./app";
import { useLog } from "./logger";

const port = Number(Bun.env.PORT) || 3000;

useLog().info(`ledger API starting on http://localhost:${port}`);

// oxlint-disable-next-line import/no-default-export
export default {
  port,
  fetch: app.fetch,
};
