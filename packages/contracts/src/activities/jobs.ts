import { z } from "zod";
import { requestIdFieldSchema } from "../common/request-id.js";

/** `activities` queue (ADR-011, ADR-021 §5). */
export const ACTIVITIES_QUEUE_NAME = "activities";
/** `process-activity` job (ADR-011, ADR-019 §5). */
export const PROCESS_ACTIVITY_JOB_NAME = "process-activity";

/**
 * Deterministic job id derived from the entity (ADR-011 §2): a replayed
 * enqueue for the same activity never duplicates the job.
 */
export function processActivityJobId(activityId: string): string {
  return `process-activity:${activityId}`;
}

/** `process-activity` job payload (ADR-011, ADR-019 §5). */
export const processActivityJobSchema = z.object({
  activityId: z.uuid(),
  userId: z.uuid(),
  requestId: requestIdFieldSchema,
});
export type ProcessActivityJob = z.infer<typeof processActivityJobSchema>;
