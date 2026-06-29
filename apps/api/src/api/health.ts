import { sql } from "../db";
import { createHono, errStatus, ok } from "./index";

export const healthRoutes = createHono();

healthRoutes.get("/", async (c) => {
  try {
    await sql`select 1`.execute(c.env.db);
    return ok("healthy", { db: true });
  } catch {
    return errStatus(503);
  }
});
