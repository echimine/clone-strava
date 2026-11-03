import { z } from "zod";
import { requestIdFieldSchema } from "../common/request-id.js";

/** `avatars` queue (ADR-037 §2, ADR-011): enqueued by `auth`, run by `apps/worker`. */
export const AVATARS_QUEUE_NAME = "avatars";
/** `copy-google-avatar` job: the Google photo becomes the Avatar, once (ADR-037 §2). */
export const COPY_GOOGLE_AVATAR_JOB_NAME = "copy-google-avatar";

/** Deterministic job id derived from the entity (ADR-011 §2): one copy per account. */
export function copyGoogleAvatarJobId(userId: string): string {
  return `copy-google-avatar-${userId}`;
}

/**
 * `copy-google-avatar` payload: the account and its Better Auth `user.image` (the `picture` of
 * Google's ID token), carried in the job because the worker does not read `auth`'s tables.
 * Only `https` URLs are fetched.
 */
export const copyGoogleAvatarJobSchema = z.object({
  userId: z.uuid(),
  imageUrl: z.url({ protocol: /^https$/ }),
  requestId: requestIdFieldSchema,
});
export type CopyGoogleAvatarJob = z.infer<typeof copyGoogleAvatarJobSchema>;
