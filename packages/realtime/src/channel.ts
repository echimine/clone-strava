import { z } from "zod";
import { envelopeSchema } from "./protocol.js";

/**
 * Single Redis channel used to broadcast events to every `realtime` gateway
 * instance (ADR-010 §6). Topics are computed by the publisher; the gateway
 * has nothing to decide.
 */
export const REALTIME_CHANNEL = "realtime:events";

/** Message published on `REALTIME_CHANNEL`. */
export const realtimeChannelMessageSchema = z.object({
  topics: z.array(z.string()),
  envelope: envelopeSchema,
});
export type RealtimeChannelMessage = z.infer<typeof realtimeChannelMessageSchema>;
