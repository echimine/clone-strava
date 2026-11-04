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
  return `process-activity-${activityId}`;
}

/** `process-activity` job payload (ADR-011, ADR-019 §5). */
export const processActivityJobSchema = z.object({
  activityId: z.uuid(),
  userId: z.uuid(),
  requestId: requestIdFieldSchema,
});
export type ProcessActivityJob = z.infer<typeof processActivityJobSchema>;

/**
 * `reprocess-activity` job (ADR-033 §5): recomputes a processed Activity's official values
 * after a sport change, on the `activities` queue.
 */
export const REPROCESS_ACTIVITY_JOB_NAME = "reprocess-activity";

/**
 * One job per sport change (ADR-033 §5): a replay of the same change is deduplicated, a later
 * change (new `updated_at`) gets its own job.
 */
export function reprocessActivityJobId(activityId: string, updatedAt: Date): string {
  return `reprocess-${activityId}-${updatedAt.getTime()}`;
}

/**
 * Backfill of the Activity analysis (ADR-036 §7): one job per Activity and analysis version, so
 * a job that failed for good is not retried before the next version bump.
 */
export function reprocessAnalysisJobId(activityId: string, analysisVersion: number): string {
  return `reprocess-${activityId}-analysis-v${analysisVersion}`;
}

/**
 * « Recalculer » from the backoffice (ADR-038 §14): a new id at each click, since the id of the
 * Activity's last edit still holds the `reprocess-activity` that failed.
 */
export function recomputeActivityJobId(activityId: string, at: Date): string {
  return `reprocess-activity-${activityId}-${at.getTime()}`;
}

/** `reprocess-activity` job payload (ADR-033 §5). */
export const reprocessActivityJobSchema = z.object({
  activityId: z.uuid(),
  userId: z.uuid(),
  requestId: requestIdFieldSchema,
});
export type ReprocessActivityJob = z.infer<typeof reprocessActivityJobSchema>;

/** `imports` queue (ADR-028 §4): separate from `activities` so bulk imports never delay live recordings. */
export const IMPORTS_QUEUE_NAME = "imports";
/** `import-activity` job (ADR-028 §4). */
export const IMPORT_ACTIVITY_JOB_NAME = "import-activity";

/** Deterministic job id (ADR-011 §2, ADR-028 §9). */
export function importActivityJobId(importId: string): string {
  return `import-activity-${importId}`;
}

/** `import-activity` job payload (ADR-028 §4). */
export const importActivityJobSchema = z.object({
  importId: z.uuid(),
  userId: z.uuid(),
  requestId: requestIdFieldSchema,
});
export type ImportActivityJob = z.infer<typeof importActivityJobSchema>;
