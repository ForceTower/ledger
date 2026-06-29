import { z } from "zod";
import { createHono, ok, zValidator } from "./index";

const barcodeParam = z.object({ barcode: z.string() });

export const productRoutes = createHono();

productRoutes.get("/:barcode/prices", zValidator("param", barcodeParam), async (c) => {
  const { barcode } = c.req.valid("param");
  return ok("ok", await c.env.service.purchase.prices(barcode));
});
