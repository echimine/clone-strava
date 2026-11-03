import { z } from "zod";
import { feedAuthorSchema } from "../activities/feed.js";

/** Content type of every Avatar, signed in its pre-signed `PUT` (ADR-037 §2). */
export const AVATAR_CONTENT_TYPE = "image/jpeg";

/** Largest Avatar accepted (ADR-037 §2: 1 MB); the phone sends a 512×512 JPEG, far below. */
export const AVATAR_MAX_BYTES = 1024 * 1024;

/** How long an Avatar `avatarUrl` stays valid (ADR-037 §1: 7 days, the SigV4 maximum). */
export const AVATAR_URL_EXPIRES_IN_SECONDS = 7 * 24 * 60 * 60;

/** `POST /v1/me/avatar/upload-url` body: the exact size of the JPEG about to be sent. */
export const avatarUploadUrlRequestSchema = z.object({
  sizeBytes: z.number().int().min(1).max(AVATAR_MAX_BYTES),
});
export type AvatarUploadUrlRequest = z.infer<typeof avatarUploadUrlRequestSchema>;

/**
 * `POST /v1/me/avatar/upload-url` response (ADR-037 §2): a 15-minute pre-signed `PUT`. The phone
 * sends `Content-Type: image/jpeg` and `Content-Length: {sizeBytes}` exactly (both are signed),
 * then confirms with `PUT /v1/me/avatar { avatarId }`.
 */
export const avatarUploadUrlResponseSchema = z.object({
  avatarId: z.uuid(),
  uploadUrl: z.url(),
  expiresAt: z.iso.datetime(),
});
export type AvatarUploadUrlResponse = z.infer<typeof avatarUploadUrlResponseSchema>;

/** `PUT /v1/me/avatar` body: the `avatarId` of an upload URL whose `PUT` succeeded. */
export const setAvatarRequestSchema = z.object({
  avatarId: z.uuid(),
});
export type SetAvatarRequest = z.infer<typeof setAvatarRequestSchema>;

/** `PUT /v1/me/avatar` response: the athlete's identity as everyone now sees it. */
export const setAvatarResponseSchema = z.object({
  athlete: feedAuthorSchema,
});
export type SetAvatarResponse = z.infer<typeof setAvatarResponseSchema>;
