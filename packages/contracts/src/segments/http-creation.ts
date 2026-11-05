import { z } from "zod";

/**
 * Creating a Segment in the app (ADR-039 §5, §12, spec #249): preview, create, rename, delete,
 * favourites. The rules (length, loop, duplicate, quota) belong to the `segments` domain; only
 * shapes are checked here.
 */

/** ADR-039 §5: a Segment has one sport among those with a map. */
export const segmentCreationSportSchema = z.enum(["run", "ride", "walk", "hike"]);
export type SegmentCreationSport = z.infer<typeof segmentCreationSportSchema>;

/** ADR-039 §5: climb category, from 4 to HC; null under a score of 8,000. */
export const segmentClimbCategorySchema = z.enum(["hc", "1", "2", "3", "4"]);
export type SegmentClimbCategory = z.infer<typeof segmentClimbCategorySchema>;

/** A point of the path drawn in the Itinerary editor, in WGS 84 degrees. */
export const segmentDrawnPointSchema = z.object({
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
});

/** ADR-039 §5: required, 3 to 60 characters once trimmed, no uniqueness. */
export const segmentNameSchema = z.string().trim().min(3).max(60);

/** `POST /v1/segments/preview` body: the drawn path (Mapbox Legs and straight lines, flattened). */
export const previewSegmentRequestSchema = z.object({
  sport: segmentCreationSportSchema,
  points: z.array(segmentDrawnPointSchema).min(2).max(10_000),
});
export type PreviewSegmentRequest = z.infer<typeof previewSegmentRequestSchema>;

/** `POST /v1/segments` body: everything is recomputed by the server. */
export const createSegmentRequestSchema = previewSegmentRequestSchema.extend({ name: segmentNameSchema });
export type CreateSegmentRequest = z.infer<typeof createSegmentRequestSchema>;

/** `PATCH /v1/segments/:id` body: renaming, with no recomputation. */
export const renameSegmentRequestSchema = z.object({ name: segmentNameSchema });
export type RenameSegmentRequest = z.infer<typeof renameSegmentRequestSchema>;

/** A rule of ADR-039 §5 the drawn path breaks. */
export const segmentRuleViolationSchema = z.enum(["too_short", "too_long", "loop"]);
export type SegmentRuleViolationCode = z.infer<typeof segmentRuleViolationSchema>;

/** A Segment named in an answer: the duplicate of a preview, a rename. */
export const segmentRefSchema = z.object({ id: z.uuid(), name: z.string() });
export type SegmentRef = z.infer<typeof segmentRefSchema>;

/**
 * The resampled path (points every ~20 m as polyline6) and the `ElevationService`'s altitudes,
 * one per point: the mini-map and the elevation profile.
 */
export const segmentTrackSchema = z.object({
  polyline6: z.string().min(1),
  altitudesM: z.array(z.number()),
});
export type SegmentTrack = z.infer<typeof segmentTrackSchema>;

/** Computed once by the server (ADR-039 §5); grades in percent, to the tenth. */
export const segmentFiguresSchema = z.object({
  distanceM: z.number().nonnegative(),
  elevationGainM: z.number().nonnegative(),
  avgGradePct: z.number(),
  maxGradePct: z.number(),
  minAltitudeM: z.number(),
  maxAltitudeM: z.number(),
  climbCategory: segmentClimbCategorySchema.nullable(),
});
export type SegmentFigures = z.infer<typeof segmentFiguresSchema>;

/**
 * `POST /v1/segments/preview` response: nothing is written. `violations` lists the broken
 * length and loop rules, `duplicate` the existing Segment of the same sport matching it both
 * ways, `quotaLeft` the creations left over the rolling 24 h.
 */
export const segmentPreviewSchema = segmentFiguresSchema.extend({
  track: segmentTrackSchema,
  violations: z.array(segmentRuleViolationSchema),
  duplicate: segmentRefSchema.nullable(),
  quotaLeft: z.number().int().nonnegative(),
});
export type SegmentPreview = z.infer<typeof segmentPreviewSchema>;

/** `POST /v1/segments` `201` response. */
export const createdSegmentSchema = segmentFiguresSchema.extend({
  id: z.uuid(),
  name: z.string(),
  sport: segmentCreationSportSchema,
  verified: z.boolean(),
  track: segmentTrackSchema,
  createdAt: z.iso.datetime(),
});
export type CreatedSegment = z.infer<typeof createdSegmentSchema>;

/** `GET /v1/me/segment-favorites` query: opaque keyset cursor. */
export const listSegmentFavoritesQuerySchema = z.object({
  cursor: z.string().min(1).max(200).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});
export type ListSegmentFavoritesQuery = z.infer<typeof listSegmentFavoritesQuerySchema>;

/** One of my starred Segments (Plus › « Segments »). */
export const segmentFavoriteSchema = z.object({
  id: z.uuid(),
  sport: segmentCreationSportSchema,
  name: z.string(),
  verified: z.boolean(),
  distanceM: z.number().nonnegative(),
  avgGradePct: z.number(),
  climbCategory: segmentClimbCategorySchema.nullable(),
  /** My fastest valid Effort, whatever its visibility; null without any. */
  myBestTimeS: z.number().int().nonnegative().nullable(),
});
export type SegmentFavorite = z.infer<typeof segmentFavoriteSchema>;

/** `GET /v1/me/segment-favorites` response: most recently starred first. */
export const listSegmentFavoritesResponseSchema = z.object({
  items: z.array(segmentFavoriteSchema),
  nextCursor: z.string().min(1).nullable(),
});
export type ListSegmentFavoritesResponse = z.infer<typeof listSegmentFavoritesResponseSchema>;
