import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { parseFit, parseGpx, parseTcx } from "./index.js";

const fixture = (name: string): Uint8Array =>
  new Uint8Array(readFileSync(join(__dirname, "..", "fixtures", name)));
const T0 = Date.parse("2026-05-01T08:00:00Z");

describe("parseGpx", () => {
  const r = parseGpx(fixture("ride.gpx"));

  it("concatenates trksegs and ignores rte/wpt", () => {
    expect(r.format).toBe("gpx");
    expect(r.points).toHaveLength(3);
    expect(r.pointsWithoutPosition).toBe(0);
  });

  it("reads coordinates, elevation and time", () => {
    expect(r.points[0]).toMatchObject({ lat: 48.85, lon: 2.35, elevationM: 35.5, timestampMs: T0 });
  });

  it("reads timezone offsets as UTC", () => {
    expect(r.points[2]?.timestampMs).toBe(T0 + 2000);
  });

  it("reads gpxtpx hr/cad extensions", () => {
    expect(r.points[0]).toMatchObject({ heartRateBpm: 120, cadenceRpm: 80 });
    expect(r.points[1]?.heartRateBpm).toBe(121);
    expect(r.points[2]?.heartRateBpm).toBeUndefined();
  });

  it("reads metadata", () => {
    expect(r).toMatchObject({ name: "Morning ride", sport: "cycling", startedAtMs: T0, endedAtMs: T0 + 2000 });
  });

  it("tolerates a file without times", () => {
    const n = parseGpx(fixture("no-time.gpx"));
    expect(n.points).toHaveLength(2);
    expect(n.points[0]?.timestampMs).toBeUndefined();
    expect(n.startedAtMs).toBeUndefined();
    expect(n.endedAtMs).toBeUndefined();
  });

  it("handles single trk/trkseg/trkpt (non-array)", () => {
    const xml = `<gpx><trk><trkseg><trkpt lat="1" lon="2"/></trkseg></trk></gpx>`;
    expect(parseGpx(new TextEncoder().encode(xml)).points).toEqual([{ lat: 1, lon: 2 }]);
  });
});

describe("parseTcx", () => {
  const r = parseTcx(fixture("ride.tcx"));

  it("parses the first Activity only, with sport lowercased", () => {
    expect(r.format).toBe("tcx");
    expect(r.sport).toBe("biking");
    expect(r.points).toHaveLength(2);
  });

  it("counts trackpoints without Position", () => {
    expect(r.pointsWithoutPosition).toBe(2);
  });

  it("reads values and extensions", () => {
    expect(r.points[0]).toMatchObject({
      lat: 48.85,
      lon: 2.35,
      elevationM: 35.5,
      timestampMs: T0,
      heartRateBpm: 120,
      cadenceRpm: 80,
      speedMs: 5.5,
    });
  });

  it("uses Lap StartTime and last point time", () => {
    expect(r.startedAtMs).toBe(T0);
    expect(r.endedAtMs).toBe(T0 + 2000);
  });
});

describe("parseFit", () => {
  const r = parseFit(fixture("ride.fit"));

  it("converts semicircles to degrees and prefers enhanced fields", () => {
    expect(r.format).toBe("fit");
    expect(r.points).toHaveLength(10);
    expect(r.points[0]?.lat).toBeCloseTo(48.85, 5);
    expect(r.points[0]?.lon).toBeCloseTo(2.35, 5);
    expect(r.points[0]).toMatchObject({ elevationM: 35, heartRateBpm: 120, cadenceRpm: 80, timestampMs: T0 });
    expect(r.points[0]?.speedMs).toBeCloseTo(5, 2);
  });

  it("counts records without position", () => {
    expect(r.pointsWithoutPosition).toBe(1);
  });

  it("reads session metadata", () => {
    expect(r.sport).toBe("cycling:mountain");
    expect(r.startedAtMs).toBe(T0);
    expect(r.endedAtMs).toBe(T0 + 10_000);
    expect(r.name).toBeUndefined();
  });

  it("rejects a corrupted file", () => {
    const bad = fixture("ride.fit");
    bad[30] = (bad[30] ?? 0) ^ 0xff;
    expect(() => parseFit(bad)).toThrowError(expect.objectContaining({ code: "invalid_file" }));
  });

  it("rejects garbage with a FIT-like header only", () => {
    const bad = fixture("ride.fit").slice(0, 20);
    expect(() => parseFit(bad)).toThrowError(expect.objectContaining({ code: "invalid_file" }));
  });
});
