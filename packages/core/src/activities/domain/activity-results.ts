import type { Medal } from "./medals.js";

/** One Best effort of « Résultats » (ADR-039 §3, §12), not removed. */
export interface BestEffortResult {
  distanceM: number;
  elapsedTimeMs: number;
  medal: Medal | null;
  /** No earlier Activity of the athlete has a Best effort over this distance. */
  isFirst: boolean;
  /** Still the athlete's Record over this distance. */
  isCurrentRecord: boolean;
}

/** « Résultats » of an Activity as `activities` knows it: its pool and its Best efforts. */
export interface ActivityBestEffortResults {
  /** A pool swim's pool length, null otherwise. */
  poolLengthM: number | null;
  bestEfforts: BestEffortResult[];
}

/** How many times one Medal appears on one Activity. */
export interface MedalCount {
  activityId: string;
  medal: Medal;
  count: number;
}
