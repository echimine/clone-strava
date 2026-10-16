/** Thrown when a client sends a cursor this server did not produce. */
export class InvalidCursorError extends Error {
  constructor(message = "Invalid cursor") {
    super(message);
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * A keyset position (ADR-034 §1, §3): a sort value (a timestamp) and the row's UUID as the
 * tie-breaker. Opaque to clients: base64url of `{position}|{id}`.
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
