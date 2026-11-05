import { z } from "zod";

/** A Medal (ADR-039 §8): the athlete's 1st, 2nd, 3rd time at the date of the Activity. */
export const medalSchema = z.enum(["gold", "silver", "bronze"]);
export type Medal = z.infer<typeof medalSchema>;

/**
 * « Performances » of an Activity card (ADR-039 §12): its Medals, Best efforts not removed and
 * Efforts added up, with the privacy-zone filter of the viewer. Never stored.
 */
export const medalCountsSchema = z.object({
  gold: z.number().int().nonnegative(),
  silver: z.number().int().nonnegative(),
  bronze: z.number().int().nonnegative(),
});
export type MedalCounts = z.infer<typeof medalCountsSchema>;

/** One Best effort of « Résultats » (ADR-039 §3, §12). */
export const activityBestEffortResultSchema = z.object({
  /** Meters; the half marathon is 21,097.5. */
  distanceM: z.number().positive(),
  elapsedTimeMs: z.number().int().nonnegative(),
  medal: medalSchema.nullable(),
  /** The athlete's first time over this distance. */
  isFirst: z.boolean(),
  /** Still the athlete's Record over this distance. */
  isCurrentRecord: z.boolean(),
  /** « Retirer ce temps de mes meilleurs efforts »: the author only. */
  removable: z.boolean(),
});
export type ActivityBestEffortResult = z.infer<typeof activityBestEffortResultSchema>;

/** One Effort of « Résultats », in trace order (ADR-039 §6, §8, §12). */
export const activitySegmentEffortResultSchema = z.object({
  id: z.uuid(),
  segment: z.object({
    id: z.uuid(),
    name: z.string(),
    distanceM: z.number().nonnegative(),
    verified: z.boolean(),
  }),
  elapsedTimeS: z.number().int().nonnegative(),
  medal: medalSchema.nullable(),
  /** The athlete's first Effort on this Segment. */
  isFirstPass: z.boolean(),
  /** Its athlete is currently the Segment's Local Legend (Tous): the laurel crown. */
  localLegend: z.boolean(),
  /** The Segment's start (WGS 84), where the ribbon goes on the map. */
  startPoint: z.object({ lat: z.number(), lon: z.number() }),
});
export type ActivitySegmentEffortResult = z.infer<typeof activitySegmentEffortResultSchema>;

/**
 * `GET /v1/activities/:id/results` (ADR-039 §12): « Résultats » of an Activity, same rights as its
 * detail. Efforts in the privacy zone are left out for everyone but the author.
 */
export const activityResultsSchema = z.object({
  /** The Segments are still being looked for: no matching yet, or an older matching version. */
  matchingInProgress: z.boolean(),
  /** A pool swim's pool length in meters (« bassin de 25 m »), null otherwise. */
  poolLengthM: z.number().positive().nullable(),
  /** Every Best effort not removed, shortest distance first. */
  bestEfforts: z.array(activityBestEffortResultSchema),
  efforts: z.array(activitySegmentEffortResultSchema),
});
export type ActivityResults = z.infer<typeof activityResultsSchema>;
