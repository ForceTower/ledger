import { z } from "zod";
import { createHono, ok, zValidator } from "./index";

const scanBody = z.object({ url: z.string().min(1) });

export const scanRoutes = createHono();

scanRoutes.post("/", zValidator("json", scanBody), async (c) => {
  const { url } = c.req.valid("json");
  const result = await c.env.service.scan.scan(url);
  const message = result.status === "duplicate" ? "Purchase already recorded." : "Purchase saved.";
  return ok(message, result);
});
