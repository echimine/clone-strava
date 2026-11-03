import { describe, expect, it } from "vitest";
import { streakWeeks } from "./streak.js";

describe("streakWeeks (ADR-036 §4 Streak)", () => {
  // Wednesday 18 March 2026: the current week starts on Monday 16 March.
  const now = new Date("2026-03-18T12:00:00Z");

  it("counts consecutive active weeks ending with the current one", () => {
    expect(streakWeeks(["2026-03-16", "2026-03-09", "2026-03-02", "2026-02-16"], now)).toBe(3);
  });

  it("does not break on an empty current week: it ends with the previous week", () => {
    expect(streakWeeks(["2026-03-09", "2026-03-02"], now)).toBe(2);
  });

  it("is broken by an empty week", () => {
    expect(streakWeeks(["2026-03-16", "2026-03-02"], now)).toBe(1);
  });

  it("is zero when neither the current nor the previous week has an Activity", () => {
    expect(streakWeeks(["2026-03-02"], now)).toBe(0);
    expect(streakWeeks([], now)).toBe(0);
  });
});
