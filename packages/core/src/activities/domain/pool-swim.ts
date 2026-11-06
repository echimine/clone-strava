import type { TraceLength, TracePool } from "@repo/contracts";
import { RECORD_DISTANCES_M, type BestEffort } from "./best-efforts.js";

/** The official figures of a pool swim (ADR-039 §4), from its lengths alone. */
export interface PoolMetrics {
  /** Active lengths × pool length. */
  distanceM: number;
  /** Time spent on active lengths. */
  movingTimeS: number;
  avgSpeedMs: number;
  /** The fastest active length. */
  maxSpeedMs: number;
}

/**
 * How far a whole number of lengths may miss a Record distance: FIT stores the pool length to the
 * centimeter, so 3 lengths of a 33⅓ m pool read 99.99 m.
 */
const MULTIPLE_TOLERANCE = 0.001;

/** The distance and times of a pool swim (ADR-039 §4): a rest length adds neither. Pure. */
export function poolMetrics(lengths: readonly TraceLength[], pool: TracePool): PoolMetrics {
  const active = lengths.filter((length) => length.active);
  const distanceM = active.length * pool.lengthM;
  const movingTimeS = active.reduce((sum, length) => sum + length.elapsedMs, 0) / 1000;
  const fastestMs = Math.min(...active.filter((length) => length.elapsedMs > 0).map((length) => length.elapsedMs));
  return {
    distanceM,
    movingTimeS,
    avgSpeedMs: movingTimeS > 0 ? distanceM / movingTimeS : 0,
    maxSpeedMs: Number.isFinite(fastestMs) ? pool.lengthM / (fastestMs / 1000) : 0,
  };
}

/**
 * The Best efforts of a pool swim over the `swim_pool` distances (ADR-039 §3): for a distance of
 * N lengths, the best sum of N consecutive active lengths; a rest length breaks the sequence. Only
 * the distances that are a whole number of lengths count, and a pool set in yards has none. On
 * equal times the earliest window wins. Pure.
 */
export function poolBestEfforts(lengths: readonly TraceLength[], pool: TracePool): BestEffort[] {
  if (pool.unit !== "m") {
    return [];
  }
  // Runs of consecutive active lengths, each with the number of active lengths before it.
  const runs: Array<{ before: number; timesMs: number[] }> = [];
  let before = 0;
  let current: number[] | undefined;
  for (const length of lengths) {
    if (!length.active) {
      current = undefined;
      continue;
    }
    if (!current) {
      current = [];
      runs.push({ before, timesMs: current });
    }
    current.push(length.elapsedMs);
    before++;
  }

  const efforts: BestEffort[] = [];
  for (const distanceM of RECORD_DISTANCES_M.swim_pool) {
    const count = Math.round(distanceM / pool.lengthM);
    if (count < 1 || Math.abs(count * pool.lengthM - distanceM) > distanceM * MULTIPLE_TOLERANCE) {
      continue;
    }
    let best: { timeMs: number; startLength: number } | undefined;
    for (const run of runs) {
      let windowMs = 0;
      for (let i = 0; i < run.timesMs.length; i++) {
        windowMs += run.timesMs[i]!;
        if (i >= count) windowMs -= run.timesMs[i - count]!;
        if (i + 1 < count) continue;
        if (!best || windowMs < best.timeMs) {
          best = { timeMs: windowMs, startLength: run.before + i + 1 - count };
        }
      }
    }
    if (best) {
      efforts.push({
        distanceM,
        elapsedTimeMs: best.timeMs,
        startDistanceM: Math.round(best.startLength * pool.lengthM * 10) / 10,
      });
    }
  }
  return efforts;
}
