import { isBucketKeyId } from "../activities/bucket-keys.js";

/** Bucket layout of Avatars (ADR-037 §1, §2). Keys are immutable: a new UUID for every upload. */

/** Root of every Avatar. */
export const AVATARS_BUCKET_PREFIX = "avatars/";

/** Every Avatar of a user, the current one and those left behind (ADR-021 §2 rule 7). */
export function userAvatarsPrefix(userId: string): string {
  return `${AVATARS_BUCKET_PREFIX}${userId}/`;
}

/** An Avatar, also the value of `user_profile.avatar_key` (ADR-037 §2). */
export function avatarKey(userId: string, avatarId: string): string {
  return `${userAvatarsPrefix(userId)}${avatarId}.jpg`;
}

/**
 * The owner of a key under {@link AVATARS_BUCKET_PREFIX}; `undefined` when it is not
 * `avatars/{userId}/{file}` with a UUID user id.
 */
export function parseAvatarKey(key: string): { userId: string } | undefined {
  const [root, userId, file, ...rest] = key.split("/");
  if (`${root}/` !== AVATARS_BUCKET_PREFIX || !isBucketKeyId(userId) || !file || rest.length > 0) {
    return undefined;
  }
  return { userId };
}
