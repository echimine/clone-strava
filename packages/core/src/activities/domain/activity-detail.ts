import type { ActivityProcessingErrorCode, ActivityStats } from "@repo/contracts";
import type { ActivityRecord } from "./activity-record.js";

/**
 * An Activity as opened in its detail (ADR-033 §2): the `activities`
 * module's part only, with its official values and track fields. The
 * caller adds the author and engagement (ADR-029 §2, ADR-021 §2).
 */
export interface ActivityDetailRecord extends ActivityRecord {
  title: string;
  description: string | null;
  endedAt: Date;
  /** Only once `failed`. */
  processingError: ActivityProcessingErrorCode | null;
  /** Official values, only once `processed`. */
  stats: ActivityStats | null;
  /** polyline5 of the privacy-zoned route, null when nothing can be shown. */
  mapPolyline: string | null;
  locationName: string | null;
  updatedAt: Date;
}
