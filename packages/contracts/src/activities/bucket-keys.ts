import { z } from "zod";

/**
 * Bucket layout of Activities and imports (ADR-037 §1, §11, ADR-028 §3). Every object of an
 * Activity lives under its prefix, the trace (`activityTraceKey`) and its Media included; the
 * original file of an import lives under the import's prefix (`activityImportSourceKey`). Keys
 * are immutable: a new UUID for every upload.
 */

/** Root of every Activity folder. */
export const ACTIVITIES_BUCKET_PREFIX = "activities/";
/** Root of every import folder. */
export const IMPORTS_BUCKET_PREFIX = "imports/";

/** Every Activity of a user (ADR-021 §2 rule 7: deleted with the account). */
export function userActivitiesPrefix(userId: string): string {
  return `${ACTIVITIES_BUCKET_PREFIX}${userId}/`;
}

/** Everything that belongs to an Activity: trace, Media, Media still being sent (ADR-037 §11). */
export function activityPrefix(userId: string, activityId: string): string {
  return `${userActivitiesPrefix(userId)}${activityId}/`;
}

/** The folder of one Media (ADR-037 §3), also its `activity_media.s3_key`. */
export function activityMediaPrefix(userId: string, activityId: string, mediaId: string): string {
  return `${activityPrefix(userId, activityId)}media/${mediaId}/`;
}

/** A file of a Media: `original.jpg`, `thumb.jpg`, `original.mp4` or `poster.jpg` (ADR-037 §3). */
export function activityMediaKey(
  userId: string,
  activityId: string,
  mediaId: string,
  file: string,
): string {
  return `${activityMediaPrefix(userId, activityId, mediaId)}${file}`;
}

/** Every import of a user (ADR-021 §2 rule 7: deleted with the account). */
export function userImportsPrefix(userId: string): string {
  return `${IMPORTS_BUCKET_PREFIX}${userId}/`;
}

/** The folder of one import; the import id is the Activity id (ADR-028 §1). */
export function importPrefix(userId: string, importId: string): string {
  return `${userImportsPrefix(userId)}${importId}/`;
}

/** An Activity folder, and the Media folder when the key is under one. */
export interface ActivityKeyParts {
  userId: string;
  activityId: string;
  activityPrefix: string;
  media?: { mediaId: string; prefix: string };
}

/** Every id of the layout is a UUID. */
export function isBucketKeyId(id: string | undefined): id is string {
  return z.uuid().safeParse(id).success;
}

/**
 * Splits a key under {@link ACTIVITIES_BUCKET_PREFIX}; `undefined` when it is not inside an
 * Activity folder of this layout (ids that are not UUIDs included).
 */
export function parseActivityKey(key: string): ActivityKeyParts | undefined {
  const [root, userId, activityId, folder, mediaId, ...rest] = key.split("/");
  if (
    `${root}/` !== ACTIVITIES_BUCKET_PREFIX ||
    !isBucketKeyId(userId) ||
    !isBucketKeyId(activityId) ||
    folder === undefined
  ) {
    return undefined;
  }
  const parts: ActivityKeyParts = {
    userId,
    activityId,
    activityPrefix: activityPrefix(userId, activityId),
  };
  if (folder === "media" && isBucketKeyId(mediaId) && rest.length > 0) {
    parts.media = { mediaId, prefix: activityMediaPrefix(userId, activityId, mediaId) };
  }
  return parts;
}

/** An import folder. */
export interface ImportKeyParts {
  userId: string;
  importId: string;
  prefix: string;
}

/**
 * Splits a key under {@link IMPORTS_BUCKET_PREFIX}; `undefined` when it is not inside an import
 * folder of this layout (ids that are not UUIDs included).
 */
export function parseImportKey(key: string): ImportKeyParts | undefined {
  const [root, userId, importId, file] = key.split("/");
  if (
    `${root}/` !== IMPORTS_BUCKET_PREFIX ||
    !isBucketKeyId(userId) ||
    !isBucketKeyId(importId) ||
    file === undefined
  ) {
    return undefined;
  }
  return { userId, importId, prefix: importPrefix(userId, importId) };
}
