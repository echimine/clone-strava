import { describe, expect, it } from "vitest";
import { computeMetrics, type TracePoint } from "./compute-metrics.js";

describe("computeMetrics", () => {
  it("returns all-zero metrics for fewer than two points", () => {
    expect(computeMetrics([])).toEqual({
      distanceM: 0,
      elapsedTimeS: 0,
      movingTimeS: 0,
      elevationGainM: 0,
      avgSpeedMs: 0,
      maxSpeedMs: 0,
    });
  });

  it("computes distance, elapsed time and average speed for a simple trace", () => {
    // ~0.1 degree of latitude at the equator is close to 11.1 km.
    const points: TracePoint[] = [
      { lat: 0, lon: 0, timestampMs: 0 },
      { lat: 0.1, lon: 0, timestampMs: 1000 * 1000 },
    ];

    const metrics = computeMetrics(points, 0);

    expect(metrics.distanceM).toBeGreaterThan(11_000);
    expect(metrics.distanceM).toBeLessThan(11_200);
    expect(metrics.elapsedTimeS).toBe(1000);
    expect(metrics.movingTimeS).toBe(1000);
    expect(metrics.avgSpeedMs).toBeCloseTo(metrics.distanceM / 1000, 5);
  });

  it("excludes segments below the moving speed threshold from moving time", () => {
    const points: TracePoint[] = [
      { lat: 0, lon: 0, timestampMs: 0 },
      // Same point, 60s later: zero speed, should not count as moving.
      { lat: 0, lon: 0, timestampMs: 60_000 },
      { lat: 0.01, lon: 0, timestampMs: 70_000 },
    ];

    const metrics = computeMetrics(points, 0.5);

    expect(metrics.elapsedTimeS).toBe(70);
    expect(metrics.movingTimeS).toBe(10);
  });

  it("sums only positive elevation deltas into elevationGainM", () => {
    const points: TracePoint[] = [
      { lat: 0, lon: 0, elevationM: 100, timestampMs: 0 },
      { lat: 0.001, lon: 0, elevationM: 120, timestampMs: 10_000 },
      { lat: 0.002, lon: 0, elevationM: 90, timestampMs: 20_000 },
      { lat: 0.003, lon: 0, elevationM: 110, timestampMs: 30_000 },
    ];

    const metrics = computeMetrics(points, 0);

    expect(metrics.elevationGainM).toBe(20 + 20);
  });
});
