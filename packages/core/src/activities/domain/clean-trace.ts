import type { TracePause } from "@repo/contracts";
import { haversineDistanceM } from "@repo/geo";
import { straddlesPause } from "./pauses.js";

/** Minimal point shape the cleanup needs; extra fields are kept untouched. */
export interface CleanablePoint {
  lat: number;
  lon: number;
  timestampMs: number;
  horizontalAccuracyM?: number;
}

export interface CleanTraceOptions {
  /** Points less accurate than this are dropped. */
  maxAccuracyM: number;
  /** A point reached faster than this from the previous kept point is a GPS jump. */
  maxSpeedMs: number;
  /** Pauses of a Recording: a move during a Pause is not a speed jump (ADR-031 §12). */
  pauses?: TracePause[];
}

/** GPS fixes less accurate than this are dropped (ADR-019 §5 step 3, ADR-031 §5). */
export const MAX_TRACE_ACCURACY_M = 50;

/** Plausible top speed per sport (ADR-019 §5 step 3); anything faster is a GPS jump. */
const MAX_SPEED_MS_BY_SPORT: Record<string, number> = {
  run: 12,
  walk: 5,
  hike: 5,
  swim: 5,
  ride: 35,
};
const DEFAULT_MAX_SPEED_MS = 50;

export function maxPlausibleSpeedMs(sportTypeCode: string): number {
  return MAX_SPEED_MS_BY_SPORT[sportTypeCode] ?? DEFAULT_MAX_SPEED_MS;
}

/**
 * Trace cleanup (ADR-019 §5 step 3): sorts by time, then drops points that
 * are too inaccurate, duplicate or out-of-order timestamps, and speed
 * jumps impossible for the sport (never across a Pause). Pure: the raw
 * trace in the bucket is never modified.
 */
export function cleanTrace<T extends CleanablePoint>(points: T[], options: CleanTraceOptions): T[] {
  const sorted = [...points].sort((a, b) => a.timestampMs - b.timestampMs);
  const kept: T[] = [];
  for (const point of sorted) {
    if (point.horizontalAccuracyM !== undefined && point.horizontalAccuracyM > options.maxAccuracyM) {
      continue;
    }
    const previous = kept[kept.length - 1];
    if (previous) {
      const elapsedS = (point.timestampMs - previous.timestampMs) / 1000;
      if (elapsedS <= 0) {
        continue;
      }
      if (
        !straddlesPause(previous, point, options.pauses ?? []) &&
        haversineDistanceM(previous, point) / elapsedS > options.maxSpeedMs
      ) {
        continue;
      }
    }
    kept.push(point);
  }
  return kept;
}
