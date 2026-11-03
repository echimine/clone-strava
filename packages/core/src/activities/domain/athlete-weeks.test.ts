import { describe, expect, it } from "vitest";
import { athleteWeekStart, zeroFilledWeeks } from "./athlete-weeks.js";

describe("athlete weeks (ADR-036 §4: Monday to Sunday in Europe/Paris)", () => {
  it("puts a Sunday 23:30 Paris activity in the week of that Sunday", () => {
    // Sunday 15 March 2026, 23:30 in Paris (UTC+1) is 22:30 UTC.
    expect(athleteWeekStart(new Date("2026-03-15T22:30:00Z"))).toBe("2026-03-09");
  });

  it("follows summer time: Monday 00:30 in Paris (UTC+2) already starts the next week", () => {
    // Sunday 5 July 2026 22:30 UTC is Monday 6 July 00:30 in Paris.
    expect(athleteWeekStart(new Date("2026-07-05T22:30:00Z"))).toBe("2026-07-06");
    expect(athleteWeekStart(new Date("2026-07-05T21:30:00Z"))).toBe("2026-06-29");
  });

  it("crosses a year boundary", () => {
    // Friday 1 January 2027 belongs to the week of Monday 28 December 2026.
    expect(athleteWeekStart(new Date("2027-01-01T12:00:00Z"))).toBe("2026-12-28");
  });

  describe("zeroFilledWeeks", () => {
    // Wednesday 18 March 2026: the current week starts on Monday 16 March.
    const now = new Date("2026-03-18T12:00:00Z");

    it("lists the weeks oldest first, ending with the current week, zero-filled", () => {
      const weeks = zeroFilledWeeks(now, 3, [
        { weekStart: "2026-03-16", distanceM: 5000, elevationGainM: 40, movingTimeS: 1500, activityCount: 1 },
      ]);
      expect(weeks).toEqual([
        { weekStart: "2026-03-02", distanceM: 0, elevationGainM: 0, movingTimeS: 0, activityCount: 0 },
        { weekStart: "2026-03-09", distanceM: 0, elevationGainM: 0, movingTimeS: 0, activityCount: 0 },
        { weekStart: "2026-03-16", distanceM: 5000, elevationGainM: 40, movingTimeS: 1500, activityCount: 1 },
      ]);
    });

    it("ignores totals outside the window", () => {
      const weeks = zeroFilledWeeks(now, 2, [
        { weekStart: "2026-03-02", distanceM: 9000, elevationGainM: 0, movingTimeS: 2700, activityCount: 2 },
      ]);
      expect(weeks.map((week) => week.activityCount)).toEqual([0, 0]);
    });
  });
});
