import { CATEGORIES } from "@ledger/shared-types";
import { z } from "zod";
import { createHono, ok, zValidator } from "./index";

const partyBody = z.object({
  name: z.string().min(1),
  institution: z.string().nullable().default(null),
  agency: z.string().nullable().default(null),
  account: z.string().nullable().default(null),
});

const saveBody = z.object({
  transfer: z.object({
    transactionId: z.string().min(1),
    type: z.literal("pix"),
    amount: z.number().positive(),
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    time: z
      .string()
      .regex(/^\d{2}:\d{2}:\d{2}$/)
      .nullable()
      .default(null),
    destination: partyBody,
    origin: partyBody.nullable().default(null),
    purchaseId: z.string().nullable().default(null),
  }),
  category: z.enum(CATEGORIES),
  linkedPurchaseId: z.string().nullable().default(null),
});

export const transferRoutes = createHono();

transferRoutes.post("/", zValidator("json", saveBody), async (c) => {
  const result = await c.env.service.transfer.save(c.req.valid("json"));
  return ok("Transfer saved.", result);
});
