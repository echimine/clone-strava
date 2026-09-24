import type { ProcessingStatus, Visibility } from "@repo/contracts";

/**
 * Public representation of an `activity` row (ADR-021 §2 rule 5: cross-
 * module references are identifiers, never Drizzle entities), returned by
 * `ActivitiesService.getMany` for other modules (`engagement`, `segments`)
 * and list screens (ADR-021 §6).
 */
export interface ActivityRecord {
  id: string;
  userId: string;
  sportTypeCode: string;
  visibility: Visibility;
  processingStatus: ProcessingStatus;
  startedAt: Date;
}
