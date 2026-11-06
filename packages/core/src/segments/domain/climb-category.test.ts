import { describe, expect, it } from "vitest";
import { climbCategory } from "./climb-category.js";

describe("climbCategory (score = length in m × average grade in %)", () => {
  it("gives no category under a score of 8,000", () => {
    expect(climbCategory(1_000, 7.9)).toBeNull();
    expect(climbCategory(5_000, 0)).toBeNull();
  });

  it("gives no category to a descent, however long", () => {
    expect(climbCategory(20_000, -6)).toBeNull();
  });

  it("climbs from 4 to HC at the public Strava and Garmin thresholds", () => {
    expect(climbCategory(1_000, 8)).toBe("4"); // 8,000
    expect(climbCategory(2_000, 7.9)).toBe("4"); // 15,800
    expect(climbCategory(2_000, 8)).toBe("3"); // 16,000
    expect(climbCategory(4_000, 7.9)).toBe("3"); // 31,600
    expect(climbCategory(4_000, 8)).toBe("2"); // 32,000
    expect(climbCategory(8_000, 7.9)).toBe("2"); // 63,200
    expect(climbCategory(8_000, 8)).toBe("1"); // 64,000
    expect(climbCategory(10_000, 7.9)).toBe("1"); // 79,000
    expect(climbCategory(10_000, 8)).toBe("hc"); // 80,000
  });

  it("puts the Alpe d'Huez (13.8 km at 8.1 %) hors catégorie", () => {
    expect(climbCategory(13_800, 8.1)).toBe("hc");
  });
});
