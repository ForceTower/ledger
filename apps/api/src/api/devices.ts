import { z } from "zod";
import { createHono, ok, zValidator } from "./index";

const tokenBody = z.object({
  token: z.string().min(1),
  platform: z.enum(["ios", "android"]).default("ios"),
});

export const deviceRoutes = createHono();

deviceRoutes.post("/token", zValidator("json", tokenBody), async (c) => {
  const { token, platform } = c.req.valid("json");
  await c.env.service.notifications.registerToken(token, platform);
  return ok("Device token registered.");
});
