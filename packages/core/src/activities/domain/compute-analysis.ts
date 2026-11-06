import type { ActivityAnalysis, ActivitySeries, ActivitySplit, TracePause } from "@repo/contracts";
import { haversineDistanceM } from "@repo/geo";
import type { TracePoint } from "./compute-metrics.js";
import { straddlesPause } from "./pauses.js";
import { computeBestEfforts, type BestEffort, type RecordSet } from "./best-efforts.js";

/**
 * Written into `activity_analysis.version` (ADR-036 §6-7). Raising it makes the reconciliation
 * sweep recompute every Activity's analysis, 100 per sweep.
 */
export const ACTIVITY_ANALYSIS_VERSION = 2;

/** A cleaned trace point, with the heart rate the series need. */
export interface AnalysisPoint extends TracePoint {
  heartRateBpm?: number;
}

export interface ComputeAnalysisOptions {
  /** Pauses of a Recording (ADR-031 §12): their legs count nowhere, as in `computeMetrics`. */
  pauses?: TracePause[];
  /** Below this speed a leg does not count as moving time (same default as `computeMetrics`). */
  movingSpeedThresholdMs?: number;
  /** The Record family of the Activity's sport (ADR-039 §3); none, no Best effort. */
  recordSet?: RecordSet | null;
}

/** The Activity analysis plus the Best efforts of the trace (ADR-039 §3), stored apart. */
export interface ComputedAnalysis extends ActivityAnalysis {
  bestEfforts: BestEffort[];
}

const SPLIT_M = 1000;
/** A shorter rest after the last full split is dropped. */
const MIN_REST_M = 10;
const MAX_SAMPLES = 300;
/** Short Activities get fewer samples, at least this far apart. */
const MIN_SAMPLE_SPACING_M = 10;
const SPEED_WINDOW_M = 100;
/** Float tolerance on cumulated distances. */
const EPSILON_M = 1e-6;

/** The analysis of an Activity without a usable GPS trace (ADR-036 §6). */
export const EMPTY_ACTIVITY_ANALYSIS: ActivityAnalysis = { splits: [], series: null };

/** A leg between two consecutive points, positioned along the counted distance. */
interface Leg {
  from: number;
  to: number;
  fromM: number;
  toM: number;
  timeS: number;
  moving: boolean;
}

/** Values along the trace, one per point, and how far along it each point is. */
interface Profile {
  alongM: number[];
  values: number[];
}

/**
 * The Activity analysis (ADR-036 §6) of a cleaned trace, before the privacy zone: splits of
 * 1,000 m, series of at most 300 samples, and the Best efforts over the Record distances of
 * `recordSet` (ADR-039 §3). Distances and moving times are counted like
 * `computeMetrics` (legs straddling a Pause count nowhere, slow legs are not moving time), so
 * the splits add up to the official values. Carries no coordinates. Pure (ADR-021 §6).
 */
export function computeAnalysis(
  points: AnalysisPoint[],
  { pauses = [], movingSpeedThresholdMs = 0.5, recordSet = null }: ComputeAnalysisOptions = {},
): ComputedAnalysis {
  const empty: ComputedAnalysis = { ...EMPTY_ACTIVITY_ANALYSIS, bestEfforts: [] };
  if (points.length < 2) {
    return empty;
  }

  const alongM = [0];
  const pausedLeg = [false];
  const legs: Leg[] = [];
  for (let i = 1; i < points.length; i++) {
    const prev = points[i - 1]!;
    const curr = points[i]!;
    const paused = straddlesPause(prev, curr, pauses);
    pausedLeg.push(paused);
    if (paused) {
      alongM.push(alongM[i - 1]!);
      continue;
    }
    const lengthM = haversineDistanceM(prev, curr);
    const timeS = Math.max(0, (curr.timestampMs - prev.timestampMs) / 1000);
    alongM.push(alongM[i - 1]! + lengthM);
    legs.push({
      from: i - 1,
      to: i,
      fromM: alongM[i - 1]!,
      toM: alongM[i]!,
      timeS,
      moving: timeS > 0 && lengthM / timeS >= movingSpeedThresholdMs,
    });
  }
  const totalM = alongM[alongM.length - 1]!;
  if (totalM <= 0) {
    return empty;
  }

  const altitude = profile(alongM, points.map((point) => point.elevationM));
  const heartRate = profile(
    alongM,
    points.map((point) => (point.heartRateBpm !== undefined && point.heartRateBpm > 0 ? point.heartRateBpm : undefined)),
  );
  return {
    splits: computeSplits(legs, totalM, altitude, heartRate),
    series: computeSeries(legs, totalM, altitude, heartRate),
    bestEfforts: recordSet
      ? computeBestEfforts(
          points.map((point) => point.timestampMs),
          alongM,
          pausedLeg,
          recordSet,
        )
      : [],
  };
}

