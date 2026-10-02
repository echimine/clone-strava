import { describe, expect, it } from "vitest";
import { applyPrivacyZone } from "./apply-privacy-zone.js";
import { cleanTrace, maxPlausibleSpeedMs } from "./clean-trace.js";
import { haversineDistanceM } from "./compute-metrics.js";
import { computeHeartRate } from "./heart-rate.js";
import { simplifyRoute, toLineStringEwkt, toPointEwkt } from "./simplify-route.js";

// ~111 m per 0.001 degree of latitude.
const line = (count: number, stepDeg = 0.001) =>
  Array.from({ length: count }, (_, i) => ({ lat: 48 + i * stepDeg, lon: 2, timestampMs: i * 60_000 }));

describe("cleanTrace", () => {
  it("sorts by time and drops duplicate timestamps", () => {
    const points = [
      { lat: 48.002, lon: 2, timestampMs: 2000 },
      { lat: 48, lon: 2, timestampMs: 0 },
      { lat: 48.0001, lon: 2, timestampMs: 0 },
      { lat: 48.001, lon: 2, timestampMs: 1000 },
    ];
    const cleaned = cleanTrace(points, { maxAccuracyM: 50, maxSpeedMs: 1000 });
    expect(cleaned.map((p) => p.timestampMs)).toEqual([0, 1000, 2000]);
  });

  it("drops inaccurate fixes and impossible speed jumps", () => {
    const points = [
      { lat: 48, lon: 2, timestampMs: 0 },
      { lat: 48.0001, lon: 2, timestampMs: 10_000, horizontalAccuracyM: 200 },
      // 1 km in 10 s = 100 m/s: a GPS jump for a run.
      { lat: 48.009, lon: 2, timestampMs: 20_000 },
      { lat: 48.0002, lon: 2, timestampMs: 30_000 },
    ];
    const cleaned = cleanTrace(points, { maxAccuracyM: 50, maxSpeedMs: maxPlausibleSpeedMs("run") });
    expect(cleaned.map((p) => p.timestampMs)).toEqual([0, 30_000]);
  });

  it("uses a generic limit for unknown sports", () => {
    expect(maxPlausibleSpeedMs("ride")).toBeGreaterThan(maxPlausibleSpeedMs("run"));
    expect(maxPlausibleSpeedMs("kitesurf")).toBe(50);
  });
});

describe("applyPrivacyZone", () => {
  it("removes the points within the radius of the start and of the end", () => {
    const points = line(11); // ~1.1 km straight north
    const kept = applyPrivacyZone(points, { radiusM: 250 });
    expect(haversineDistanceM(points[0]!, kept[0]!)).toBeGreaterThanOrEqual(250);
    expect(haversineDistanceM(points[10]!, kept[kept.length - 1]!)).toBeGreaterThanOrEqual(250);
    expect(kept.length).toBe(11 - 3 - 3);
  });

  it("returns no route when everything lies inside the zones", () => {
    expect(applyPrivacyZone(line(3), { radiusM: 500 })).toEqual([]);
  });

  it("keeps the route untouched with a zero radius", () => {
    expect(applyPrivacyZone(line(4), { radiusM: 0 })).toHaveLength(4);
  });

  it("handles a loop that comes back home", () => {
    const loop = [...line(6), ...line(6).reverse().slice(1)];
    const kept = applyPrivacyZone(loop, { radiusM: 150 });
    expect(kept.length).toBeGreaterThan(0);
    expect(kept.every((p) => haversineDistanceM(loop[0]!, p) >= 150)).toBe(true);
  });
});

describe("simplifyRoute", () => {
  it("collapses collinear points to the two ends", () => {
    expect(simplifyRoute(line(50), 5)).toHaveLength(2);
  });

  it("keeps a corner above the tolerance", () => {
    const corner = [
      { lat: 48, lon: 2 },
      { lat: 48.001, lon: 2 },
      { lat: 48.001, lon: 2.001 },
    ];
    expect(simplifyRoute(corner, 5)).toHaveLength(3);
  });

  it("writes EWKT with longitude first", () => {
    expect(toPointEwkt({ lat: 48.5, lon: 2.25 })).toBe("SRID=4326;POINT(2.25 48.5)");
    expect(toLineStringEwkt([{ lat: 1, lon: 2 }, { lat: 3, lon: 4 }])).toBe(
      "SRID=4326;LINESTRING(2 1,4 3)",
    );
  });
});

describe("computeHeartRate", () => {
  it("averages only the points with a heart rate", () => {
    expect(computeHeartRate([{ heartRateBpm: 100 }, {}, { heartRateBpm: 151 }])).toEqual({
      avgHeartRate: 126,
      maxHeartRate: 151,
    });
    expect(computeHeartRate([{}, {}])).toEqual({});
  });
});
