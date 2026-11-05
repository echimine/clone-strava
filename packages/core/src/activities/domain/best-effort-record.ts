import type { RecordSet } from "./best-efforts.js";
import type { Medal } from "./medals.js";

/** A stored Best effort not removed (ADR-039 §3), with its Medal at the date of its Activity. */
export interface BestEffortRecord {
  activityId: string;
  recordSet: RecordSet;
  distanceM: number;
  elapsedTimeMs: number;
  startDistanceM: number;
  medal: Medal | null;
}
