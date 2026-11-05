import { describe, expect, it } from "vitest";
import { planEffortSync, type FoundEffort, type StoredEffort } from "./effort-sync.js";

const T0 = Date.UTC(2026, 10, 5, 8);
const SEGMENT = "segment-1";

/** An Effort found on a 1 km Segment, `startS` seconds into the Activity, lasting `timeS`. */
function found(startIndex: number, startS: number, timeS: number, segmentId = SEGMENT): FoundEffort {
  return {
    segmentId,
    segmentDistanceM: 1000,
    startIndex,
    endIndex: startIndex + timeS,
    startedAtMs: T0 + startS * 1000,
    endedAtMs: T0 + (startS + timeS) * 1000,
    elapsedTimeS: timeS,
    minDistanceToActivityStartM: 300,
    minDistanceToActivityEndM: 400,
  };
}

function stored(
  id: string,
  startIndex: number,
  startS: number,
  timeS: number,
  status: StoredEffort["status"],
): StoredEffort {
  return {
    id,
    segmentId: SEGMENT,
    startIndex,
    startedAt: new Date(T0 + startS * 1000),
    elapsedTimeS: timeS,
    status,
  };
}

const RUN_PUBLIC = { sportTypeCode: "run", visibility: "public" } as const;

describe("planEffortSync", () => {
  it("inserts new Efforts as valid", () => {
    const plan = planEffortSync([], [found(10, 10, 300)], RUN_PUBLIC);

    expect(plan.inserts).toEqual([{ ...found(10, 10, 300), status: "valid" }]);
    expect(plan.updates).toEqual([]);
    expect(plan.deletes).toEqual([]);
  });

  it("marks a new Effort suspicious above the sport's maximum speed", () => {
    // 1 km in 120 s is 30 km/h, above 25 km/h on foot but not by bike.
    expect(planEffortSync([], [found(10, 10, 120)], RUN_PUBLIC).inserts[0]!.status).toBe("suspicious");
    expect(
      planEffortSync([], [found(10, 10, 120)], { sportTypeCode: "ride", visibility: "public" }).inserts[0]!.status,
    ).toBe("valid");
    // 1 km in 300 s is 12 km/h: too fast for a walk.
    expect(
      planEffortSync([], [found(10, 10, 300)], { sportTypeCode: "walk", visibility: "followers" }).inserts[0]!.status,
    ).toBe("suspicious");
  });

  it("does not check the Efforts of a private Activity", () => {
    expect(
      planEffortSync([], [found(10, 10, 120)], { sportTypeCode: "run", visibility: "private" }).inserts[0]!.status,
    ).toBe("valid");
  });

  it("keeps an Effort that still exists, with its verdict and new figures", () => {
    const plan = planEffortSync([stored("old", 10, 10, 300, "rejected")], [found(10, 10, 120)], RUN_PUBLIC);

    expect(plan.inserts).toEqual([]);
    expect(plan.deletes).toEqual([]);
    expect(plan.updates).toEqual([{ id: "old", ...found(10, 10, 120) }]);
  });

  it("passes the verdict of the old Effort it overlaps most to a new one", () => {
    const plan = planEffortSync(
      [stored("a", 5, 5, 100, "rejected"), stored("b", 20, 20, 300, "suspicious")],
      [found(12, 12, 300)],
      RUN_PUBLIC,
    );

    expect(plan.inserts).toEqual([{ ...found(12, 12, 300), status: "suspicious" }]);
    expect(plan.deletes.sort()).toEqual(["a", "b"]);
  });

  it("does not inherit across Segments", () => {
    const plan = planEffortSync([stored("a", 12, 12, 300, "rejected")], [found(12, 12, 300, "segment-2")], RUN_PUBLIC);

    expect(plan.inserts[0]!.status).toBe("valid");
    expect(plan.deletes).toEqual(["a"]);
  });

  it("deletes an old Effort with no successor, verdict included", () => {
    const plan = planEffortSync([stored("gone", 10, 10, 300, "rejected")], [], RUN_PUBLIC);

    expect(plan).toEqual({ inserts: [], updates: [], deletes: ["gone"] });
  });
});
