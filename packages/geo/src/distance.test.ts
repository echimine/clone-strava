import { describe, expect, it } from "vitest";
import { haversineDistanceM } from "./index.js";

/** One degree of arc on the 6,371 km sphere: 2πR / 360. */
const ONE_DEGREE_M = 111_194.93;

describe("haversineDistanceM", () => {
  it("is zero between a point and itself", () => {
    expect(haversineDistanceM({ lat: 45.5, lon: 6.1 }, { lat: 45.5, lon: 6.1 })).toBe(0);
  });

  it("measures one degree along a meridian", () => {
    expect(haversineDistanceM({ lat: 45, lon: 6 }, { lat: 46, lon: 6 })).toBeCloseTo(ONE_DEGREE_M, 1);
  });

  it("shrinks a degree of longitude away from the equator", () => {
    expect(haversineDistanceM({ lat: 0, lon: 0 }, { lat: 0, lon: 1 })).toBeCloseTo(ONE_DEGREE_M, 1);
    expect(haversineDistanceM({ lat: 60, lon: 0 }, { lat: 60, lon: 1 })).toBeCloseTo(55_597, 0);
  });
});
