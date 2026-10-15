import { z } from "zod";

/**
 * Raw trace stored in the bucket as `trace.json.gz` (ADR-019 §3), written
 * by the app for recorded activities and by the worker for imported ones
 * (ADR-028 §4 step 9). Versioned: a reader rejects an unknown
 * `schemaVersion` instead of guessing. v2 adds the Pauses of a Recording
 * (ADR-031 §12); v1 is gone, imported traces have no Pause.
 */
export const TRACE_SCHEMA_VERSION = 2;

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
export type TracePoint = z.infer<typeof tracePointSchema>;

/** A Pause of a Recording (ADR-031 §4, §12): no kind, manual and automatic look the same. */
export const tracePauseSchema = z.object({
  /** UTC epoch milliseconds. */
  startMs: z.number().int().nonnegative(),
  /** UTC epoch milliseconds. */
  endMs: z.number().int().nonnegative(),
});
export type TracePause = z.infer<typeof tracePauseSchema>;

export const traceSchema = z
  .object({
    schemaVersion: z.literal(TRACE_SCHEMA_VERSION),
    /** One flat list, Pauses or not: the route stays one line (ADR-031 §12). */
    points: z.array(tracePointSchema),
    pauses: z.array(tracePauseSchema),
  })
  .superRefine((trace, ctx) => {
    trace.pauses.forEach((pause, index) => {
      const issue = pauseIssue(pause, trace.points);
      if (issue) {
        ctx.addIssue({ code: "custom", path: ["pauses", index], message: issue });
      }
      const previous = trace.pauses[index - 1];
      if (previous && pause.startMs < previous.endMs) {
        ctx.addIssue({
          code: "custom",
          path: ["pauses", index],
          message: "Pauses must be ordered and must not overlap",
        });
      }
    });
  });
export type Trace = z.infer<typeof traceSchema>;

/**
 * A Pause lies between two points (ADR-031 §12): at least one point at or
 * before its start, one at or after its end, and none strictly inside. A
 * point may carry the start or end timestamp exactly (an automatic Pause
 * ends on the last point near the stop, ADR-031 §4).
 */
function pauseIssue(pause: TracePause, points: TracePoint[]): string | null {
  if (!(pause.startMs < pause.endMs)) {
    return "A Pause must end after it starts";
  }
  let before = false;
  let after = false;
  for (const { timestampMs } of points) {
    if (timestampMs > pause.startMs && timestampMs < pause.endMs) {
      return "No point may lie inside a Pause";
    }
    before ||= timestampMs <= pause.startMs;
    after ||= timestampMs >= pause.endMs;
  }
  return before && after ? null : "A Pause must lie between two points";
}

/** Bucket key of an activity's raw trace (ADR-019 §1). */
export function activityTraceKey(userId: string, activityId: string): string {
  return `activities/${userId}/${activityId}/trace.json.gz`;
}
