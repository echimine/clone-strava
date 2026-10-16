import { describe, expect, it } from "vitest";
import { activityTopic, parseTopic, userTopic } from "./topics.js";

describe("topics", () => {
  it("round-trips a user topic", () => {
    expect(userTopic("u1")).toBe("user:u1");
    expect(parseTopic("user:u1")).toEqual({ kind: "user", userId: "u1" });
  });

  it("round-trips an activity topic (ADR-034 §5)", () => {
    expect(activityTopic("a1")).toBe("activity:a1");
    expect(parseTopic("activity:a1")).toEqual({ kind: "activity", activityId: "a1" });
  });

  it("does not recognize an empty id or another prefix", () => {
    expect(parseTopic("activity:")).toEqual({ kind: "unknown" });
    expect(parseTopic("itinerary:1")).toEqual({ kind: "unknown" });
  });
});
