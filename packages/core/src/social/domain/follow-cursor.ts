import { decodeKeysetCursor, encodeKeysetCursor, isMicrosecondTimestamp } from "../../infrastructure/index.js";

/**
 * Keyset position in a follow list (ADR-036 §1): `created_at desc`, then the
 * listed athlete's id. `at` keeps PostgreSQL's microseconds (a JS `Date`
 * would truncate them), so a page boundary never skips or repeats a row.
 */
export interface FollowCursor {
  /** `created_at` in UTC, `YYYY-MM-DDTHH:MM:SS.ffffffZ`. */
  at: string;
  athleteId: string;
}

/** Opaque to clients: base64url of `{at}|{athleteId}`, as the other keyset cursors (ADR-029 §1). */
export function encodeFollowCursor(cursor: FollowCursor): string {
  return encodeKeysetCursor(cursor.at, cursor.athleteId);
}

/** Throws `InvalidCursorError` on a cursor this server did not produce. */
export function decodeFollowCursor(value: string): FollowCursor {
  const { position, id } = decodeKeysetCursor(value, isMicrosecondTimestamp, "Invalid follow cursor");
  return { at: position, athleteId: id };
}
