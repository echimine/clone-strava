/** Families of Records (ADR-039 §3): two swims are never compared. Stored as `best_effort.record_set`. */
export const RECORD_SETS = ["run", "ride", "walk", "hike", "swim_pool", "swim_open_water"] as const;
export type RecordSet = (typeof RECORD_SETS)[number];

const HALF_MARATHON_M = 21097.5;
const MARATHON_M = 42195;

/** The Record distances of each family, in meters, shortest first (ADR-039 §3). */
export const RECORD_DISTANCES_M: Readonly<Record<RecordSet, readonly number[]>> = {
  run: [400, 1000, 2000, 3000, 5000, 10000, 15000, 20000, HALF_MARATHON_M, 30000, MARATHON_M, 50000, 100000],
  // 160 km is the 100 miles.
  ride: [5000, 10000, 20000, 30000, 40000, 50000, 80000, 100000, 150000, 160000, 200000],
  walk: [1000, 2000, 3000, 5000, 10000, 20000, HALF_MARATHON_M, 30000, MARATHON_M],
  hike: [5000, 10000, 15000, 20000, 30000, 40000, 50000],
  // Computed from the pool lengths of a FIT file, never from a trace.
  swim_pool: [50, 100, 200, 400, 800, 1000, 1500],
  swim_open_water: [400, 750, 1000, 1500, 1900, 3800, 5000, 10000],
};

/** The Record family of an Activity of this sport with a GPS trace; a swim with a trace is open water. */
export function recordSetOf(sportTypeCode: string): RecordSet | null {
  switch (sportTypeCode) {
    case "run":
    case "ride":
    case "walk":
    case "hike":
      return sportTypeCode;
    case "swim":
      return "swim_open_water";
    default:
      return null;
  }
}

/** A window longer than this between two points, outside a Pause, is a GPS gap (ADR-039 §3). */
function maxGapMs(recordSet: RecordSet): number {
  return recordSet === "swim_open_water" ? 60_000 : 30_000;
}

/** The fastest window of an Activity over one Record distance. */
export interface BestEffort {
  distanceM: number;
  /** Elapsed time, Pauses included, to the millisecond. */
  elapsedTimeMs: number;
  /** Where the window starts along the counted distance, in meters. */
  startDistanceM: number;
}

/** Float tolerance on cumulated distances. */
const EPSILON_M = 1e-6;

/**
 * The Best effort over each Record distance of `recordSet` that the trace covers (ADR-039 §3):
 * a two-pointer window on the counted distance `alongM`, interpolated at both ends, on elapsed
 * time. Between two points the passing time is affine in the distance, so the minimum falls on
 * a window ending on a point or starting on one: both families are scanned, each in O(n). A
 * window holding a leg longer than the family's gap, outside a Pause, is discarded.
 *
 * `alongM[i]` is the counted distance at point `i` (a leg straddling a Pause adds none) and
 * `pausedLeg[i]` tells whether the leg from `i - 1` to `i` straddles a Pause.
 */
export function computeBestEfforts(
  timestampsMs: readonly number[],
  alongM: readonly number[],
  pausedLeg: readonly boolean[],
  recordSet: RecordSet,
): BestEffort[] {
  const n = alongM.length;
  if (n < 2) {
    return [];
  }
  const totalM = alongM[n - 1]!;
  const gapMs = maxGapMs(recordSet);
  // gaps[i]: GPS gaps among the legs 1..i, so a window over the legs i+1..j holds
  // gaps[j] - gaps[i] of them.
  const gaps = [0];
  for (let i = 1; i < n; i++) {
    const gap = !pausedLeg[i] && timestampsMs[i]! - timestampsMs[i - 1]! > gapMs;
    gaps.push(gaps[i - 1]! + (gap ? 1 : 0));
  }
  const clean = (first: number, last: number) => gaps[last]! - gaps[first]! === 0;

  /** The time of point `low` or `low + 1` passing `m`, interpolated within their leg. */
  const timeAt = (low: number, m: number) => {
    const spanM = alongM[low + 1]! - alongM[low]!;
    const ratio = spanM > 0 ? Math.min(1, Math.max(0, (m - alongM[low]!) / spanM)) : 1;
    return timestampsMs[low]! + (timestampsMs[low + 1]! - timestampsMs[low]!) * ratio;
  };

  const efforts: BestEffort[] = [];
  for (const distanceM of RECORD_DISTANCES_M[recordSet]) {
    if (distanceM > totalM + EPSILON_M) {
      break;
    }
    let best: { timeMs: number; startM: number } | undefined;
    const consider = (timeMs: number, startM: number) => {
      if (!best || timeMs < best.timeMs) {
        best = { timeMs, startM };
      }
    };

    // Ending on point j: start at alongM[j] - D, after the last point that is not beyond it
    // (the latest time the athlete is there).
    let i = 0;
    for (let j = 1; j < n; j++) {
      const startM = alongM[j]! - distanceM;
      if (startM < -EPSILON_M) continue;
      while (i + 1 < j && alongM[i + 1]! <= startM + EPSILON_M) i++;
      if (!clean(i, j)) continue;
      const startMs = alongM[i]! >= startM - EPSILON_M ? timestampsMs[i]! : timeAt(i, startM);
      consider(timestampsMs[j]! - startMs, Math.max(0, startM));
    }

    // Starting on point i: end at alongM[i] + D, on the first point that reaches it (the
    // earliest time the athlete is there).
    let j = 1;
    for (let start = 0; start < n - 1; start++) {
      const endM = Math.min(totalM, alongM[start]! + distanceM);
      if (alongM[start]! + distanceM > totalM + EPSILON_M) break;
      if (j <= start) j = start + 1;
      while (j < n - 1 && alongM[j]! < endM - EPSILON_M) j++;
      if (!clean(start, j)) continue;
      const endMs = alongM[j]! <= endM + EPSILON_M ? timestampsMs[j]! : timeAt(j - 1, endM);
      consider(endMs - timestampsMs[start]!, alongM[start]!);
    }

    if (best) {
      efforts.push({
        distanceM,
        elapsedTimeMs: Math.round(best.timeMs),
        startDistanceM: Math.round(best.startM * 10) / 10,
      });
    }
  }
  return efforts;
}
