import { z } from "zod";
import { mediaKindSchema, type MediaKind } from "../common/enums.js";
import { ACTIVITY_MEDIA_MAX, mediaSchema } from "./media.js";

const MB = 1024 * 1024;

/** The file names of a Media's folder (ADR-037 §3). */
export const mediaFileNameSchema = z.enum(["original.jpg", "original.mp4", "poster.jpg", "thumb.jpg"]);
export type MediaFileName = z.infer<typeof mediaFileNameSchema>;

/** Content types of Media files, signed in each pre-signed `PUT`. */
export const mediaContentTypeSchema = z.enum(["image/jpeg", "video/mp4"]);
export type MediaContentType = z.infer<typeof mediaContentTypeSchema>;

export interface MediaFileSpec {
  name: MediaFileName;
  contentType: MediaContentType;
  maxBytes: number;
}

/** Every file a Media must have, with its content type and largest size (ADR-037 §3). */
export const MEDIA_FILE_SPECS = {
  photo: [
    { name: "original.jpg", contentType: "image/jpeg", maxBytes: 8 * MB },
    { name: "thumb.jpg", contentType: "image/jpeg", maxBytes: MB },
  ],
  video: [
    { name: "original.mp4", contentType: "video/mp4", maxBytes: 60 * MB },
    { name: "poster.jpg", contentType: "image/jpeg", maxBytes: MB },
    { name: "thumb.jpg", contentType: "image/jpeg", maxBytes: MB },
  ],
} as const satisfies Record<MediaKind, readonly MediaFileSpec[]>;

/** How long a Media file's pre-signed `PUT` stays valid (ADR-037 §4: 24 hours, for background uploads). */
export const MEDIA_UPLOAD_URL_EXPIRES_IN_SECONDS = 24 * 60 * 60;

export const mediaUploadFileSchema = z
  .object({
    name: mediaFileNameSchema,
    contentType: mediaContentTypeSchema,
    /** Exact size of the file about to be sent, signed: the bucket refuses any other size. */
    contentLength: z.number().int().min(1),
  })
  .meta({ id: "MediaUploadFile" });
export type MediaUploadFile = z.infer<typeof mediaUploadFileSchema>;

/**
 * `POST /v1/activities/:id/media/upload-urls` body (ADR-037 §4). `mediaId` is a UUID made by the
 * phone. `files` is exactly the kind's set of `MEDIA_FILE_SPECS` (any order), each with its content
 * type and at most its size; anything else is `422 validation_error`.
 */
export const mediaUploadUrlsRequestSchema = z
  .object({
    mediaId: z.uuid(),
    kind: mediaKindSchema,
    files: z.array(mediaUploadFileSchema).min(1).max(3),
  })
  .superRefine((request, context) => {
    const specs: readonly MediaFileSpec[] = MEDIA_FILE_SPECS[request.kind];
    const names = request.files.map((file) => file.name);
    if (names.length !== specs.length || specs.some((spec) => !names.includes(spec.name))) {
      context.addIssue({
        code: "custom",
        path: ["files"],
        message: `A ${request.kind} has exactly these files: ${specs.map((spec) => spec.name).join(", ")}`,
      });
      return;
    }
    request.files.forEach((file, index) => {
      const spec = specs.find((candidate) => candidate.name === file.name)!;
      if (file.contentType !== spec.contentType) {
        context.addIssue({
          code: "custom",
          path: ["files", index, "contentType"],
          message: `${file.name} is ${spec.contentType}`,
        });
      }
      if (file.contentLength > spec.maxBytes) {
        context.addIssue({
          code: "custom",
          path: ["files", index, "contentLength"],
          message: `${file.name} is at most ${spec.maxBytes} bytes`,
        });
      }
    });
  });
export type MediaUploadUrlsRequest = z.infer<typeof mediaUploadUrlsRequestSchema>;

/**
 * `POST /v1/activities/:id/media/upload-urls` response: one pre-signed `PUT` per requested file, in
 * the request's order. The phone sends `Content-Type` and `Content-Length` exactly as requested.
 */
export const mediaUploadUrlSchema = z
  .object({
    name: mediaFileNameSchema,
    uploadUrl: z.url(),
    expiresAt: z.iso.datetime(),
  })
  .meta({ id: "MediaUploadUrl" });
export type MediaUploadUrl = z.infer<typeof mediaUploadUrlSchema>;

export const mediaUploadUrlsResponseSchema = z.object({
  files: z.array(mediaUploadUrlSchema),
});
export type MediaUploadUrlsResponse = z.infer<typeof mediaUploadUrlsResponseSchema>;

/**
 * `POST /v1/activities/:id/media` body (ADR-037 §4): confirms a Media whose files are all in the
 * bucket. `id` is the `mediaId` of its upload URLs. Width, height and duration are the phone's;
 * `durationMs` is required for a video and null or absent for a photo. `position` is its index in
 * the wanted order (ADR-037 §8).
 */
export const confirmMediaRequestSchema = z
  .object({
    id: z.uuid(),
    kind: mediaKindSchema,
    width: z.number().int().positive(),
    height: z.number().int().positive(),
    // Nullish: the generated Swift client omits a nil optional rather than sending `null`.
    durationMs: z.number().int().nonnegative().nullish(),
    position: z
      .number()
      .int()
      .min(0)
      .max(ACTIVITY_MEDIA_MAX - 1),
  })
  .refine((request) => (request.kind === "video") === (request.durationMs != null), {
    path: ["durationMs"],
    message: "A video has a duration, a photo has none",
  });
export type ConfirmMediaRequest = z.infer<typeof confirmMediaRequestSchema>;

/** `POST /v1/activities/:id/media` response: the confirmed Media as every read gives it (ADR-037 §7). */
export const confirmMediaResponseSchema = z.object({
  media: mediaSchema,
});
export type ConfirmMediaResponse = z.infer<typeof confirmMediaResponseSchema>;
