import { describe, expect, it } from "vitest";
import { elevationGainM } from "./index.js";

describe("elevationGainM", () => {
  it("counts a real climb in full, including the steps smaller than the threshold", () => {
    expect(elevationGainM([100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110], 2)).toBe(10);
  });

  it("ignores noise below the threshold on flat ground", () => {
    expect(elevationGainM([100, 101.5, 100, 101.9, 100.2, 101, 100, 101.8, 100], 2)).toBe(0);
  });

  it("ignores noise below the threshold during a climb and at its top", () => {
    // Climbs 100 → 110 with 1.5 m dips, then wobbles at the top.
    expect(elevationGainM([100, 104, 102.5, 107, 105.5, 110, 109, 110, 108.5, 110], 2)).toBe(10);
  });

  it("counts each climb separated by a real descent", () => {
    // +20, -15, +12 (from the bottom of the descent).
    expect(elevationGainM([100, 110, 120, 112, 105, 108, 117], 2)).toBe(32);
  });

  it("counts a climb from the lowest point of a preceding descent", () => {
    expect(elevationGainM([100, 99, 98, 99.5, 100.5], 2)).toBe(2.5);
  });

  it("is zero for fewer than two altitudes", () => {
    expect(elevationGainM([], 2)).toBe(0);
    expect(elevationGainM([1200], 2)).toBe(0);
  });

  it("sums every rise with a zero threshold", () => {
    expect(elevationGainM([100, 101, 100, 101], 0)).toBe(2);
  });

  it("refuses a negative threshold", () => {
    expect(() => elevationGainM([100, 110], -1)).toThrow(RangeError);
  });
});
