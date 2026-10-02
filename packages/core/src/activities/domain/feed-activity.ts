import type { ActivityRecord } from "./activity-record.js";

/** Stats shown on a feed card (ADR-029); null until computed or when not tracked. */
export interface FeedActivityStats {
  distanceM: number | null;
  movingTimeS: number | null;
  elapsedTimeS: number | null;
  elevationGainM: number | null;
}

/**
 * An activity as listed in a feed (ADR-029): the `activities` module's
 * part only. Authors and engagement are added by the caller (ADR-021 §6).
 */
export interface FeedActivity extends ActivityRecord {
  title: string;
  stats: FeedActivityStats;
  /** polyline5 of the privacy-zoned route, null when nothing can be shown. */
  mapPolyline: string | null;
  locationName: string | null;
}

export interface FeedActivityPage {
  items: FeedActivity[];
  nextCursor: string | null;
}
