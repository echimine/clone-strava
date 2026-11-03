import { expect } from "vitest";

const escaped = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * Matches the `avatarUrl` the real `StorageModule` of the specs (`https://bucket.test`, bucket
 * `test`, path style) signs for `avatarKey`: a 7-day `GET` (ADR-037 §1).
 */
export function signedAvatarUrl(avatarKey: string) {
  return expect.stringMatching(new RegExp(`^https://bucket\\.test/test/${escaped(avatarKey)}\\?.*X-Amz-Expires=604800`));
}

/**
 * Matches the URL of `file` in the Media folder `folderKey` (`activityMediaPrefix`): a 1-hour
 * `GET` (ADR-037 §1), signed by the real `StorageModule` of the specs (bucket `test`, path style)
 * or by `InMemoryStorage` (no bucket in the path).
 */
export function signedMediaUrl(folderKey: string, file: string) {
  return expect.stringMatching(
    new RegExp(`^https://bucket\\.test/(test/)?${escaped(`${folderKey}${file}`)}\\?.*X-Amz-Expires=3600`),
  );
}
