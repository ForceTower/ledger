import { cors } from "hono/cors";
import status from "http-status";
import { createHono, errFromOptions, errStatus, ok } from "./api";
import { deviceRoutes } from "./api/devices";
import { healthRoutes } from "./api/health";
import { authMiddleware } from "./api/middleware";
import { productRoutes } from "./api/products";
import { purchaseRoutes } from "./api/purchases";
import { scanRoutes } from "./api/scan";
import { getEnv } from "./env";
import { LedgerError } from "./error";
import { loggerContext, useLog } from "./logger";

export const app = createHono();

// Per-request child logger bound via AsyncLocalStorage.
app.use("*", (c, next) => loggerContext.with(useLog().child(), () => next()));

app.use(
  "*",
  cors({
    origin: "*",
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allowHeaders: ["Content-Type", "Authorization"],
    maxAge: 86400,
  }),
);

// Lazily build (and cache) the service registry, then expose it as c.env.
app.use("*", async (c, next) => {
  c.env = await getEnv();
  await next();
});

// Everything but the public liveness root and CORS preflight requires the bearer token.
app.use("*", (c, next) => {
  if (c.req.path === "/" || c.req.method === "OPTIONS") return next();
  return authMiddleware(c, next);
});

app.get("/", () => ok("ledger API"));
app.route("/health", healthRoutes);
app.route("/scan", scanRoutes);
app.route("/purchases", purchaseRoutes);
app.route("/products", productRoutes);
app.route("/devices", deviceRoutes);

app.notFound(() => errStatus(status.NOT_FOUND));

app.onError((err) => {
  if (err instanceof LedgerError) {
    return errFromOptions({ message: err.message, statusCode: err.statusCode, errorCode: err.errorCode });
  }

  useLog().withError(err).error("Unhandled error");
  return errFromOptions({ message: "Internal Server Error", statusCode: status.INTERNAL_SERVER_ERROR });
});
