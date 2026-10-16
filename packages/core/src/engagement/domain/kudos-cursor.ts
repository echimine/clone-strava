import { decodeKeysetCursor, encodeKeysetCursor } from "./keyset-cursor.js";

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

const MICROS_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/;

/** Opaque to clients: base64url of `{at}|{userId}`. */
export function encodeKudosCursor(cursor: KudosCursor): string {
  return encodeKeysetCursor(cursor.at, cursor.userId);
}

/** Throws `InvalidCursorError` on a cursor this server did not produce. */
export function decodeKudosCursor(value: string): KudosCursor {
  const { position, id } = decodeKeysetCursor(
    value,
    (at) => MICROS_UTC.test(at) && !Number.isNaN(new Date(at).getTime()),
    "Invalid kudos cursor",
  );
  return { at: position, userId: id };
}
