import { z } from "zod";

/** ADR-039 §10: the sports the Nervo generator creates Segments for; `walk` gets none. */
export const NERVO_SEGMENT_SPORTS = ["ride", "run", "hike"] as const;
export type NervoSegmentSport = (typeof NERVO_SEGMENT_SPORTS)[number];

/** `[lon, lat, altitude in meters]`, WGS 84. */
const coordinateZSchema = z.tuple([
  z.number().min(-180).max(180),
  z.number().min(-90).max(90),
  z.number().finite(),
]);

/**
 * One line of the generator's NDJSON (ADR-039 §10), read by `pnpm segments:import`. Every figure
 * comes from the generator's elevation model, never from the `ElevationService`.
 */
export const nervoSegmentLineSchema = z.object({
  /** Stable key drawn from OSM (way ids and rounded ends): the import is idempotent on it. */
  sourceKey: z.string().min(1).max(200),
  sport: z.enum(NERVO_SEGMENT_SPORTS),
  /** In French, 3–60 characters, like an athlete's Segment (ADR-039 §5). */
  name: z.string().trim().min(3).max(60),
  /** The LineStringZ, from the trough to the summit. */
  path: z.array(coordinateZSchema).min(2),
  distanceM: z.number().positive(),
  elevationGainM: z.number().nonnegative(),
  avgGrade: z.number(),
  maxGrade: z.number(),
  minAltitudeM: z.number(),
  maxAltitudeM: z.number(),
  climbCategory: z.enum(["hc", "1", "2", "3", "4"]).nullable(),
});
export type NervoSegmentLine = z.infer<typeof nervoSegmentLineSchema>;
