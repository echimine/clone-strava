import { z } from "zod";
import { mediaKindSchema } from "../common/enums.js";

/**
 * A Media as every response gives it (ADR-037 §7): a flat object, ordered by its array, with
 * 1-hour pre-signed `GET` URLs. `durationMs` and `posterUrl` are null for a photo. Neither the
 * object key, the position nor an expiry leaves the API. The `id` meta makes it one OpenAPI
 * component (`Media_Output`), so the app decodes a single Swift type everywhere (ADR-026).
 */
export const mediaSchema = z
  .object({
    id: z.uuid(),
    kind: mediaKindSchema,
    width: z.number().int().positive(),
    height: z.number().int().positive(),
    durationMs: z.number().int().nonnegative().nullable(),
    /** The photo (2048 px) or the video (MP4): carousel and viewer. */
    url: z.string(),
    /** The first frame of a video (1280 px), shown before it plays. */
    posterUrl: z.string().nullable(),
    /** 512 px: Gallery grid and edit strip. */
    thumbUrl: z.string(),
  })
  .meta({ id: "Media" });
export type Media = z.infer<typeof mediaSchema>;

/** How long a Media file's `url`, `posterUrl` and `thumbUrl` stay valid (ADR-037 §1: 1 hour). */
export const MEDIA_URL_EXPIRES_IN_SECONDS = 60 * 60;

/** The most Media an Activity holds (ADR-037 §4, §7). */
export const ACTIVITY_MEDIA_MAX = 8;
