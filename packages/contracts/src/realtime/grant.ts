import { z } from "zod";

/**
 * The only topic granted per request today (ADR-034 §5): `activity:{uuid}`, lowercase, since
 * the bridge publishes on the stored (lowercase) id and the gateway matches topics exactly.
 */
const ACTIVITY_TOPIC_PATTERN = /^activity:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** `POST /v1/realtime/grants` body (ADR-034 §5): the topic to subscribe to. */
export const realtimeGrantRequestSchema = z.object({
  topic: z.string().regex(ACTIVITY_TOPIC_PATTERN, "Expected activity:{uuid}"),
});
export type RealtimeGrantRequest = z.infer<typeof realtimeGrantRequestSchema>;

/** `POST /v1/realtime/grants` response: the signed grant and its lifetime in seconds. */
export const realtimeGrantResponseSchema = z.object({
  grant: z.string(),
  expiresInS: z.number().int(),
});
export type RealtimeGrantResponse = z.infer<typeof realtimeGrantResponseSchema>;
