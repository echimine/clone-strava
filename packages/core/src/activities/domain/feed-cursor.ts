/** Keyset position in the feed (ADR-029): `started_at desc, id desc`. */
export interface FeedCursor {
  startedAt: Date;
  id: string;
}

/** Thrown when a client sends a cursor this server did not produce. */
export class InvalidFeedCursorError extends Error {
  constructor() {
    super("Invalid feed cursor");
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Opaque to clients: base64url of `{ISO startedAt}|{id}`. */
export function encodeFeedCursor(cursor: FeedCursor): string {
  return Buffer.from(`${cursor.startedAt.toISOString()}|${cursor.id}`, "utf8").toString("base64url");
}

export function decodeFeedCursor(value: string): FeedCursor {
  const [iso, id, ...rest] = Buffer.from(value, "base64url").toString("utf8").split("|");
  const startedAt = new Date(iso ?? "");
  if (rest.length > 0 || !id || !UUID.test(id) || Number.isNaN(startedAt.getTime())) {
    throw new InvalidFeedCursorError();
  }
  return { startedAt, id };
}
