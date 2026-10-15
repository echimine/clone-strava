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

    const metrics = computeMetrics(points, { movingSpeedThresholdMs: 0 });

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

    const metrics = computeMetrics(points, { movingSpeedThresholdMs: 0.5 });

    expect(metrics.elapsedTimeS).toBe(70);
    expect(metrics.movingTimeS).toBe(10);
  });

  it("counts climbs on the track resampled by distance into elevationGainM", () => {
    const points: TracePoint[] = [
      { lat: 0, lon: 0, elevationM: 100, timestampMs: 0 },
      { lat: 0.001, lon: 0, elevationM: 120, timestampMs: 10_000 },
      { lat: 0.002, lon: 0, elevationM: 90, timestampMs: 20_000 },
      { lat: 0.003, lon: 0, elevationM: 110, timestampMs: 30_000 },
    ];

    const metrics = computeMetrics(points, { movingSpeedThresholdMs: 0 });

    // Legs of ~111.195 m sampled every 20 m: the 120 m summit falls between
    // samples (highest at 100 m along: ~117.99), the lowest sample of the
    // descent is ~90.65 (220 m along), and the last point (110) is kept.
    // (117.99 - 100) + (110 - 90.65) ≈ 37.34.
    expect(metrics.elevationGainM).toBeCloseTo(37.34, 2);
  });

  it("does not count altitude drift while stopped as elevation gain", () => {
    // Barometer drift at a standstill, then a flat move: no distance covered
    // while the altitude wobbles, so the resampled track has no climb.
    const points: TracePoint[] = [
      { lat: 0, lon: 0, elevationM: 100, timestampMs: 0 },
      { lat: 0, lon: 0, elevationM: 103, timestampMs: 10_000 },
      { lat: 0, lon: 0, elevationM: 100, timestampMs: 20_000 },
      { lat: 0, lon: 0, elevationM: 103, timestampMs: 30_000 },
      { lat: 0, lon: 0, elevationM: 100, timestampMs: 40_000 },
      { lat: 0.001, lon: 0, elevationM: 100, timestampMs: 60_000 },
    ];

    const metrics = computeMetrics(points, { movingSpeedThresholdMs: 0 });

    expect(metrics.elevationGainM).toBe(0);
  });

  it("ignores altitude noise smaller than the 2 m hysteresis", () => {
    // Legs of ~111 m, altitude wobbling by 1.5 m: GPS noise, not a climb.
    const points: TracePoint[] = [
      { lat: 0, lon: 0, elevationM: 100, timestampMs: 0 },
      { lat: 0.001, lon: 0, elevationM: 101.5, timestampMs: 30_000 },
      { lat: 0.002, lon: 0, elevationM: 100, timestampMs: 60_000 },
      { lat: 0.003, lon: 0, elevationM: 101.5, timestampMs: 90_000 },
    ];

    const metrics = computeMetrics(points, { movingSpeedThresholdMs: 0 });

    expect(metrics.elevationGainM).toBe(0);
  });

  it("skips a move during a Pause for distance and moving time, not for total time", () => {
    // Two legs of 0.001 degree of latitude (~111.195 m each, 30 s each), and
    // a train ride of ~55 km during the Pause between them.
    const points: TracePoint[] = [
      { lat: 48, lon: 2, timestampMs: 0 },
      { lat: 48.001, lon: 2, timestampMs: 30_000 },
      { lat: 48.5, lon: 2, timestampMs: 3_610_000 },
      { lat: 48.501, lon: 2, timestampMs: 3_640_000 },
    ];

    const metrics = computeMetrics(points, { pauses: [{ startMs: 40_000, endMs: 3_600_000 }] });

    expect(metrics.distanceM).toBeCloseTo(222.39, 1);
    expect(metrics.movingTimeS).toBe(60);
    expect(metrics.elapsedTimeS).toBe(3640);
    expect(metrics.avgSpeedMs).toBeCloseTo(222.39 / 60, 2);
    expect(metrics.maxSpeedMs).toBeCloseTo(111.195 / 30, 2);
  });

  it("does not count a climb made during a Pause as elevation gain", () => {
    // Flat before and after; the train climbs 500 m during the Pause.
    const points: TracePoint[] = [
      { lat: 45, lon: 6, elevationM: 100, timestampMs: 0 },
      { lat: 45.001, lon: 6, elevationM: 100, timestampMs: 30_000 },
      { lat: 45.2, lon: 6, elevationM: 600, timestampMs: 2_000_000 },
      { lat: 45.201, lon: 6, elevationM: 600, timestampMs: 2_030_000 },
    ];

    const metrics = computeMetrics(points, { pauses: [{ startMs: 40_000, endMs: 1_990_000 }] });

    expect(metrics.elevationGainM).toBe(0);
  });
});
