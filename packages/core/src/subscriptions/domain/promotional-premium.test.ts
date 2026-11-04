import { describe, expect, it } from "vitest";
import { promotionalPremiumEnd } from "./promotional-premium.js";

describe("promotionalPremiumEnd (ADR-038 §12)", () => {
  it("adds 1, 3, 6 or 12 calendar months at the same time", () => {
    const now = new Date("2026-11-04T09:30:00Z");
    expect(promotionalPremiumEnd(now, "1m")).toEqual(new Date("2026-12-04T09:30:00Z"));
    expect(promotionalPremiumEnd(now, "3m")).toEqual(new Date("2027-02-04T09:30:00Z"));
    expect(promotionalPremiumEnd(now, "6m")).toEqual(new Date("2027-05-04T09:30:00Z"));
    expect(promotionalPremiumEnd(now, "12m")).toEqual(new Date("2027-11-04T09:30:00Z"));
  });

  it("falls back to the month's last day", () => {
    expect(promotionalPremiumEnd(new Date("2027-01-31T08:00:00Z"), "1m")).toEqual(new Date("2027-02-28T08:00:00Z"));
    expect(promotionalPremiumEnd(new Date("2027-08-31T08:00:00Z"), "6m")).toEqual(new Date("2028-02-29T08:00:00Z"));
  });
});
