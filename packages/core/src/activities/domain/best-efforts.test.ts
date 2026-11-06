import type { TracePause } from "@repo/contracts";
import { describe, expect, it } from "vitest";
import { computeAnalysis, type AnalysisPoint } from "./compute-analysis.js";
import { RECORD_DISTANCES_M, recordSetOf } from "./best-efforts.js";

const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;
const START = Date.UTC(2026, 10, 5, 8);

/**
 * A straight line north through `legs`: each leg covers `lengthM` at `speedMs`, with points
 * every `stepM` (the leg's whole length by default). `stopS` waits in place before the leg.
 */
function line(
  legs: Array<{ lengthM: number; speedMs: number; stepM?: number; stopS?: number }>,
): AnalysisPoint[] {
  let m = 0;
  let ms = START;
  const points: AnalysisPoint[] = [{ lat: 45, lon: 5, timestampMs: ms }];
  for (const { lengthM, speedMs, stepM = lengthM, stopS } of legs) {
    if (stopS) {
      ms += stopS * 1000;
      points.push({ lat: 45 + m / M_PER_DEG_LAT, lon: 5, timestampMs: ms });
    }
    for (let done = stepM; done <= lengthM + 1e-9; done += stepM) {
      m += stepM;
      ms += (stepM / speedMs) * 1000;
      points.push({ lat: 45 + m / M_PER_DEG_LAT, lon: 5, timestampMs: ms });
    }
  }
  return points;
}

function bestEffortsOf(points: AnalysisPoint[], sportTypeCode = "run", pauses: TracePause[] = []) {
  const { bestEfforts } = computeAnalysis(points, { pauses, recordSet: recordSetOf(sportTypeCode) });
  return new Map(bestEfforts.map((effort) => [effort.distanceM, effort]));
}

describe("Record distances", () => {
  it("are those of ADR-039 §3 for each record set", () => {
    expect(RECORD_DISTANCES_M.run).toEqual([
      400, 1000, 2000, 3000, 5000, 10000, 15000, 20000, 21097.5, 30000, 42195, 50000, 100000,
    ]);
    expect(RECORD_DISTANCES_M.ride).toEqual([
      5000, 10000, 20000, 30000, 40000, 50000, 80000, 100000, 150000, 160000, 200000,
    ]);
    expect(RECORD_DISTANCES_M.walk).toEqual([1000, 2000, 3000, 5000, 10000, 20000, 21097.5, 30000, 42195]);
    expect(RECORD_DISTANCES_M.hike).toEqual([5000, 10000, 15000, 20000, 30000, 40000, 50000]);
    expect(RECORD_DISTANCES_M.swim_open_water).toEqual([400, 750, 1000, 1500, 1900, 3800, 5000, 10000]);
    expect(RECORD_DISTANCES_M.swim_pool).toEqual([50, 100, 200, 400, 800, 1000, 1500]);
  });

  it("maps a sport with a trace to its record set, a swim to open water", () => {
    expect(recordSetOf("run")).toBe("run");
    expect(recordSetOf("ride")).toBe("ride");
    expect(recordSetOf("walk")).toBe("walk");
    expect(recordSetOf("hike")).toBe("hike");
    expect(recordSetOf("swim")).toBe("swim_open_water");
    expect(recordSetOf("yoga")).toBeNull();
  });
});

describe("computeAnalysis Best efforts", () => {
  it("times every Record distance covered by a steady 5.2 km run, and none beyond", () => {
    const efforts = bestEffortsOf(line([{ lengthM: 5200, speedMs: 2.5, stepM: 10 }]));

    expect([...efforts.keys()]).toEqual([400, 1000, 2000, 3000, 5000]);
    expect(efforts.get(400)!.elapsedTimeMs).toBe(160_000);
    expect(efforts.get(5000)!.elapsedTimeMs).toBe(2_000_000);
  });

  it("has no Best effort without a record set", () => {
    const points = line([{ lengthM: 5200, speedMs: 2.5, stepM: 10 }]);
    expect(computeAnalysis(points).bestEfforts).toEqual([]);
  });

  it("interpolates the end of a window that starts on a point", () => {
    // 300 m at 2 m/s, a fast 150 m leg at 6 m/s, then 300 m at 3 m/s, one point every 25 s:
    // the best 400 m is the fast leg plus 250 m of the next ones, 25 s + 83.333 s.
    const efforts = bestEffortsOf(
      line([
        { lengthM: 300, speedMs: 2, stepM: 50 },
        { lengthM: 150, speedMs: 6 },
        { lengthM: 300, speedMs: 3, stepM: 75 },
      ]),
    );

    expect(efforts.get(400)).toEqual({ distanceM: 400, elapsedTimeMs: 108_333, startDistanceM: 300 });
  });

  it("interpolates the start of a window that ends on a point", () => {
    // Mirrored: the best 400 m is the last 250 m at 3 m/s, then the fast leg.
    const efforts = bestEffortsOf(
      line([
        { lengthM: 300, speedMs: 3, stepM: 75 },
        { lengthM: 150, speedMs: 6 },
        { lengthM: 300, speedMs: 2, stepM: 50 },
      ]),
    );

    expect(efforts.get(400)).toEqual({ distanceM: 400, elapsedTimeMs: 108_333, startDistanceM: 50 });
  });

  it("counts the time of a Pause inside the window, a Pause not being a gap", () => {
    // 1 km in 400 s, a 5-minute Pause in place, 1 km in 400 s.
    const points = line([
      { lengthM: 1000, speedMs: 2.5, stepM: 10 },
      { lengthM: 1000, speedMs: 2.5, stepM: 10, stopS: 300 },
    ]);
    const pauseStart = START + 400_000;
    const pauses = [{ startMs: pauseStart + 1000, endMs: pauseStart + 299_000 }];

    const efforts = bestEffortsOf(points, "run", pauses);

    expect(efforts.get(1000)!.elapsedTimeMs).toBe(400_000);
    expect(efforts.get(2000)!.elapsedTimeMs).toBe(1_100_000);
  });

  it("discards a window holding a gap of more than 30 s outside a Pause", () => {
    // The same 5-minute stop, without a Pause: GPS lost, no 2 km window is eligible.
    const efforts = bestEffortsOf(
      line([
        { lengthM: 1000, speedMs: 2.5, stepM: 10 },
        { lengthM: 1000, speedMs: 2.5, stepM: 10, stopS: 300 },
      ]),
    );

    expect(efforts.get(1000)!.elapsedTimeMs).toBe(400_000);
    expect(efforts.has(2000)).toBe(false);
  });

  it("allows gaps of up to 60 s in open water", () => {
    // One point every 45 s at 1 m/s.
    const points = line([{ lengthM: 1080, speedMs: 1, stepM: 45 }]);

    expect([...bestEffortsOf(points, "swim").keys()]).toEqual([400, 750, 1000]);
    expect(bestEffortsOf(points, "swim").get(1000)!.elapsedTimeMs).toBe(1_000_000);
    expect(bestEffortsOf(points, "run").size).toBe(0);
  });

  it("times a run of exactly 1 km over its whole length", () => {
    const efforts = bestEffortsOf(line([{ lengthM: 1000, speedMs: 4, stepM: 10 }]));

    expect(efforts.get(1000)).toEqual({ distanceM: 1000, elapsedTimeMs: 250_000, startDistanceM: 0 });
  });
});
