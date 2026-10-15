import type { TracePause } from "@repo/contracts";
import { elevationGainM, haversineDistanceM, resampleAlongTrack } from "@repo/geo";
import { straddlesPause } from "./pauses.js";

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

/** Elevation gain tuning (ADR-030 §7): resampling step and hysteresis, in meters. */
export interface ElevationGainOptions {
  stepM: number;
  hysteresisM: number;
}

/**
 * Same parameters as Itineraries to start with (ADR-030 §3, §7), to be tuned
 * on real traces.
 */
export const ACTIVITY_ELEVATION_GAIN: ElevationGainOptions = { stepM: 20, hysteresisM: 2 };

export interface ComputeMetricsOptions {
  /** Pauses of a Recording (ADR-031 §12); imported traces have none. */
  pauses?: TracePause[];
  /** Below this speed a leg does not count as moving time. */
  movingSpeedThresholdMs?: number;
  elevationGain?: ElevationGainOptions;
}

/** The stretches of the trace between Pauses: a climb during a Pause is not counted. */
function splitAtPauses(points: TracePoint[], pauses: TracePause[]): TracePoint[][] {
  const stretches: TracePoint[][] = [[points[0]!]];
  for (let i = 1; i < points.length; i++) {
    if (straddlesPause(points[i - 1]!, points[i]!, pauses)) {
      stretches.push([]);
    }
    stretches[stretches.length - 1]!.push(points[i]!);
  }
  return stretches;
}

function stretchElevationGainM(stretch: TracePoint[], options: ElevationGainOptions): number {
  const altitudes = resampleAlongTrack(stretch, options.stepM).flatMap((point) =>
    point.elevationM === undefined ? [] : [point.elevationM],
  );
  return elevationGainM(altitudes, options.hysteresisM);
}

/**
 * Computes an activity's official metrics from its cleaned trace (ADR-019
 * §5 step 4: distance, moving/total time, elevation gain, speeds).
 *
 * Distance and elevation gain use the algorithm shared with Itineraries
 * (`@repo/geo`, ADR-030 §7): the distance is the length of the track, the
 * gain is measured on the track resampled every `stepM` meters with a
 * `hysteresisM` threshold, so altitude drift while stopped is not counted.
 * Legs that straddle a Pause count neither in distance, moving time,
 * speeds nor elevation gain (a train ride during a Pause never counts);
 * total time runs from the first to the last point, Pauses included
 * (ADR-031 §12).
 * Expects a cleaned trace (strictly increasing timestamps, `cleanTrace`).
 * Pure and DB-free (ADR-021 §6) so it is unit-testable on its own.
 */
export function computeMetrics(
  points: TracePoint[],
  {
    pauses = [],
    movingSpeedThresholdMs = 0.5,
    elevationGain = ACTIVITY_ELEVATION_GAIN,
  }: ComputeMetricsOptions = {},
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
  let maxSpeedMs = 0;

  for (let i = 1; i < points.length; i++) {
    const prev = points[i - 1]!;
    const curr = points[i]!;
    if (straddlesPause(prev, curr, pauses)) {
      continue;
    }
    const segmentDistanceM = haversineDistanceM(prev, curr);
    distanceM += segmentDistanceM;
    const segmentTimeS = (curr.timestampMs - prev.timestampMs) / 1000;
    if (segmentTimeS <= 0) {
      continue;
    }

    const segmentSpeedMs = segmentDistanceM / segmentTimeS;
    maxSpeedMs = Math.max(maxSpeedMs, segmentSpeedMs);
    if (segmentSpeedMs >= movingSpeedThresholdMs) {
      movingTimeS += segmentTimeS;
    }
  }

  const first = points[0]!;
  const last = points[points.length - 1]!;
  const elapsedTimeS = (last.timestampMs - first.timestampMs) / 1000;
  const avgSpeedMs = movingTimeS > 0 ? distanceM / movingTimeS : 0;

  return {
    distanceM,
    elapsedTimeS,
    movingTimeS,
    elevationGainM: splitAtPauses(points, pauses).reduce(
      (gainM, stretch) => gainM + stretchElevationGainM(stretch, elevationGain),
      0,
    ),
    avgSpeedMs,
    maxSpeedMs,
  };
}
