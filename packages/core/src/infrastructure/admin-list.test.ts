import { describe, expect, it } from "vitest";
import { offsetPage, parisDayRange, toOffsetPage } from "./admin-list.js";

describe("parisDayRange (ADR-038 §2: days cut in Europe/Paris time)", () => {
  it("starts a summer day at 22:00 UTC the evening before", () => {
    expect(parisDayRange({ from: "2026-07-01" })).toEqual({ start: new Date("2026-06-30T22:00:00Z") });
  });

  it("starts a winter day at 23:00 UTC the evening before", () => {
    expect(parisDayRange({ from: "2026-12-01" })).toEqual({ start: new Date("2026-11-30T23:00:00Z") });
  });

  it("ends a period at the start of the day after `to`, so `to` is included", () => {
    expect(parisDayRange({ to: "2026-11-04" })).toEqual({ end: new Date("2026-11-04T23:00:00Z") });
  });

  it("handles the days the clocks change", () => {
    // 2026-03-29: Paris moves from UTC+1 to UTC+2 at 01:00 UTC.
    expect(parisDayRange({ from: "2026-03-29", to: "2026-03-29" })).toEqual({
      start: new Date("2026-03-28T23:00:00Z"),
      end: new Date("2026-03-29T22:00:00Z"),
    });
    // 2026-10-25: back from UTC+2 to UTC+1.
    expect(parisDayRange({ from: "2026-10-25", to: "2026-10-25" })).toEqual({
      start: new Date("2026-10-24T22:00:00Z"),
      end: new Date("2026-10-25T23:00:00Z"),
    });
  });

  it("has no bound for a missing end", () => {
    expect(parisDayRange({})).toEqual({});
  });
});

describe("offset pages (ADR-038 §2)", () => {
  it("turns a page into a limit and an offset", () => {
    expect(offsetPage({ page: 3, pageSize: 25 })).toEqual({ limit: 25, offset: 50 });
  });

  it("answers items, total, page and page size", () => {
    expect(toOffsetPage(["a"], 26, { page: 2, pageSize: 25 })).toEqual({
      items: ["a"],
      total: 26,
      page: 2,
      pageSize: 25,
    });
  });
});
