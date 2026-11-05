import { describe, expect, it } from "vitest";
import { replayMedals, type MedalCandidate } from "./medals.js";

const day = (n: number) => new Date(Date.UTC(2026, 0, n));

function candidate(id: string, dayOfJanuary: number, timeMs: number, removed = false): MedalCandidate {
  return { id, startedAt: day(dayOfJanuary), timeMs, removed };
}

function medalsOf(candidates: MedalCandidate[]) {
  return Object.fromEntries(replayMedals(candidates));
}

describe("replayMedals", () => {
  it("gives the first time gold, then each time its rank among the times so far", () => {
    expect(
      medalsOf([
        candidate("a", 1, 1_500_000),
        candidate("b", 2, 1_600_000),
        candidate("c", 3, 1_400_000),
        candidate("d", 4, 1_550_000),
        candidate("e", 5, 1_700_000),
      ]),
    ).toEqual({ a: "gold", b: "silver", c: "gold", d: "bronze", e: null });
  });

  it("replays in date order, whatever the input order", () => {
    expect(medalsOf([candidate("late", 9, 1_000), candidate("early", 1, 2_000)])).toEqual({
      early: "gold",
      late: "gold",
    });
  });

  it("does not let an equal time beat an earlier one: it takes the next Medal", () => {
    expect(
      medalsOf([candidate("a", 1, 1_000), candidate("b", 2, 1_000), candidate("c", 3, 1_000)]),
    ).toEqual({ a: "gold", b: "silver", c: "bronze" });
  });

  it("leaves removed Best efforts out of the ranking, with no Medal", () => {
    expect(
      medalsOf([candidate("a", 1, 1_000, true), candidate("b", 2, 2_000), candidate("c", 3, 3_000)]),
    ).toEqual({ a: null, b: "gold", c: "silver" });
  });
});
