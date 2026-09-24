import type { RealtimeTokenClaims } from "@repo/realtime";

/**
 * Per-connection state tracked by the gateway (ADR-010 §4, §9), independent
 * of the `ws` library so the quota/subscription logic in
 * `message-handling.ts` is unit-testable without a real socket.
 */
export interface ConnectionState {
  /** Claims carried by the token used to open this connection (`sub`, allowed `topics`). */
  readonly claims: RealtimeTokenClaims;
  /** Topics this connection is currently subscribed to. */
  readonly topics: Set<string>;
  /** Timestamps (ms) of inbound messages within the current rate-limit window. */
  messageTimestamps: number[];
  /** Last time (ms) an inbound message was received, for the heartbeat check. */
  lastMessageAt: number;
}

export function createConnectionState(
  claims: RealtimeTokenClaims,
  now: number,
): ConnectionState {
  return {
    claims,
    topics: new Set(),
    messageTimestamps: [],
    lastMessageAt: now,
  };
}
