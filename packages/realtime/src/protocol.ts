import { z } from "zod";

/**
 * Protocol version for the server -> client envelope (ADR-010 §5).
 * A client that receives an unknown version ignores the message.
 */
export const PROTOCOL_VERSION = 1;

/**
 * Server -> client event envelope.
 *
 * `data` is intentionally a loose record here: the per-event-type payload
 * shapes are defined in `events.ts`. This schema only validates the
 * transport envelope itself.
 */
export const envelopeSchema = z.object({
  v: z.literal(PROTOCOL_VERSION),
  t: z.string(),
  id: z.string(),
  data: z.record(z.string(), z.unknown()),
});
export type Envelope = z.infer<typeof envelopeSchema>;

// --- Client -> server control messages (ADR-010 §5) ---

export const subMessageSchema = z.object({
  a: z.literal("sub"),
  topic: z.string(),
});
export type SubMessage = z.infer<typeof subMessageSchema>;

export const unsubMessageSchema = z.object({
  a: z.literal("unsub"),
  topic: z.string(),
});
export type UnsubMessage = z.infer<typeof unsubMessageSchema>;

export const pingMessageSchema = z.object({
  a: z.literal("ping"),
});
export type PingMessage = z.infer<typeof pingMessageSchema>;

/** Discriminated union of every message a client may send. */
export const clientMessageSchema = z.discriminatedUnion("a", [
  subMessageSchema,
  unsubMessageSchema,
  pingMessageSchema,
]);
export type ClientMessage = z.infer<typeof clientMessageSchema>;

// --- Server -> client control messages (ADR-010 §5) ---

export const subErrorReasonSchema = z.enum(["forbidden", "limit"]);
export type SubErrorReason = z.infer<typeof subErrorReasonSchema>;

export const subOkMessageSchema = z.object({
  a: z.literal("sub:ok"),
  topic: z.string(),
});
export type SubOkMessage = z.infer<typeof subOkMessageSchema>;

export const subErrMessageSchema = z.object({
  a: z.literal("sub:err"),
  topic: z.string(),
  reason: subErrorReasonSchema,
});
export type SubErrMessage = z.infer<typeof subErrMessageSchema>;

export const pongMessageSchema = z.object({
  a: z.literal("pong"),
});
export type PongMessage = z.infer<typeof pongMessageSchema>;

/** Discriminated union of every control message the gateway may send. */
export const serverControlMessageSchema = z.discriminatedUnion("a", [
  subOkMessageSchema,
  subErrMessageSchema,
  pongMessageSchema,
]);
export type ServerControlMessage = z.infer<typeof serverControlMessageSchema>;

// --- Parsing ---

export type ParseClientMessageResult =
  | { success: true; message: ClientMessage }
  | { success: false };

/**
 * Parses a raw WebSocket frame into a `ClientMessage`.
 *
 * Never throws (ADR-010 §5: "an unreadable or unknown message is ignored,
 * never an exception"). The caller decides how to count this toward quotas.
 */
export function parseClientMessage(raw: string): ParseClientMessageResult {
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    return { success: false };
  }

  const result = clientMessageSchema.safeParse(json);
  if (!result.success) {
    return { success: false };
  }

  return { success: true, message: result.data };
}
