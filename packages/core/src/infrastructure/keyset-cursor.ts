/** Thrown when a client sends a cursor this server did not produce. */
export class InvalidCursorError extends Error {
  constructor(message = "Invalid cursor") {
    super(message);
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MICROS_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/;

/**
 * A keyset position (ADR-034 §1, §3; ADR-036 §1): a sort value (a timestamp) and the row's UUID
 * as the tie-breaker. Opaque to clients: base64url of `{position}|{id}`. Shared by every module
 * that pages by keyset (`engagement`, `social`).
 */
export function encodeKeysetCursor(position: string, id: string): string {
  return Buffer.from(`${position}|${id}`, "utf8").toString("base64url");
}

/**
 * Reads back a cursor of `encodeKeysetCursor`; `isPosition` checks the sort value. Anything
 * else throws `InvalidCursorError` with `message`.
 */
export function decodeKeysetCursor(
  value: string,
  isPosition: (position: string) => boolean,
  message: string,
): { position: string; id: string } {
  const [position, id, ...rest] = Buffer.from(value, "base64url").toString("utf8").split("|");
  if (rest.length > 0 || !position || !isPosition(position) || !id || !UUID.test(id)) {
    throw new InvalidCursorError(message);
  }
  return { position, id };
}

/**
 * A PostgreSQL timestamp in UTC with its microseconds, `YYYY-MM-DDTHH:MM:SS.ffffffZ` (a JS
 * `Date` would truncate them, so a page boundary could skip or repeat a row).
 */
export function isMicrosecondTimestamp(value: string): boolean {
  return MICROS_UTC.test(value) && !Number.isNaN(new Date(value).getTime());
}
