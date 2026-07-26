import type { ChatErrorEvent } from "@ledger/shared-types";
import { streamSSE } from "hono/streaming";
import { z } from "zod";
import { LedgerError } from "../error";
import { useLog } from "../logger";
import { createHono, zValidator } from "./index";

const chatBody = z.object({
  message: z.string().trim().min(1).max(4000),
  sessionId: z.string().min(1).optional(),
});

export const chatRoutes = createHono();

// Streams ChatStreamEvents as SSE; failures after the stream opens arrive as an `error` event,
// since the 200 header is already on the wire by then.
chatRoutes.post("/", zValidator("json", chatBody), (c) => {
  const { message, sessionId } = c.req.valid("json");
  return streamSSE(c, async (stream) => {
    try {
      for await (const event of c.env.service.chat.stream({ message, sessionId })) {
        await stream.writeSSE({ event: event.type, data: JSON.stringify(event) });
      }
    } catch (error) {
      if (!(error instanceof LedgerError)) {
        useLog()
          .withError(error instanceof Error ? error : new Error(String(error)))
          .error("Chat stream failed");
      }
      const payload: ChatErrorEvent = {
        type: "error",
        message: "O assistente está indisponível no momento. Tente novamente.",
        errorCode: "ai_unavailable",
      };
      await stream.writeSSE({ event: payload.type, data: JSON.stringify(payload) });
    }
  });
});
