import { describe, expect, it } from "vitest";
import type { LonLat } from "@repo/geo";
import { resampleSegmentPath } from "./match-segment.js";
import { SEGMENT_TRACK_STEP_M, segmentFigures, segmentRuleViolations } from "./segment-geometry.js";

/** Meters per degree of latitude on the haversine sphere (R = 6,371,000 m). */
const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;
const START = { lat: 45.9, lon: 6.12 };

/** A point `northM` meters north and `eastM` meters east of the start. */
function at(northM: number, eastM = 0): LonLat {
  return {
    lat: START.lat + northM / M_PER_DEG_LAT,
    lon: START.lon + eastM / (M_PER_DEG_LAT * Math.cos((START.lat * Math.PI) / 180)),
  };
}

/** A straight line north, `lengthM` long, with altitudes from `altitudeAt(meters from start)`. */
function northTrack(lengthM: number, altitudeAt: (m: number) => number) {
  return resampleSegmentPath([at(0), at(lengthM)], SEGMENT_TRACK_STEP_M).map((point) => ({
    ...point,
    altitudeM: altitudeAt((point.lat - START.lat) * M_PER_DEG_LAT),
  }));
}

describe("segmentRuleViolations (ADR-039 §5)", () => {
  it("accepts 200 m on foot, refuses 199 m", () => {
    for (const sport of ["run", "walk", "hike"]) {
      expect(segmentRuleViolations(sport, [at(0), at(200)])).toEqual([]);
      expect(segmentRuleViolations(sport, [at(0), at(199)])).toEqual(["too_short"]);
    }
  });

  it("asks 500 m by bike", () => {
    expect(segmentRuleViolations("ride", [at(0), at(499)])).toEqual(["too_short"]);
    expect(segmentRuleViolations("ride", [at(0), at(500)])).toEqual([]);
  });

  it("refuses more than 50 km", () => {
    expect(segmentRuleViolations("ride", [at(0), at(50_000)])).toEqual([]);
    expect(segmentRuleViolations("ride", [at(0), at(50_001)])).toEqual(["too_long"]);
  });

  it("refuses a loop: start and finish less than 100 m apart, along a long enough path", () => {
    const loop = [at(0), at(400), at(400, 300), at(0, 99)];
    expect(segmentRuleViolations("run", loop)).toEqual(["loop"]);
    expect(segmentRuleViolations("run", [at(0), at(400), at(400, 300), at(0, 100)])).toEqual([]);
  });

  it("reports every rule that fails", () => {
    expect(segmentRuleViolations("ride", [at(0), at(150), at(0, 50)])).toEqual(["too_short", "loop"]);
  });
});

describe("segmentFigures (ADR-039 §5)", () => {
  it("measures a steady 1 km climb at 8 %: category 4", () => {
    const figures = segmentFigures(1_000, northTrack(1_000, (m) => 500 + m * 0.08));
    expect(figures).toEqual({
      distanceM: 1_000,
      elevationGainM: 80,
      avgGradePct: 8,
      maxGradePct: 8,
      minAltitudeM: 500,
      maxAltitudeM: 580,
      climbCategory: "4",
    });
  });

  it("takes the steepest 100 m for the maximum grade, the ends for the average", () => {
    // Flat for 200 m, then 400 m at 10 %.
    const figures = segmentFigures(600, northTrack(600, (m) => (m <= 200 ? 300 : 300 + (m - 200) * 0.1)));
    expect(figures.avgGradePct).toBe(6.7);
    expect(figures.maxGradePct).toBe(10);
    expect(figures.elevationGainM).toBe(40);
    expect(figures.climbCategory).toBeNull();
  });

  it("gives a negative average to a descent, and no category", () => {
    const figures = segmentFigures(2_000, northTrack(2_000, (m) => 900 - m * 0.05));
    expect(figures.avgGradePct).toBe(-5);
    expect(figures.maxGradePct).toBe(-5);
    expect(figures.elevationGainM).toBe(0);
    expect(figures.minAltitudeM).toBe(800);
    expect(figures.maxAltitudeM).toBe(900);
    expect(figures.climbCategory).toBeNull();
  });
});

describe("resampleSegmentPath every SEGMENT_TRACK_STEP_M", () => {
  it("keeps the drawn ends, one point every 20 m", () => {
    const track = resampleSegmentPath([at(0), at(100)], SEGMENT_TRACK_STEP_M);
    expect(track).toHaveLength(6);
    expect(track[0]).toEqual(at(0));
    expect(track.at(-1)).toEqual(at(100));
  });
});
