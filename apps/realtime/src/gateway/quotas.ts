/**
 * Per-connection protection limits (ADR-010 §9).
 */

/** Maximum number of distinct topics a single connection may subscribe to. */
export const MAX_TOPICS_PER_CONNECTION = 20;

/** Maximum number of inbound messages allowed within `MESSAGE_WINDOW_MS`. */
export const MAX_MESSAGES_PER_WINDOW = 60;

/** Sliding window used to rate-limit inbound messages, in milliseconds. */
export const MESSAGE_WINDOW_MS = 10_000;

/** `WebSocketServer({ maxPayload })`: rejects frames larger than this. */
export const MAX_PAYLOAD_BYTES = 16 * 1024;

/**
 * The client sends an application-level `{a:"ping"}` every 25s (ADR-010 §9).
 * A connection silent for longer than this is considered dead and closed.
 */
export const HEARTBEAT_TIMEOUT_MS = 60_000;

/** How often the server scans connections for heartbeat timeouts. */
export const HEARTBEAT_CHECK_INTERVAL_MS = 15_000;

/** Close code used for a heartbeat timeout (no dedicated code in ADR-010 §5). */
export const CLOSE_HEARTBEAT_TIMEOUT = 1008;
