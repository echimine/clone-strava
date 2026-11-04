import { describe, expect, it } from "vitest";
import { statsPeriodWindow } from "./stats-period.js";

/** The Growth band's periods (ADR-038 §15): whole Paris days, today included, vs the days before. */
describe("statsPeriodWindow", () => {
  it("covers the last 7 Paris days, today included, and the 7 days before them", () => {
    const window = statsPeriodWindow("7d", new Date("2026-11-04T10:00:00Z"));

    expect(window.days).toEqual([
      "2026-10-29",
      "2026-10-30",
      "2026-10-31",
      "2026-11-01",
      "2026-11-02",
      "2026-11-03",
      "2026-11-04",
    ]);
    // Paris is UTC+1 in November and was UTC+2 before 25 October.
    expect(window.current).toEqual({
      start: new Date("2026-10-28T23:00:00Z"),
      end: new Date("2026-11-04T23:00:00Z"),
    });
    expect(window.previous).toEqual({
      start: new Date("2026-10-21T22:00:00Z"),
      end: new Date("2026-10-28T23:00:00Z"),
    });
  });

  it("takes today in Paris, not in UTC, just after midnight", () => {
    const window = statsPeriodWindow("30d", new Date("2026-11-04T23:30:00Z"));

    expect(window.days).toHaveLength(30);
    expect(window.days.at(-1)).toBe("2026-11-05");
    expect(window.days[0]).toBe("2026-10-07");
  });

  it("has 90 days for 90d", () => {
    expect(statsPeriodWindow("90d", new Date("2026-11-04T10:00:00Z")).days).toHaveLength(90);
  });
});
