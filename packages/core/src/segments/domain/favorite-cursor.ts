/**
 * Keyset position in Plus › « Segments »: `starred_at desc, segment_id`. `starredAt` keeps
 * PostgreSQL's microseconds, as the Itinerary cursor does.
 */
export interface FavoriteCursor {
  starredAt: string;
  segmentId: string;
}

/** Thrown when a client sends a cursor this server did not produce. */
export class InvalidFavoriteCursorError extends Error {
  constructor() {
    super("Invalid favourites cursor");
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MICROSECOND_ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/;

/** Opaque to clients: base64url of `{starredAt}|{segmentId}`. */
export function encodeFavoriteCursor(cursor: FavoriteCursor): string {
  return Buffer.from(`${cursor.starredAt}|${cursor.segmentId}`, "utf8").toString("base64url");
}

export function decodeFavoriteCursor(value: string): FavoriteCursor {
  const [starredAt, segmentId, ...rest] = Buffer.from(value, "base64url").toString("utf8").split("|");
  if (rest.length > 0 || !segmentId || !UUID.test(segmentId) || !starredAt || !MICROSECOND_ISO.test(starredAt)) {
    throw new InvalidFavoriteCursorError();
  }
  return { starredAt, segmentId };
}
