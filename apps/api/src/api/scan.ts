import status from "http-status";
import { z } from "zod";
import { LedgerError } from "../error";
import { createHono, ok, zValidator } from "./index";

const scanBody = z.object({ url: z.string().min(1) });
const keyChallengeBody = z.object({
  accessKey: z
    .string()
    .trim()
    .regex(/^\d{44}$/),
});
const keyScanBody = z.object({ challengeId: z.string().min(1), captcha: z.string().trim().min(1) });

export const scanRoutes = createHono();

scanRoutes.post("/", zValidator("json", scanBody), async (c) => {
  const { url } = c.req.valid("json");
  const result = await c.env.service.scan.scan(url);
  const message = result.status === "duplicate" ? "Purchase already recorded." : "Purchase saved.";
  return ok(message, result);
});

// The fallback for `qr_rejected` scans: consult by bare access key, with the owner answering the
// SEFAZ anti-robot captcha the automated QR flow never sees.
scanRoutes.post("/key/challenge", zValidator("json", keyChallengeBody), async (c) => {
  const { accessKey } = c.req.valid("json");
  const challenge = await c.env.service.scan.startKeyChallenge(accessKey);
  return ok("Captcha challenge created.", challenge);
});

scanRoutes.post("/key", zValidator("json", keyScanBody), async (c) => {
  const { challengeId, captcha } = c.req.valid("json");
  const result = await c.env.service.scan.completeKeyChallenge(challengeId, captcha);
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
  const message =
    result.status === "identified"
      ? `${result.items.length} ${result.items.length === 1 ? "item" : "items"} identified.`
      : "Photo rejected by the AI.";
  return ok(message, result);
});

// The owner describing a purchase in their own words. The print is optional evidence, so either
// field alone is enough and the service rejects the request that carries neither.
scanRoutes.post("/entry", async (c) => {
  const body = await c.req.parseBody();
  const draft = await c.env.service.entry.interpret({
    image: body.image instanceof File ? body.image : undefined,
    text: typeof body.text === "string" ? body.text : undefined,
  });
  return ok("Entry drafted.", draft);
});

// Banks put the amount in the screenshot, in the text the owner copied, or both — either field
// alone is enough, and the service rejects the request that carries neither.
scanRoutes.post("/transfer", async (c) => {
  const body = await c.req.parseBody();
  const result = await c.env.service.transfer.interpret({
    image: body.image instanceof File ? body.image : undefined,
    text: typeof body.text === "string" ? body.text : undefined,
  });
  return ok("Transfer receipt interpreted.", result);
});
