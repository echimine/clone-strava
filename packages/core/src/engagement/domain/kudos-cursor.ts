import { decodeKeysetCursor, encodeKeysetCursor, isMicrosecondTimestamp } from "../../infrastructure/index.js";

/**
 * Keyset position in an Activity's kudos (ADR-034 §1): `created_at desc,
 * user_id desc`. `at` keeps PostgreSQL's microseconds (a JS `Date` would
 * truncate them), so a page boundary never skips or repeats a kudos.
 */
export interface KudosCursor {
  /** `created_at` in UTC, `YYYY-MM-DDTHH:MM:SS.ffffffZ`. */
  at: string;
  userId: string;
}

/** Opaque to clients: base64url of `{at}|{userId}`. */
export function encodeKudosCursor(cursor: KudosCursor): string {
  return encodeKeysetCursor(cursor.at, cursor.userId);
}

/** Throws `InvalidCursorError` on a cursor this server did not produce. */
export function decodeKudosCursor(value: string): KudosCursor {
  const { position, id } = decodeKeysetCursor(
    value,
    isMicrosecondTimestamp,
    "Invalid kudos cursor",
  );
  return { at: position, userId: id };
}
