import { describe, expect, it } from "vitest";
import { simplifyTrack } from "./index.js";

// ~111 m per 0.001 degree of latitude.
const line = (count: number, stepDeg = 0.001) =>
  Array.from({ length: count }, (_, i) => ({ lat: 48 + i * stepDeg, lon: 2 }));

describe("simplifyTrack", () => {
  it("collapses collinear points to the two ends", () => {
    expect(simplifyTrack(line(50), 5)).toHaveLength(2);
  });

  it("keeps a corner above the tolerance", () => {
    const corner = [
      { lat: 48, lon: 2 },
      { lat: 48.001, lon: 2 },
      { lat: 48.001, lon: 2.001 },
    ];
    expect(simplifyTrack(corner, 5)).toHaveLength(3);
  });

  it("keeps the extra fields of the points it returns", () => {
    const points = line(3).map((p, i) => ({ ...p, timestampMs: i }));
    expect(simplifyTrack(points, 5)).toEqual([points[0], points[2]]);
  });
});
