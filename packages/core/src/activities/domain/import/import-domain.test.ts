import { describe, expect, it } from "vitest";
import type { ParsedTrackFile } from "@repo/track-files";
import { defaultActivityTitle } from "./default-title.js";
import { overlapRatio } from "./overlap.js";
import { mapFileSportToCode } from "./sport-mapping.js";
import { toImportTrace } from "./to-import-trace.js";

const parsed = (overrides: Partial<ParsedTrackFile> = {}): ParsedTrackFile => ({
  format: "gpx",
  points: [
    { lat: 48, lon: 2, timestampMs: 1_000, heartRateBpm: 120.4 },
    { lat: 48.001, lon: 2, timestampMs: 61_000 },
  ],
  pointsWithoutPosition: 0,
  ...overrides,
});

describe("mapFileSportToCode", () => {
  it.each([
    ["running", "run"],
    ["Biking", "ride"],
    ["cycling:mountain", "ride"],
    ["trail running", "run"],
    ["swimming:lap_swimming", "swim"],
    ["hiking", "hike"],
    ["walking", "walk"],
  ])("maps %s to %s", (raw, code) => {
    expect(mapFileSportToCode(raw)).toBe(code);
  });

  it("ignores unknown or missing sports", () => {
    expect(mapFileSportToCode("other")).toBeUndefined();
    expect(mapFileSportToCode(undefined)).toBeUndefined();
  });
});

describe("overlapRatio", () => {
  it("is relative to the shorter interval", () => {
    expect(overlapRatio({ startMs: 0, endMs: 100 }, { startMs: 50, endMs: 60 })).toBe(1);
    expect(overlapRatio({ startMs: 0, endMs: 100 }, { startMs: 60, endMs: 160 })).toBe(0.4);
  });

  it("is zero for disjoint or touching intervals", () => {
    expect(overlapRatio({ startMs: 0, endMs: 10 }, { startMs: 10, endMs: 20 })).toBe(0);
  });
});

describe("defaultActivityTitle", () => {
  it("uses the sport and the time of day in Paris", () => {
    expect(defaultActivityTitle("ride", new Date("2026-06-01T06:30:00Z"))).toBe("Sortie à vélo le matin");
    expect(defaultActivityTitle("run", new Date("2026-06-01T17:30:00Z"))).toBe("Course à pied le soir");
    expect(defaultActivityTitle("unknown", new Date("2026-06-01T23:30:00Z"))).toBe("Activité de nuit");
  });
});

describe("toImportTrace", () => {
  it("builds a v2 trace without Pauses, with rounded heart rate and the file bounds", () => {
    const result = toImportTrace(parsed({ startedAtMs: 0, endedAtMs: 70_000 }));
    expect(result).toMatchObject({ ok: true });
    if (!result.ok) return;
    expect(result.trace.schemaVersion).toBe(2);
    expect(result.trace.pauses).toEqual([]);
    expect(result.trace.points[0]).toMatchObject({ heartRateBpm: 120 });
    expect(result.startedAt.getTime()).toBe(0);
    expect(result.endedAt.getTime()).toBe(70_000);
  });

  it("refuses files without timestamps", () => {
    expect(toImportTrace(parsed({ points: [{ lat: 1, lon: 1 }, { lat: 2, lon: 2 }] }))).toEqual({
      ok: false,
      code: "no_timestamps",
    });
  });

  it("tells indoor files apart from empty ones", () => {
    expect(toImportTrace(parsed({ points: [], pointsWithoutPosition: 30 }))).toEqual({
      ok: false,
      code: "no_gps_data",
    });
    expect(toImportTrace(parsed({ points: [] }))).toEqual({ ok: false, code: "empty_track" });
  });

  it("refuses a zero duration", () => {
    const same = { lat: 1, lon: 1, timestampMs: 5 };
    expect(toImportTrace(parsed({ points: [same, same] }))).toEqual({
      ok: false,
      code: "invalid_duration",
    });
  });
});
