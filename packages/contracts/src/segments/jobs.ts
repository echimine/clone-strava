import { z } from "zod";
import { requestIdFieldSchema } from "../common/request-id.js";

/** `segments` queue (ADR-011, ADR-021 §5). */
export const SEGMENTS_QUEUE_NAME = "segments";
/** `match-segments` job (ADR-011, ADR-019 §8), enqueued after `process-activity`. */
export const MATCH_SEGMENTS_JOB_NAME = "match-segments";

/** Deterministic job id derived from the entity (ADR-011 §2, ADR-019 §8). */
export function matchSegmentsJobId(activityId: string): string {
  return `match-segments:${activityId}`;
}

/** `match-segments` job payload (ADR-019 §8). */
export const matchSegmentsJobSchema = z.object({
  activityId: z.uuid(),
  userId: z.uuid(),
  requestId: requestIdFieldSchema,
});
export type MatchSegmentsJob = z.infer<typeof matchSegmentsJobSchema>;
