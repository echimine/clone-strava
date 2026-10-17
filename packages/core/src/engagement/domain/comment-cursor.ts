import { decodeKeysetCursor, encodeKeysetCursor } from "./keyset-cursor.js";

/** Keyset position in an Activity's comments (ADR-034 §3): `created_at desc, id desc`. */
export interface CommentCursor {
  createdAt: Date;
  id: string;
}

/** Opaque to clients: base64url of `{ISO createdAt}|{id}`. */
export function encodeCommentCursor(cursor: CommentCursor): string {
  return encodeKeysetCursor(cursor.createdAt.toISOString(), cursor.id);
}

/** Throws `InvalidCursorError` on a cursor this server did not produce. */
export function decodeCommentCursor(value: string): CommentCursor {
  const { position, id } = decodeKeysetCursor(
    value,
    (iso) => !Number.isNaN(new Date(iso).getTime()),
    "Invalid comment cursor",
  );
  return { createdAt: new Date(position), id };
}
