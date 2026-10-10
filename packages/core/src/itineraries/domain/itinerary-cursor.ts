/**
 * Keyset position in the athlete's Itinerary list (ADR-030 §6):
 * `updated_at desc, id`. `updatedAt` keeps PostgreSQL's microseconds
 * (`YYYY-MM-DDTHH:MM:SS.ffffffZ`): a millisecond `Date` would repeat or
 * skip rows written in the same millisecond.
 */
export interface ItineraryCursor {
  updatedAt: string;
  id: string;
}

/** Thrown when a client sends a cursor this server did not produce. */
export class InvalidItineraryCursorError extends Error {
  constructor() {
    super("Invalid itinerary cursor");
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MICROSECOND_ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/;

/** Opaque to clients: base64url of `{updatedAt}|{id}`. */
export function encodeItineraryCursor(cursor: ItineraryCursor): string {
  return Buffer.from(`${cursor.updatedAt}|${cursor.id}`, "utf8").toString("base64url");
}

export function decodeItineraryCursor(value: string): ItineraryCursor {
  const [updatedAt, id, ...rest] = Buffer.from(value, "base64url").toString("utf8").split("|");
  if (
    rest.length > 0 ||
    !id ||
    !UUID.test(id) ||
    !updatedAt ||
    !MICROSECOND_ISO.test(updatedAt) ||
    Number.isNaN(Date.parse(updatedAt))
  ) {
    throw new InvalidItineraryCursorError();
  }
  return { updatedAt, id };
}
