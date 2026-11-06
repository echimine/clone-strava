import type { Medal } from "./segment-medals.js";

/** One Effort of an Activity's « Résultats » (ADR-039 §6, §8, §12). */
export interface EffortResult {
  id: string;
  segment: { id: string; name: string; distanceM: number; verified: boolean };
  elapsedTimeS: number;
  medal: Medal | null;
  /** The athlete's first Effort on this Segment that is not rejected. */
  isFirstPass: boolean;
  /** Its athlete currently holds the Segment's Local Legend (Tous). */
  localLegend: boolean;
  startPoint: { lat: number; lon: number };
}

/** « Résultats » of an Activity as `segments` knows it. */
export interface ActivitySegmentResults {
  /** Processed, and never matched or matched with an older version. */
  matchingInProgress: boolean;
  /** In trace order, rejected ones and, for anyone but the author, the privacy zone left out. */
  efforts: EffortResult[];
}
