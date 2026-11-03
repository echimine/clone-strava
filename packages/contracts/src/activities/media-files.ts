import { z } from "zod";
import type { MediaKind } from "../common/enums.js";

const MB = 1024 * 1024;

/** Content types of Media files, signed in each pre-signed `PUT`. */
export const mediaContentTypeSchema = z.enum(["image/jpeg", "video/mp4"]);
export type MediaContentType = z.infer<typeof mediaContentTypeSchema>;

/** What a file is for: the photo or video itself, a video's first frame, the 512 px preview. */
export type MediaFileRole = "original" | "poster" | "thumb";

export interface MediaFileSpec {
  role: MediaFileRole;
  name: string;
  contentType: MediaContentType;
  maxBytes: number;
}

/**
 * The single description of a Media's folder (`activityMediaPrefix`, stored as
 * `activity_media.s3_key`): every file a Media must have, all made on the iPhone, with its
 * content type and largest size (ADR-037 §3). `MEDIA_FILES` and `mediaFileNameSchema` derive
 * from it.
 */
export const MEDIA_FILE_SPECS = {
  photo: [
    { role: "original", name: "original.jpg", contentType: "image/jpeg", maxBytes: 8 * MB },
    { role: "thumb", name: "thumb.jpg", contentType: "image/jpeg", maxBytes: MB },
  ],
  video: [
    { role: "original", name: "original.mp4", contentType: "video/mp4", maxBytes: 60 * MB },
    { role: "poster", name: "poster.jpg", contentType: "image/jpeg", maxBytes: MB },
    { role: "thumb", name: "thumb.jpg", contentType: "image/jpeg", maxBytes: MB },
  ],
} as const satisfies Record<MediaKind, readonly MediaFileSpec[]>;

export type MediaFileName = (typeof MEDIA_FILE_SPECS)[MediaKind][number]["name"];

const MEDIA_FILE_NAMES = [
  ...new Set(Object.values(MEDIA_FILE_SPECS).flatMap((specs) => specs.map((spec) => spec.name))),
].sort() as [MediaFileName, ...MediaFileName[]];

/** The file names of a Media's folder. */
export const mediaFileNameSchema = z.enum(MEDIA_FILE_NAMES);

function fileOf(kind: MediaKind, role: MediaFileRole): MediaFileName | null {
  const specs: readonly MediaFileSpec[] = MEDIA_FILE_SPECS[kind];
  return (specs.find((spec) => spec.role === role)?.name as MediaFileName | undefined) ?? null;
}

/** The file of each role, by kind: `poster` is null for a photo. */
export const MEDIA_FILES = Object.fromEntries(
  (Object.keys(MEDIA_FILE_SPECS) as MediaKind[]).map((kind) => [
    kind,
    { original: fileOf(kind, "original")!, poster: fileOf(kind, "poster"), thumb: fileOf(kind, "thumb")! },
  ]),
) as Record<MediaKind, { original: MediaFileName; poster: MediaFileName | null; thumb: MediaFileName }>;
