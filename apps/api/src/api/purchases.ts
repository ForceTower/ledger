import { z } from "zod";
import { createHono, errStatus, ok, zValidator } from "./index";

const listQuery = z.object({
  from: z.string().optional(),
  to: z.string().optional(),
  store: z.string().optional(),
});

const idParam = z.object({ id: z.string() });

export const purchaseRoutes = createHono();

purchaseRoutes.get("/", zValidator("query", listQuery), async (c) => {
  const filters = c.req.valid("query");
  return ok("ok", await c.env.service.purchase.list(filters));
});

purchaseRoutes.get("/:id", zValidator("param", idParam), async (c) => {
  const { id } = c.req.valid("param");
  const purchase = await c.env.service.purchase.get(id);
  if (!purchase) return errStatus(404);
  return ok("ok", purchase);
});
