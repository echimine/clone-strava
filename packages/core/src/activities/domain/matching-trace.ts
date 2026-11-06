import type { TracePause } from "@repo/contracts";

/**
 * What `segments` matches on (ADR-039 §2, §6): the stored trace of a processed Activity, cleaned
 * as for its official values, before the privacy zone. Never leaves the backend.
 */
export interface ActivityMatchingTrace {
  activityId: string;
  userId: string;
  sportTypeCode: string;
  visibility: "public" | "followers" | "private";
  /** Cleaned, timestamped points; empty without a usable trace (manual entry, unreadable file). */
  points: Array<{ lat: number; lon: number; timestampMs: number }>;
  pauses: TracePause[];
  /** First and last cleaned points, the reference of the privacy zone; null without points. */
  firstPoint: { lat: number; lon: number } | null;
  lastPoint: { lat: number; lon: number } | null;
}

/** A page of processed Activities whose route passes near a path's start and end (ADR-039 §7). */
export interface ActivitiesNearPathPage {
  activities: Array<{ id: string; userId: string }>;
  /** `null` on the last page. */
  nextCursor: string | null;
}

export interface ActivitiesNearPathQuery {
  sportTypeCode: string;
  start: { lat: number; lon: number };
  end: { lat: number; lon: number };
  /** How far from the route the start and end may lie, in meters. */
  marginM: number;
  /** The last Activity id of the previous page. */
  cursor?: string;
  limit: number;
  /** Only this athlete's Activities. */
  userId?: string;
  /** Everyone's but this athlete's. */
  excludeUserId?: string;
}

/**
 * A margin in meters as degrees for an indexed `ST_DWithin` on `geometry(…, 4326)`, overestimated
 * (ADR-039 §6): the scale of a longitude degree at the highest latitude, capped at 80°.
 */
export function marginInDegrees(marginM: number, latitudes: number[]): number {
  const maxLat = Math.min(80, Math.max(...latitudes.map(Math.abs)));
  return marginM / (111_320 * Math.cos((maxLat * Math.PI) / 180));
}
