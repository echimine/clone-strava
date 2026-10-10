import { haversineDistanceM } from "@repo/geo";

/** One cleaned trace point (ADR-019 §5 step 3: cleanup happens upstream). */
export interface TracePoint {
  lat: number;
  lon: number;
  elevationM?: number;
  timestampMs: number;
}

export interface ComputedMetrics {
  distanceM: number;
  elapsedTimeS: number;
  movingTimeS: number;
  elevationGainM: number;
  avgSpeedMs: number;
  maxSpeedMs: number;
}

/**
 * Computes an activity's official metrics from its cleaned trace (ADR-019
 * §5 step 4: distance, moving/total time, elevation gain, speeds).
 *
 * Deliberately simple for the MVP skeleton (ADR-019 "Consequences":
 * "algorithms ... will be approximate"): no smoothing beyond the moving
 * speed threshold, no outlier rejection (that happens upstream, §5 step
 * 3). Pure and DB-free (ADR-021 §6) so it is unit-testable on its own.
 */
export function computeMetrics(
  points: TracePoint[],
  movingSpeedThresholdMs = 0.5,
): ComputedMetrics {
  if (points.length < 2) {
    return {
      distanceM: 0,
      elapsedTimeS: 0,
      movingTimeS: 0,
      elevationGainM: 0,
      avgSpeedMs: 0,
      maxSpeedMs: 0,
    };
  }

  let distanceM = 0;
  let movingTimeS = 0;
  let elevationGainM = 0;
  let maxSpeedMs = 0;

  for (let i = 1; i < points.length; i++) {
    const prev = points[i - 1]!;
    const curr = points[i]!;
    const segmentDistanceM = haversineDistanceM(prev, curr);
    const segmentTimeS = (curr.timestampMs - prev.timestampMs) / 1000;
    if (segmentTimeS <= 0) {
      continue;
    }

    const segmentSpeedMs = segmentDistanceM / segmentTimeS;
    distanceM += segmentDistanceM;
    maxSpeedMs = Math.max(maxSpeedMs, segmentSpeedMs);
    if (segmentSpeedMs >= movingSpeedThresholdMs) {
      movingTimeS += segmentTimeS;
    }

    if (prev.elevationM !== undefined && curr.elevationM !== undefined) {
      const delta = curr.elevationM - prev.elevationM;
      if (delta > 0) {
        elevationGainM += delta;
      }
    }
  }

  const first = points[0]!;
  const last = points[points.length - 1]!;
  const elapsedTimeS = (last.timestampMs - first.timestampMs) / 1000;
  const avgSpeedMs = movingTimeS > 0 ? distanceM / movingTimeS : 0;

  return { distanceM, elapsedTimeS, movingTimeS, elevationGainM, avgSpeedMs, maxSpeedMs };
}
