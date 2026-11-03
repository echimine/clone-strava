import { z } from "zod";
import { mediaSchema } from "./media.js";

/** `GET /v1/athletes/:id/media` query (ADR-037 §9): opaque keyset cursor, 30 Media by default. */
export const galleryQuerySchema = z.object({
  cursor: z.string().min(1).max(400).optional(),
  limit: z.coerce.number().int().min(1).max(60).default(30),
});
export type GalleryQuery = z.infer<typeof galleryQuerySchema>;

/** The Activity a Gallery Media belongs to: the viewer's "titre · Voir l'activité ›" pill. */
export const galleryActivitySchema = z.object({
  id: z.uuid(),
  title: z.string(),
  startedAt: z.iso.datetime(),
});

/**
 * One Media of the Gallery (ADR-037 §9): the Media of every response (§7) plus its Activity, as
 * its own OpenAPI component (`GalleryItem_Output`; `.extend` does not carry the `Media` id).
 */
export const galleryItemSchema = mediaSchema.extend({ activity: galleryActivitySchema }).meta({ id: "GalleryItem" });
export type GalleryItem = z.infer<typeof galleryItemSchema>;

/**
 * `GET /v1/athletes/:id/media` response (ADR-037 §9): newest Activity first, then the Media
 * order within it; `nextCursor` is null on the last page.
 */
export const galleryResponseSchema = z.object({
  items: z.array(galleryItemSchema),
  nextCursor: z.string().min(1).nullable(),
});
export type GalleryResponse = z.infer<typeof galleryResponseSchema>;
