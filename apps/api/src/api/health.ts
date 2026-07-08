import pkg from "../../package.json";
import { createHono, errStatus, ok } from "./index";

export const healthRoutes = createHono();

healthRoutes.get("/", async (c) => {
  try {
    const { count } = await c.env.db
      .selectFrom("purchases")
      .select((eb) => eb.fn.countAll<string>().as("count"))
      .executeTakeFirstOrThrow();
    return ok("healthy", { db: true, version: pkg.version, purchaseCount: Number(count) });
  } catch {
    return errStatus(503);
  }
});
