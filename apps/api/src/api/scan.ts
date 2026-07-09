import status from "http-status";
import { z } from "zod";
import { LedgerError } from "../error";
import { createHono, ok, zValidator } from "./index";

const scanBody = z.object({ url: z.string().min(1) });

export const scanRoutes = createHono();

scanRoutes.post("/", zValidator("json", scanBody), async (c) => {
  const { url } = c.req.valid("json");
  const result = await c.env.service.scan.scan(url);
  const message = result.status === "duplicate" ? "Purchase already recorded." : "Purchase saved.";
  return ok(message, result);
});

scanRoutes.post("/photo", async (c) => {
  const body = await c.req.parseBody();
  const image = body.image;
  if (!(image instanceof File)) {
    throw new LedgerError(status.BAD_REQUEST, "Multipart field 'image' with a photo is required", "invalid_image");
  }
  const result = await c.env.service.photoScan.identify(image);
  const message = result.status === "identified" ? "Item identified." : "Item rejected by the AI.";
  return ok(message, result);
});
