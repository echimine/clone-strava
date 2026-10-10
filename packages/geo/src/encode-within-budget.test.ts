import { describe, expect, it } from "vitest";
import { decodePolyline, encodeWithinBudget } from "./index.js";

/** A zigzag of `count` points ~110 m apart, every turn sharper than any small tolerance. */
function zigzag(count: number) {
  return Array.from({ length: count }, (_, i) => ({ lat: 45 + i * 0.001, lon: 6 + (i % 2) * 0.001 }));
}

describe("encodeWithinBudget", () => {
  it("keeps every point when the first tolerance already fits", () => {
    const track = zigzag(10);
    expect(decodePolyline(encodeWithinBudget(track, { maxChars: 2000, firstToleranceM: 5 }), 5)).toEqual(track);
  });

  it("doubles the tolerance until the polyline5 fits the budget", () => {
    // A winding ~110 km trace: thousands of points survive 5 m, a few dozen survive larger tolerances.
    const winding = Array.from({ length: 20_000 }, (_, i) => ({ lat: 45.9 + i * 0.00005, lon: 6.1 + Math.sin(i / 50) * 0.01 }));
    const encoded = encodeWithinBudget(winding, { maxChars: 2000, firstToleranceM: 5 });
    expect(encoded.length).toBeLessThanOrEqual(2000);
    expect(decodePolyline(encoded, 5).length).toBeGreaterThan(2);
  });

  it("without a tolerance ceiling, falls back to the two ends even over budget", () => {
    const track = zigzag(50);
    const encoded = encodeWithinBudget(track, { maxChars: 5, firstToleranceM: 5 });
    expect(decodePolyline(encoded, 5)).toEqual([track[0], track.at(-1)]);
  });

  it("with a tolerance ceiling, gives up (null) once past it", () => {
    const track = zigzag(50);
    // Only 5 m is tried: every one of the 50 points remains.
    expect(encodeWithinBudget(track, { maxChars: 20, firstToleranceM: 5, maxToleranceM: 5 })).toBeNull();
    // Even the two ends exceed 5 characters.
    expect(encodeWithinBudget(track, { maxChars: 5, firstToleranceM: 5, maxToleranceM: 10_000 })).toBeNull();
    const ends = encodeWithinBudget(track, { maxChars: 20, firstToleranceM: 5, maxToleranceM: 640 });
    expect(decodePolyline(ends!, 5)).toEqual([track[0], track.at(-1)]);
  });
});
