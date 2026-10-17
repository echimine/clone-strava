import type { ClientMessage } from "@repo/realtime";
import type { ConnectionState } from "./connection-state.js";
import {
  MAX_MESSAGES_PER_WINDOW,
  MAX_TOPICS_PER_CONNECTION,
  MESSAGE_WINDOW_MS,
} from "./quotas.js";

/**
 * Records an inbound message (well-formed or not, ADR-010 §5: "an unreadable
 * or unknown message is ignored, but counted toward the quota") and reports
 * whether the connection is still within its rate limit.
 */
export function recordMessageAndCheckQuota(state: ConnectionState, now: number): boolean {
  const windowStart = now - MESSAGE_WINDOW_MS;
  state.messageTimestamps = state.messageTimestamps.filter((t) => t > windowStart);
  state.messageTimestamps.push(now);
  state.lastMessageAt = now;
  return state.messageTimestamps.length <= MAX_MESSAGES_PER_WINDOW;
}

export type SubResult = "ok" | "forbidden" | "limit";

/** Checks a subscription grant for `topic` and the connection's user (ADR-034 §5). */
export type GrantVerifier = (grant: string, topic: string, userId: string) => boolean;

const noGrantAccepted: GrantVerifier = () => false;

/**
 * Applies a `sub` message (ADR-010 §4): a topic is accepted when it is in the
 * token, or when `grant` verifies for it (ADR-034 §5), and only up to
 * `MAX_TOPICS_PER_CONNECTION` (ADR-010 §9).
 * Idempotent: re-subscribing to an already-subscribed topic always succeeds.
 */
export function handleSubMessage(
  state: ConnectionState,
  topic: string,
  grant?: string,
  verifyGrant: GrantVerifier = noGrantAccepted,
): SubResult {
  const allowed =
    state.claims.topics.includes(topic) ||
    (grant !== undefined && verifyGrant(grant, topic, state.claims.sub));
  if (!allowed) {
    return "forbidden";
  }
  if (!state.topics.has(topic) && state.topics.size >= MAX_TOPICS_PER_CONNECTION) {
    return "limit";
  }
  state.topics.add(topic);
  return "ok";
}

/** Applies an `unsub` message. Idempotent, no-op if not subscribed. */
export function handleUnsubMessage(state: ConnectionState, topic: string): void {
  state.topics.delete(topic);
}

export type HandledMessage =
  | { kind: "sub"; topic: string; result: SubResult }
  | { kind: "unsub"; topic: string }
  | { kind: "ping" };

/** Dispatches a parsed `ClientMessage` to the matching pure handler. */
export function handleClientMessage(
  state: ConnectionState,
  message: ClientMessage,
  verifyGrant: GrantVerifier = noGrantAccepted,
): HandledMessage {
  switch (message.a) {
    case "sub":
      return {
        kind: "sub",
        topic: message.topic,
        result: handleSubMessage(state, message.topic, message.grant, verifyGrant),
      };
    case "unsub":
      handleUnsubMessage(state, message.topic);
      return { kind: "unsub", topic: message.topic };
    case "ping":
      return { kind: "ping" };
  }
}
