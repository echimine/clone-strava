import { InvalidCursorError, isMicrosecondTimestamp } from "../../infrastructure/index.js";

/**
 * Keyset position in an athlete's Gallery (ADR-037 §9): the Activity `started_at desc, id desc`,
 * then the Media `position, created_at, id` ascending. Timestamps keep PostgreSQL's microseconds
 * (`YYYY-MM-DDTHH:MM:SS.ffffffZ`), so a page boundary never skips or repeats a Media.
 */
export interface GalleryCursor {
  activityStartedAt: string;
  activityId: string;
  position: number;
  createdAt: string;
  mediaId: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const POSITION = /^-?\d{1,10}$/;

/** Opaque to clients: base64url of the five fields joined by `|`. */
export function encodeGalleryCursor(cursor: GalleryCursor): string {
  const { activityStartedAt, activityId, position, createdAt, mediaId } = cursor;
  return Buffer.from([activityStartedAt, activityId, position, createdAt, mediaId].join("|"), "utf8").toString(
    "base64url",
  );
}

/** Throws `InvalidCursorError` on a cursor this server did not produce. */
export function decodeGalleryCursor(value: string): GalleryCursor {
  const parts = Buffer.from(value, "base64url").toString("utf8").split("|");
  const [activityStartedAt = "", activityId = "", position = "", createdAt = "", mediaId = ""] = parts;
  if (
    parts.length !== 5 ||
    !isMicrosecondTimestamp(activityStartedAt) ||
    !UUID.test(activityId) ||
    !POSITION.test(position) ||
    !isMicrosecondTimestamp(createdAt) ||
    !UUID.test(mediaId)
  ) {
    throw new InvalidCursorError("Invalid gallery cursor");
  }
  return { activityStartedAt, activityId, position: Number(position), createdAt, mediaId };
}
