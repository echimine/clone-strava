/** Thrown when a client sends a cursor this server did not produce. */
export class InvalidFollowCursorError extends Error {
  constructor() {
    super("Invalid follow cursor");
  }
}

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

const MICROS_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Opaque to clients: base64url of `{at}|{athleteId}`, as the other keyset cursors (ADR-029 §1). */
export function encodeFollowCursor(cursor: FollowCursor): string {
  return Buffer.from(`${cursor.at}|${cursor.athleteId}`, "utf8").toString("base64url");
}

/** Throws `InvalidFollowCursorError` on a cursor this server did not produce. */
export function decodeFollowCursor(value: string): FollowCursor {
  const [at, athleteId, ...rest] = Buffer.from(value, "base64url").toString("utf8").split("|");
  if (
    rest.length > 0 ||
    !at ||
    !MICROS_UTC.test(at) ||
    Number.isNaN(new Date(at).getTime()) ||
    !athleteId ||
    !UUID.test(athleteId)
  ) {
    throw new InvalidFollowCursorError();
  }
  return { at, athleteId };
}
