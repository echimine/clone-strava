import { describe, expect, it } from "vitest";
import { climbCategory } from "./climb-category.js";

describe("climbCategory (ADR-039 §5: length in meters × average grade in %)", () => {
  it("has no category under a score of 8,000", () => {
    expect(climbCategory(500, 7)).toBeNull(); // 3,500
    expect(climbCategory(1_999, 4)).toBeNull(); // 7,996
  });

  it("is a 4 from 8,000", () => {
    expect(climbCategory(2_000, 4)).toBe("4");
    expect(climbCategory(2_000, 5)).toBe("4"); // 10,000
  });

  it("climbs through 3, 2, 1 at 16,000, 32,000, 64,000", () => {
    expect(climbCategory(4_000, 4)).toBe("3");
    expect(climbCategory(5_000, 6.4)).toBe("2");
    expect(climbCategory(8_000, 8)).toBe("1");
  });

  it("is HC from 80,000, like a great Alpine pass", () => {
    expect(climbCategory(18_000, 7)).toBe("hc"); // 126,000
    expect(climbCategory(10_000, 8)).toBe("hc");
  });

  it("has no category for a descent", () => {
    expect(climbCategory(10_000, -8)).toBeNull();
  });
});
