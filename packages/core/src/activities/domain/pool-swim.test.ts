import type { TraceLength, TracePool } from "@repo/contracts";
import { describe, expect, it } from "vitest";
import { poolBestEfforts, poolMetrics } from "./pool-swim.js";

const START = Date.UTC(2026, 4, 2, 7);

/** Lengths one after the other from START: a number is an active length of that many seconds, `rest(s)` a rest. */
function lengths(...items: Array<number | { rest: number }>): TraceLength[] {
  let ms = START;
  return items.map((item) => {
    const active = typeof item === "number";
    const elapsedMs = (active ? item : item.rest) * 1000;
    const length = { startMs: ms, elapsedMs, active };
    ms += elapsedMs;
    return length;
  });
}

const METRIC_25: TracePool = { lengthM: 25, unit: "m" };
// 30, 28, 29, 31 s, a minute of rest, then 27, 27, 30, 30 s.
const SESSION = lengths(30, 28, 29, 31, { rest: 60 }, 27, 27, 30, 30);

describe("poolMetrics", () => {
  it("counts the active lengths times the pool length, moving only while swimming", () => {
    expect(poolMetrics(SESSION, METRIC_25)).toEqual({
      distanceM: 200,
      movingTimeS: 232,
      avgSpeedMs: 200 / 232,
      maxSpeedMs: 25 / 27,
    });
  });

  it("converts a pool in yards to meters", () => {
    expect(poolMetrics(lengths(25, 25, 25, 25), { lengthM: 22.86, unit: "yd" }).distanceM).toBeCloseTo(91.44, 6);
  });
});

describe("poolBestEfforts", () => {
  it("times the best run of consecutive active lengths; a rest breaks it", () => {
    // 8 active lengths make 200 m, but never 8 in a row.
    expect(poolBestEfforts(SESSION, METRIC_25)).toEqual([
      { distanceM: 50, elapsedTimeMs: 54_000, startDistanceM: 100 },
      { distanceM: 100, elapsedTimeMs: 114_000, startDistanceM: 100 },
    ]);
  });

  it("keeps only the distances that are a whole number of lengths", () => {
    // FIT stores 33⅓ m as 33.33: 3 lengths make the 100 m and 6 the 200 m, 1.5 lengths are no 50 m.
    const efforts = poolBestEfforts(lengths(40, 40, 40, 40, 40, 40), { lengthM: 33.33, unit: "m" });
    expect(efforts).toEqual([
      { distanceM: 100, elapsedTimeMs: 120_000, startDistanceM: 0 },
      { distanceM: 200, elapsedTimeMs: 240_000, startDistanceM: 0 },
    ]);
  });

  it("has no Best effort in a pool set in yards", () => {
    // 35 lengths of 25 yd are 800.1 m: still no Record.
    const swim = lengths(...Array.from({ length: 40 }, () => 20));
    expect(poolBestEfforts(swim, { lengthM: 22.86, unit: "yd" })).toEqual([]);
  });

  it("starts the window on the earliest of equal times", () => {
    expect(poolBestEfforts(lengths(30, 30, 30), METRIC_25)).toEqual([
      { distanceM: 50, elapsedTimeMs: 60_000, startDistanceM: 0 },
    ]);
  });
});
