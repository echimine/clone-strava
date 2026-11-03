import { expect } from "vitest";

/**
 * Matches the `avatarUrl` the real `StorageModule` of the specs (`https://bucket.test`, bucket
 * `test`, path style) signs for `avatarKey`: a 7-day `GET` (ADR-037 §1).
 */
export function signedAvatarUrl(avatarKey: string) {
  const path = avatarKey.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return expect.stringMatching(new RegExp(`^https://bucket\\.test/test/${path}\\?.*X-Amz-Expires=604800`));
}
