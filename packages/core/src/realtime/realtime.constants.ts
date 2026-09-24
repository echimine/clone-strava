/**
 * DI token for the `RealtimePublisher` (ADR-021 §4). A separate token from
 * `REDIS` so `RealtimeBridge` can be unit-tested with a fake publisher,
 * with no Redis connection involved (ADR-021 §4 "Testable").
 */
export const REALTIME_PUBLISHER = Symbol("REALTIME_PUBLISHER");
