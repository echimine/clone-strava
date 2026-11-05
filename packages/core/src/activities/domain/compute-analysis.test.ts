import { readFileSync } from "node:fs";
import { join } from "node:path";
import { traceSchema } from "@repo/contracts";
import { describe, expect, it } from "vitest";
import { cleanTrace, MAX_TRACE_ACCURACY_M, maxPlausibleSpeedMs } from "./clean-trace.js";
import { computeAnalysis, type AnalysisPoint } from "./compute-analysis.js";

/** Shared timestamped traces (ADR-031 §5): their values come from their construction. */
const TRACES_DIR = join(__dirname, "..", "..", "..", "..", "contracts", "fixtures", "traces");

function analysisOf(file: string) {
  const shared = JSON.parse(readFileSync(join(TRACES_DIR, file), "utf8")) as {
    sportTypeCode: string;
    trace: unknown;
  };
  const trace = traceSchema.parse(shared.trace);
  const points = cleanTrace(trace.points, {
    maxAccuracyM: MAX_TRACE_ACCURACY_M,
    maxSpeedMs: maxPlausibleSpeedMs(shared.sportTypeCode),
    pauses: trace.pauses,
  });
  return computeAnalysis(points, { pauses: trace.pauses });
}

const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;
const START = Date.UTC(2026, 10, 3, 8);

/** A straight line north, one point every `stepM` meters at `speedMs`, from `fromM`. */
function northLine(
  fromM: number,
  toM: number,
  { stepM = 10, speedMs = 2.5, startMs = START, extra = (_m: number) => ({}) } = {},
): AnalysisPoint[] {
  const points: AnalysisPoint[] = [];
  for (let m = fromM; m <= toM + 1e-9; m += stepM) {
    points.push({
      lat: 45 + m / M_PER_DEG_LAT,
      lon: 5,
      timestampMs: startMs + ((m - fromM) / speedMs) * 1000,
      ...extra(m),
    });
  }
  return points;
}

describe("computeAnalysis", () => {
  it("splits a 1,800 m run into one kilometre and an 800 m rest", () => {
    const { splits } = analysisOf("run-no-pause.json");

    expect(splits).toHaveLength(2);
    expect(splits[0]!.distanceM).toBeCloseTo(1000, 1);
    expect(splits[0]!.movingTimeS).toBe(333);
    expect(splits[1]!.distanceM).toBeCloseTo(800, 1);
    expect(splits[1]!.movingTimeS).toBe(267);
  });

  it("counts 52 full kilometres on a 52 km ride, with no rest split", () => {
    const { splits } = analysisOf("ride-long-loop.json");

    expect(splits).toHaveLength(52);
    for (const split of splits) {
      expect(split.distanceM).toBeCloseTo(1000, 1);
      expect(split.movingTimeS).toBe(100);
    }
  });

  it("ignores the train ride during a Pause, like the official distance", () => {
    const { splits, series } = analysisOf("run-train-during-pause.json");

    // 1,950 m on foot: the 60 km by train count nowhere.
    expect(splits.map((split) => Math.round(split.distanceM))).toEqual([1000, 950]);
    expect(splits[0]!.movingTimeS + splits[1]!.movingTimeS).toBe(650);
    expect(series!.distanceM.at(-1)).toBeCloseTo(1950, 0);
  });

  it("keeps a rest of at least 10 m and drops a shorter one", () => {
    expect(computeAnalysis(northLine(0, 1010)).splits.map((s) => Math.round(s.distanceM))).toEqual([1000, 10]);
    expect(computeAnalysis(northLine(0, 1005, { stepM: 5 })).splits.map((s) => Math.round(s.distanceM))).toEqual([
      1000,
    ]);
  });

  it("leaves altitude and heart rate out when the trace has none", () => {
    const { splits, series } = analysisOf("walk-imprecise-points.json");

    expect(splits).toEqual([{ distanceM: expect.closeTo(600, 1), movingTimeS: 400, elevationDiffM: null, avgHeartRate: null }]);
    expect(series!.altitudeM).toBeNull();
    expect(series!.heartRateBpm).toBeNull();
  });

  it("samples at most 300 points evenly along the distance, at a steady speed", () => {
    const ride = analysisOf("ride-long-loop.json").series!;
    expect(ride.distanceM).toHaveLength(300);
    expect(ride.speedMs).toHaveLength(300);
    expect(ride.distanceM[0]).toBe(0);
    expect(ride.distanceM.at(-1)).toBeCloseTo(52_000, 0);
    expect(ride.distanceM[150]! - ride.distanceM[149]!).toBeCloseTo(52_000 / 299, 0);
    for (const speed of ride.speedMs) expect(speed).toBeCloseTo(10, 1);

    const run = analysisOf("run-no-pause.json").series!;
    expect(run.distanceM.length).toBeLessThanOrEqual(300);
    for (const speed of run.speedMs) expect(speed).toBeCloseTo(3, 1);
  });

  it("gives each split its altitude difference and average heart rate", () => {
    // 2 km climbing 5 m per 100 m; heart rate 120 bpm on the first km, 160 on the second.
    const points = northLine(0, 2000, {
      extra: (m) => ({ elevationM: 100 + m / 20, heartRateBpm: m < 1000 ? 120 : 160 }),
    });
    const { splits, series } = computeAnalysis(points);

    expect(splits.map((split) => split.elevationDiffM)).toEqual([50, 50]);
    expect(splits[0]!.avgHeartRate).toBeGreaterThanOrEqual(120);
    expect(splits[0]!.avgHeartRate).toBeLessThanOrEqual(122);
    expect(splits[1]!.avgHeartRate).toBe(160);
    expect(series!.altitudeM![0]).toBe(100);
    expect(series!.altitudeM!.at(-1)).toBe(200);
    expect(series!.heartRateBpm![0]).toBe(120);
    expect(series!.heartRateBpm!.at(-1)).toBe(160);
  });

  it("shows a speed of 0 while stopped", () => {
    // 1 km at 2.5 m/s, then 200 m shuffled at 0.2 m/s (not moving), then 1 km at 2.5 m/s.
    const first = northLine(0, 1000);
    const lastFirstMs = first.at(-1)!.timestampMs;
    const stopped = northLine(1000, 1200, { speedMs: 0.2, startMs: lastFirstMs }).slice(1);
    const second = northLine(1200, 2200, { startMs: stopped.at(-1)!.timestampMs }).slice(1);
    const { splits, series } = computeAnalysis([...first, ...stopped, ...second]);

    const middle = series!.distanceM.findIndex((m) => m >= 1100);
    expect(series!.speedMs[middle]).toBe(0);
    expect(series!.speedMs[5]).toBeCloseTo(2.5, 1);
    // The stopped 200 m count in the distance but not in the moving time.
    expect(splits[1]!.movingTimeS).toBe(Math.round(800 / 2.5));
  });

  it("has no split and no series with fewer than two points", () => {
    expect(computeAnalysis(northLine(0, 0))).toEqual({ splits: [], series: null, bestEfforts: [] });
    expect(computeAnalysis([])).toEqual({ splits: [], series: null, bestEfforts: [] });
  });
});
