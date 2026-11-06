import { elevationGainM, haversineDistanceM, trackDistanceM, type LonLat } from "@repo/geo";
import { climbCategory, type ClimbCategory } from "./climb-category.js";

/** ADR-039 §5: shortest Segment on foot (run, walk, hike) and by bike. */
export const SEGMENT_MIN_LENGTH_M: Readonly<Record<string, number>> = { run: 200, walk: 200, hike: 200, ride: 500 };
/** ADR-039 §5: longest Segment, whatever the sport. */
export const SEGMENT_MAX_LENGTH_M = 50_000;
/** ADR-039 §5: start and finish at least this far apart (no loop). */
export const SEGMENT_MIN_ENDS_APART_M = 100;
/** ADR-039 §5: Segments an athlete may create per rolling 24 h. */
export const SEGMENT_CREATIONS_PER_DAY = 10;

/**
 * Step of the stored path (`LineStringZ`), as for an Itinerary's track (ADR-030 §3): the drawn
 * path is resampled with `resampleSegmentPath(path, SEGMENT_TRACK_STEP_M)`, ends kept, and these
 * are the points the `ElevationService` is asked about.
 */
export const SEGMENT_TRACK_STEP_M = 20;
/** Elevation gain hysteresis, as for an Itinerary (ADR-030 §3). */
const HYSTERESIS_M = 2;
/** The maximum grade is the steepest stretch of at least this length (DEM noise aside). */
const MAX_GRADE_WINDOW_M = 100;

/** A rule of ADR-039 §5 the drawn path breaks. */
export type SegmentRuleViolation = "too_short" | "too_long" | "loop";

/** Every rule of ADR-039 §5 the drawn path breaks, in this order: length, then loop. */
export function segmentRuleViolations(sport: string, path: LonLat[]): SegmentRuleViolation[] {
  const violations: SegmentRuleViolation[] = [];
  const lengthM = trackDistanceM(path);
  // A centimetre of slack: a path drawn at exactly the minimum is accepted.
  if (lengthM < (SEGMENT_MIN_LENGTH_M[sport] ?? SEGMENT_MIN_LENGTH_M.ride!) - 0.01) {
    violations.push("too_short");
  }
  if (lengthM > SEGMENT_MAX_LENGTH_M + 0.01) {
    violations.push("too_long");
  }
  if (path.length < 2 || haversineDistanceM(path[0]!, path.at(-1)!) < SEGMENT_MIN_ENDS_APART_M - 0.01) {
    violations.push("loop");
  }
  return violations;
}

/** What the server computes once at creation (ADR-039 §5); grades in percent. */
export interface SegmentFigures {
  distanceM: number;
  elevationGainM: number;
  /** (finish altitude − start altitude) / distance. */
  avgGradePct: number;
  /** The steepest 100 m. */
  maxGradePct: number;
  minAltitudeM: number;
  maxAltitudeM: number;
  climbCategory: ClimbCategory | null;
}

/**
 * Figures of a Segment from the length of its drawn path and its resampled track with the
 * `ElevationService`'s altitudes. Distances and altitudes to the decimeter, grades to the tenth.
 */
export function segmentFigures(distanceM: number, track: Array<LonLat & { altitudeM: number }>): SegmentFigures {
  const altitudes = track.map((point) => point.altitudeM);
  const avgGradePct = distanceM > 0 ? ((altitudes.at(-1)! - altitudes[0]!) / distanceM) * 100 : 0;
  return {
    distanceM: toTenth(distanceM),
    elevationGainM: toTenth(elevationGainM(altitudes, HYSTERESIS_M)),
    avgGradePct: toTenth(avgGradePct),
    maxGradePct: toTenth(maxGradePct(track) ?? avgGradePct),
    minAltitudeM: toTenth(Math.min(...altitudes)),
    maxAltitudeM: toTenth(Math.max(...altitudes)),
    climbCategory: climbCategory(distanceM, avgGradePct),
  };
}

/** Steepest grade over windows of at least 100 m, starting at each point; null when shorter. */
function maxGradePct(track: Array<LonLat & { altitudeM: number }>): number | null {
  const along = [0];
  for (let i = 1; i < track.length; i++) {
    along.push(along[i - 1]! + haversineDistanceM(track[i - 1]!, track[i]!));
  }
  let steepest: number | null = null;
  let j = 0;
  for (let i = 0; i < track.length; i++) {
    j = Math.max(j, i + 1);
    while (j < track.length && along[j]! - along[i]! < MAX_GRADE_WINDOW_M - 0.01) {
      j += 1;
    }
    if (j >= track.length) {
      break;
    }
    const grade = ((track[j]!.altitudeM - track[i]!.altitudeM) / (along[j]! - along[i]!)) * 100;
    steepest = steepest === null ? grade : Math.max(steepest, grade);
  }
  return steepest;
}

function toTenth(value: number): number {
  return Math.round(value * 10) / 10 || 0;
}