function computeSplits(
  legs: Leg[],
  totalM: number,
  altitude: Profile | undefined,
  heartRate: Profile | undefined,
): ActivitySplit[] {
  const splits: ActivitySplit[] = [];
  let startM = 0;
  let movingTimeS = 0;
  let heartBeats = 0;
  let heartRateTimeS = 0;

  const add = (leg: Leg, portion: number) => {
    const timeS = leg.timeS * portion;
    if (leg.moving) movingTimeS += timeS;
    if (heartRate) {
      heartBeats += ((heartRate.values[leg.from]! + heartRate.values[leg.to]!) / 2) * timeS;
      heartRateTimeS += timeS;
    }
  };
  const close = (endM: number) => {
    splits.push({
      distanceM: round(endM - startM, 1),
      movingTimeS: Math.round(movingTimeS),
      elevationDiffM: altitude ? round(valueAt(altitude, endM) - valueAt(altitude, startM), 1) : null,
      avgHeartRate: !heartRate
        ? null
        : Math.round(heartRateTimeS > 0 ? heartBeats / heartRateTimeS : valueAt(heartRate, (startM + endM) / 2)),
    });
    startM = endM;
    movingTimeS = 0;
    heartBeats = 0;
    heartRateTimeS = 0;
  };

  for (const leg of legs) {
    const lengthM = leg.toM - leg.fromM;
    let done = 0;
    // A leg crossing a kilometre is shared between both splits, in proportion to its length.
    while (lengthM > 0 && leg.toM >= startM + SPLIT_M - EPSILON_M) {
      const crossed = Math.min(1, Math.max(done, (startM + SPLIT_M - leg.fromM) / lengthM));
      add(leg, crossed - done);
      close(startM + SPLIT_M);
      done = crossed;
    }
    add(leg, 1 - done);
  }
  if (totalM - startM >= MIN_REST_M - EPSILON_M) {
    close(totalM);
  }
  return splits;
}

function computeSeries(
  legs: Leg[],
  totalM: number,
  altitude: Profile | undefined,
  heartRate: Profile | undefined,
): ActivitySeries {
  const count = Math.min(MAX_SAMPLES, Math.max(2, Math.floor(totalM / MIN_SAMPLE_SPACING_M) + 1));
  const distanceM = Array.from({ length: count }, (_, i) => (totalM * i) / (count - 1));
  return {
    distanceM: distanceM.map((m) => round(m, 1)),
    speedMs: windowSpeeds(legs, totalM, distanceM),
    altitudeM: altitude ? distanceM.map((m) => round(valueAt(altitude, m), 1)) : null,
    heartRateBpm: heartRate ? distanceM.map((m) => Math.round(valueAt(heartRate, m))) : null,
  };
}

/**
 * Speed around each sample over about {@link SPEED_WINDOW_M}: the distance covered while
 * moving divided by the time spent, stops included, so a stop reads 0.
 */
function windowSpeeds(legs: Leg[], totalM: number, samplesM: number[]): number[] {
  let first = 0;
  return samplesM.map((m) => {
    const startM = Math.min(Math.max(0, m - SPEED_WINDOW_M / 2), Math.max(0, totalM - SPEED_WINDOW_M));
    const endM = Math.min(totalM, startM + SPEED_WINDOW_M);
    while (first < legs.length && legs[first]!.toM < startM) first++;
    let movingM = 0;
    let timeS = 0;
    for (let i = first; i < legs.length && legs[i]!.fromM <= endM; i++) {
      const leg = legs[i]!;
      const lengthM = leg.toM - leg.fromM;
      if (lengthM <= 0) {
        timeS += leg.timeS;
        continue;
      }
      const overlapM = Math.min(endM, leg.toM) - Math.max(startM, leg.fromM);
      if (overlapM <= 0) continue;
      timeS += (leg.timeS * overlapM) / lengthM;
      if (leg.moving) movingM += overlapM;
    }
    return timeS > 0 ? round(movingM / timeS, 2) : 0;
  });
}

/** Per-point values with gaps filled from the nearest known one; undefined when none is known. */
function profile(alongM: number[], raw: Array<number | undefined>): Profile | undefined {
  const firstKnown = raw.find((value) => value !== undefined);
  if (firstKnown === undefined) {
    return undefined;
  }
  let last = firstKnown;
  const values = raw.map((value) => (last = value ?? last));
  return { alongM, values };
}

/** The profile's value at `m` along the counted distance, interpolated between points. */
function valueAt({ alongM, values }: Profile, m: number): number {
  let low = 0;
  let high = alongM.length - 1;
  while (low < high) {
    const mid = (low + high) >> 1;
    if (alongM[mid]! < m) low = mid + 1;
    else high = mid;
  }
  if (low === 0) {
    return values[0]!;
  }
  const spanM = alongM[low]! - alongM[low - 1]!;
  if (spanM <= 0) {
    return values[low]!;
  }
  const t = Math.min(1, (m - alongM[low - 1]!) / spanM);
  return values[low - 1]! + (values[low]! - values[low - 1]!) * t;
}

function round(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}
