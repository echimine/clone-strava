/** Keyset position in an Activity's comments (ADR-034 §3): `created_at desc, id desc`. */
export interface CommentCursor {
  createdAt: Date;
  id: string;
}

/** Thrown when a client sends a cursor this server did not produce. */
export class InvalidCommentCursorError extends Error {
  constructor() {
    super("Invalid comment cursor");
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Opaque to clients: base64url of `{ISO createdAt}|{id}`. */
export function encodeCommentCursor(cursor: CommentCursor): string {
  return Buffer.from(`${cursor.createdAt.toISOString()}|${cursor.id}`, "utf8").toString("base64url");
}

export function decodeCommentCursor(value: string): CommentCursor {
  const [iso, id, ...rest] = Buffer.from(value, "base64url").toString("utf8").split("|");
  const createdAt = new Date(iso ?? "");
  if (rest.length > 0 || !id || !UUID.test(id) || Number.isNaN(createdAt.getTime())) {
    throw new InvalidCommentCursorError();
  }
  return { createdAt, id };
}
