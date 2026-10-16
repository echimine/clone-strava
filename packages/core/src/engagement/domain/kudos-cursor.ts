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

/** Thrown when a client sends a cursor this server did not produce. */
export class InvalidKudosCursorError extends Error {
  constructor() {
    super("Invalid kudos cursor");
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MICROS_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/;

/** Opaque to clients: base64url of `{at}|{userId}`. */
export function encodeKudosCursor(cursor: KudosCursor): string {
  return Buffer.from(`${cursor.at}|${cursor.userId}`, "utf8").toString("base64url");
}

export function decodeKudosCursor(value: string): KudosCursor {
  const [at, userId, ...rest] = Buffer.from(value, "base64url").toString("utf8").split("|");
  if (
    rest.length > 0 ||
    !at ||
    !MICROS_UTC.test(at) ||
    Number.isNaN(new Date(at).getTime()) ||
    !userId ||
    !UUID.test(userId)
  ) {
    throw new InvalidKudosCursorError();
  }
  return { at, userId };
}
