import { CATEGORIES } from "@ledger/shared-types";
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

const createBody = z.object({
  date: isoDate,
  time: z
    .string()
    .regex(/^\d{2}:\d{2}:\d{2}$/)
    .nullable()
    .default(null),
  store: z.string().trim().min(1),
  paymentMethod: z.string().trim().min(1).nullable().default(null),
  items: z
    .array(
      z.object({
        description: z.string().trim().min(1),
        category: z.enum(CATEGORIES),
        quantity: z.number().int().positive(),
        unitPrice: z.number().nonnegative(),
      }),
    )
    .min(1),
});

export const purchaseRoutes = createHono();

purchaseRoutes.get("/", zValidator("query", listQuery), async (c) => {
  const filters = c.req.valid("query");
  return ok("ok", await c.env.service.purchase.list(filters));
});

// A purchase the owner typed instead of scanning — the confirmed half of `POST /scan/entry`.
purchaseRoutes.post("/", zValidator("json", createBody), async (c) => {
  const purchase = await c.env.service.purchase.create(c.req.valid("json"));
  return ok("Purchase saved.", purchase);
});

purchaseRoutes.get("/:id", zValidator("param", idParam), async (c) => {
  const { id } = c.req.valid("param");
  const purchase = await c.env.service.purchase.get(id);
  if (!purchase) return errStatus(404);
  return ok("ok", purchase);
});
