import { z } from "zod";
import { createHono, errStatus, ok, zValidator } from "./index";

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD");

const listQuery = z.object({
  page: z.coerce.number().int().min(1).default(1),
  from: isoDate.optional(),
  to: isoDate.optional(),
  store: z.string().min(1).optional(),
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
