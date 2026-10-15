import { describe, expect, it } from "vitest";
import { traceSchema } from "./trace.js";

const point = (timestampMs: number) => ({ timestampMs, lat: 48, lon: 2 });
const points = [point(1_000), point(10_000), point(60_000), point(70_000), point(120_000)];

describe("traceSchema (v2)", () => {
  it("accepts a trace whose Pauses lie between points", () => {
    const result = traceSchema.safeParse({
      schemaVersion: 2,
      points,
      pauses: [
        { startMs: 15_000, endMs: 55_000 },
        { startMs: 80_000, endMs: 110_000 },
      ],
    });

    expect(result.success).toBe(true);
  });

  it("accepts a Pause that starts and ends on point timestamps", () => {
    // An automatic Pause ends on the last point near the stop (ADR-031 §4).
    const result = traceSchema.safeParse({
      schemaVersion: 2,
      points,
      pauses: [{ startMs: 10_000, endMs: 60_000 }],
    });

    expect(result.success).toBe(true);
  });

  it.each([
    ["before the first point", { startMs: 0, endMs: 500 }],
    ["after the last point", { startMs: 125_000, endMs: 130_000 }],
    ["with a point inside", { startMs: 5_000, endMs: 65_000 }],
  ])("rejects a Pause %s", (_label, pause) => {
    const result = traceSchema.safeParse({ schemaVersion: 2, points, pauses: [pause] });

    expect(result.success).toBe(false);
  });

  it.each([
    [
      "overlap",
      [
        { startMs: 15_000, endMs: 40_000 },
        { startMs: 30_000, endMs: 55_000 },
      ],
    ],
    [
      "are out of order",
      [
        { startMs: 80_000, endMs: 110_000 },
        { startMs: 15_000, endMs: 55_000 },
      ],
    ],
  ])("rejects Pauses that %s", (_label, pauses) => {
    const result = traceSchema.safeParse({ schemaVersion: 2, points, pauses });

    expect(result.success).toBe(false);
  });

  it("rejects a v1 trace", () => {
    const result = traceSchema.safeParse({ schemaVersion: 1, points });

    expect(result.success).toBe(false);
  });
});
