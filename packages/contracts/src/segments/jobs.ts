import { z } from "zod";
import { requestIdFieldSchema } from "../common/request-id.js";

/** `segments` queue (ADR-011, ADR-021 §5). */
export const SEGMENTS_QUEUE_NAME = "segments";
/**
 * `match-segments` job (ADR-011, ADR-019 §8, ADR-039 §6): enqueued after `process-activity`,
 * after `reprocess-activity` when the sport changed, by the Nervo import and by the sweep.
 */
export const MATCH_SEGMENTS_JOB_NAME = "match-segments";

/** Deterministic job id derived from the entity (ADR-011 §2, ADR-019 §8). */
export function matchSegmentsJobId(activityId: string): string {
  return `match-segments-${activityId}`;
}

/**
 * `reconcile-segment-matching` and the Nervo import (ADR-039 §7, §13): one job per Activity and
 * matching version, so a job that failed for good is not retried before the next version bump.
 */
export function matchSegmentsVersionJobId(activityId: string, matchingVersion: number): string {
  return `match-segments-${activityId}-v${matchingVersion}`;
}

/** `match-segments` job payload (ADR-019 §8). */
export const matchSegmentsJobSchema = z.object({
  activityId: z.uuid(),
  userId: z.uuid(),
  requestId: requestIdFieldSchema,
});
export type MatchSegmentsJob = z.infer<typeof matchSegmentsJobSchema>;

/**
 * Retro-matching of a new Segment (ADR-039 §7): pages of candidate Activities chained by cursor,
 * enqueued by `POST /v1/segments`, then by itself.
 */
export const MATCH_SEGMENT_HISTORY_JOB_NAME = "match-segment-history";

/** Deterministic, without `:` (BullMQ): `first` for the first page, the creator's Activities. */
export function matchSegmentHistoryJobId(segmentId: string, cursor: string | null): string {
  return `match-segment-history-${segmentId}-${cursor ?? "first"}`;
}

export const matchSegmentHistoryJobSchema = z.object({
  segmentId: z.uuid(),
  /** `null` on the first page; else the last Activity id of the previous page. */
  cursor: z.uuid().nullable(),
});
export type MatchSegmentHistoryJob = z.infer<typeof matchSegmentHistoryJobSchema>;

/**
 * Replays every Segment Medal of an athlete (ADR-039 §8, §13): enqueued by `activities` after an
 * Activity is deleted, since the touched Segments are unknown after the cascade.
 */
export const REPLAY_SEGMENT_MEDALS_JOB_NAME = "replay-segment-medals";

/** One job per deleted Activity. */
export function replaySegmentMedalsJobId(userId: string, deletedActivityId: string): string {
  return `replay-segment-medals-${userId}-${deletedActivityId}`;
}

export const replaySegmentMedalsJobSchema = z.object({
  userId: z.uuid(),
});
export type ReplaySegmentMedalsJob = z.infer<typeof replaySegmentMedalsJobSchema>;

/**
 * BullMQ priorities on the `segments` queue (ADR-039 §7, §13): a job without priority runs
 * first, then the lowest number. `match-segments` from the sweep or the Nervo import comes after
 * new Activities; a retro-matching page after both.
 */
export const SEGMENT_JOB_PRIORITY = {
  backgroundMatching: 10,
  history: 20,
} as const;
