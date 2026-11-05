import { describe, expect, it } from "vitest";
import { replaySegmentMedals, type MedalEffort } from "./segment-medals.js";

const DAY_MS = 86_400_000;
const T0 = Date.UTC(2026, 0, 1);

/** The athlete's Efforts on one Segment, one per day, in this order. */
function efforts(...times: Array<number | [number, MedalEffort["status"]]>): MedalEffort[] {
  return times.map((time, day) => {
    const [elapsedTimeS, status] = typeof time === "number" ? [time, "valid" as const] : time;
    return { id: `e${day + 1}`, startedAt: new Date(T0 + day * DAY_MS), elapsedTimeS, status };
  });
}

describe("replaySegmentMedals", () => {
  it("gives gold to the first pass", () => {
    expect(replaySegmentMedals(efforts(300))).toEqual(new Map([["e1", "gold"]]));
  });

  it("ranks each Effort among the times done up to it", () => {
    const medals = replaySegmentMedals(efforts(300, 280, 290, 310, 270));

    expect([...medals.values()]).toEqual(["gold", "gold", "silver", null, "gold"]);
  });

  it("does not let an equal time beat an earlier one", () => {
    expect([...replaySegmentMedals(efforts(300, 300, 300, 300)).values()]).toEqual([
      "gold",
      "silver",
      "bronze",
      null,
    ]);
  });

  it("counts suspicious Efforts and leaves rejected ones out, with no Medal", () => {
    const medals = replaySegmentMedals(efforts([250, "rejected"], 300, [290, "suspicious"], 295));

    expect(medals).toEqual(
      new Map([
        ["e1", null],
        ["e2", "gold"],
        ["e3", "gold"],
        ["e4", "silver"],
      ]),
    );
  });

  it("replays in date order whatever the input order", () => {
    const [first, second] = efforts(300, 280);

    expect(replaySegmentMedals([second!, first!])).toEqual(
      new Map([
        ["e1", "gold"],
        ["e2", "gold"],
      ]),
    );
  });
});
