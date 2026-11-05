import { z } from "zod";

/**
 * The Segments mode of the Map tab (ADR-039 §12, §15): under this zoom the app draws no path
 * and asks nothing; the server refuses a zone larger than a screen at this zoom.
 */
export const SEGMENT_MAP_MIN_ZOOM = 10.5;

/** At most this many Segments per search, the most-ridden first (ADR-039 §12). */
export const SEGMENT_MAP_MAX_RESULTS = 50;

/**
 * The longest side of a phone screen at `SEGMENT_MAP_MIN_ZOOM`, in points: the screen's diagonal
 * (an iPhone Pro Max is 440 × 956 pt), so a rotated map still fits. Mapbox's world is
 * `512 × 2^zoom` points wide.
 */
export const SEGMENT_MAP_MAX_SIDE_PT = 1060;

/** `[minLng, minLat, maxLng, maxLat]` in degrees (WGS 84). */
export type SegmentMapBbox = [number, number, number, number];

/**
 * Whether a zone exceeds what one screen shows at `SEGMENT_MAP_MIN_ZOOM`, in Web Mercator on both
 * axes (`400 zone_too_large`).
 */
export function isSegmentMapZoneTooLarge([minLng, minLat, maxLng, maxLat]: SegmentMapBbox): boolean {
  const worldPt = 512 * 2 ** SEGMENT_MAP_MIN_ZOOM;
  const mercatorY = (lat: number) => Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
  const widthPt = ((maxLng - minLng) / 360) * worldPt;
  const heightPt = ((mercatorY(maxLat) - mercatorY(minLat)) / (2 * Math.PI)) * worldPt;
  return widthPt > SEGMENT_MAP_MAX_SIDE_PT || heightPt > SEGMENT_MAP_MAX_SIDE_PT;
}

/** `bbox=minLng,minLat,maxLng,maxLat`: four finite numbers, min below max, no antimeridian crossing (`422`). */
const segmentMapBboxSchema = z
  .string()
  .max(200)
  .transform((value, context): SegmentMapBbox => {
    const parts = value.split(",").map((part) => (part.trim() === "" ? Number.NaN : Number(part)));
    const [minLng, minLat, maxLng, maxLat] = parts as SegmentMapBbox;
    const valid =
      parts.length === 4 &&
      parts.every(Number.isFinite) &&
      minLng >= -180 &&
      maxLng <= 180 &&
      minLat >= -85 &&
      maxLat <= 85 &&
      minLng < maxLng &&
      minLat < maxLat;
    if (!valid) {
      context.addIssue({ code: "custom", message: "bbox must be minLng,minLat,maxLng,maxLat" });
      return z.NEVER;
    }
    return [minLng, minLat, maxLng, maxLat];
  });

/** A Segment's sport: one of the sports with a map (ADR-039 §5). */
export const segmentMapSportSchema = z.enum(["run", "ride", "walk", "hike"]);
export type SegmentMapSport = z.infer<typeof segmentMapSportSchema>;

/** `GET /v1/segments` query (ADR-039 §12): the zone, one sport or all, the viewer's favourites only. */
export const listMapSegmentsQuerySchema = z.object({
  bbox: segmentMapBboxSchema,
  sport: segmentMapSportSchema.optional(),
  favorites: z.stringbool().default(false),
});
export type ListMapSegmentsQuery = z.infer<typeof listMapSegmentsQuerySchema>;

/** One card of the Map carousel (ADR-039 §12, §15). */
export const mapSegmentSchema = z.object({
  id: z.uuid(),
  sportTypeCode: segmentMapSportSchema,
  name: z.string(),
  verified: z.boolean(),
  /** In the viewer's favourites. */
  starred: z.boolean(),
  distanceM: z.number().nonnegative(),
  /** Average grade, in percent. */
  averageGradePct: z.number(),
  /** Climb category, null under a score of 8,000 (ADR-039 §5). */
  climbCategory: z.enum(["hc", "1", "2", "3", "4"]).nullable(),
  /** Athletes with at least one Effort that stands on the Leaderboard, Blocks and Bans not filtered (§8). */
  athleteCount: z.number().int().nonnegative(),
  /** The viewer's best Effort, all visibilities, rejected ones excluded; null without one. */
  myBestTimeS: z.number().int().nonnegative().nullable(),
  /** 1st of the « Tous » Leaderboard for this viewer, only when `myBestTimeS` is null. */
  leaderTimeS: z.number().int().nonnegative().nullable(),
  /** polyline5 of the path. */
  mapPolyline: z.string(),
});
export type MapSegment = z.infer<typeof mapSegmentSchema>;

/** `GET /v1/segments` response: the Segments crossing the zone, the most athletes first. */
export const listMapSegmentsResponseSchema = z.object({
  items: z.array(mapSegmentSchema),
});
export type ListMapSegmentsResponse = z.infer<typeof listMapSegmentsResponseSchema>;
