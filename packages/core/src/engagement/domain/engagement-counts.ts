/**
 * Counts for one activity (ADR-021 §6: "counters ... computed on read",
 * ADR-021 §2 rule 6 batch read). Keyed by `activityId` in
 * `EngagementService.getCounts`.
 */
export interface EngagementCounts {
  kudosCount: number;
  commentCount: number;
}
