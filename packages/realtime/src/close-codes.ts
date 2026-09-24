/**
 * WebSocket close codes used by the `realtime` gateway (ADR-010 §5).
 * Range 4000-4999 is reserved for application use by RFC 6455.
 */

/** Invalid or expired token detected after opening. Client should get a new token and reconnect. */
export const CLOSE_INVALID_TOKEN = 4001;

/** Message quota exceeded. Client should reconnect with backoff. */
export const CLOSE_QUOTA_EXCEEDED = 4008;

/** Server shutdown (deployment). Client should reconnect immediately. */
export const CLOSE_SERVER_SHUTDOWN = 4009;
