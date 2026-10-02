import { z } from "zod";

/**
 * Raw trace stored in the bucket as `trace.json.gz` (ADR-019 §3), written
 * by the app for recorded activities and by the worker for imported ones
 * (ADR-028 §4 step 9). Versioned: a reader rejects an unknown
 * `schemaVersion` instead of guessing.
 */
export const TRACE_SCHEMA_VERSION = 1;

export const tracePointSchema = z.object({
  /** UTC epoch milliseconds. */
  timestampMs: z.number().int().nonnegative(),
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
  elevationM: z.number().optional(),
  /** Horizontal accuracy reported by the GPS (recorded activities only). */
  horizontalAccuracyM: z.number().nonnegative().optional(),
  speedMs: z.number().nonnegative().optional(),
  heartRateBpm: z.number().int().positive().optional(),
  cadenceRpm: z.number().nonnegative().optional(),
});
export type TracePointV1 = z.infer<typeof tracePointSchema>;

export const traceSchema = z.object({
  schemaVersion: z.literal(TRACE_SCHEMA_VERSION),
  points: z.array(tracePointSchema),
});
export type Trace = z.infer<typeof traceSchema>;

/** Bucket key of an activity's raw trace (ADR-019 §1). */
export function activityTraceKey(userId: string, activityId: string): string {
  return `activities/${userId}/${activityId}/trace.json.gz`;
}
