import { describe, expect, it } from "vitest";
import { haversineDistanceM, resampleAlongTrack } from "./index.js";

/** Meters per degree of latitude on the 6,371 km sphere (2πR / 360). */
const M_PER_DEG_LAT = 111_194.93;
/** Point `m` meters north of 45°N 6°E. */
const north = (m: number, elevationM?: number) => ({
  lat: 45 + m / M_PER_DEG_LAT,
  lon: 6,
  ...(elevationM === undefined ? {} : { elevationM }),
});
const gaps = (points: { lat: number; lon: number }[]) =>
  points.slice(1).map((p, i) => haversineDistanceM(points[i]!, p));

describe("resampleAlongTrack", () => {
  it("places points one step apart, whatever the input vertices, and keeps both ends", () => {
    const track = [north(0), north(7), north(50), north(51), north(110)];
    const resampled = resampleAlongTrack(track, 20);

    expect(resampled).toHaveLength(7); // 0, 20, 40, 60, 80, 100, 110
    for (const gap of gaps(resampled).slice(0, -1)) {
      expect(gap).toBeCloseTo(20, 3);
    }
    expect(gaps(resampled).at(-1)).toBeCloseTo(10, 3);
    expect(resampled[0]).toEqual({ lat: track[0]!.lat, lon: track[0]!.lon });
    expect(resampled.at(-1)).toEqual({ lat: track.at(-1)!.lat, lon: track.at(-1)!.lon });
  });

  it("interpolates the altitude along each leg", () => {
    const track = [north(0, 100), north(60, 106), north(100, 90)];
    const altitudes = resampleAlongTrack(track, 20).map((p) => p.elevationM);

    // 0, 20, 40, 60 climb 6 m over 60 m; 80, 100 drop 16 m over 40 m.
    for (const [i, expected] of [100, 102, 104, 106, 98, 90].entries()) {
      expect(altitudes[i]).toBeCloseTo(expected, 3);
    }
    expect(altitudes).toHaveLength(6);
  });

  it("leaves the altitude out where a leg end has none", () => {
    const track = [north(0, 100), north(40), north(80, 120)];
    const resampled = resampleAlongTrack(track, 20);

    expect(resampled).toHaveLength(5);
    expect(resampled[0]!.elevationM).toBe(100);
    expect(resampled.slice(1, 4).every((p) => p.elevationM === undefined)).toBe(true);
    expect(resampled[4]!.elevationM).toBe(120);
  });

  it("keeps only both ends of a track shorter than one step", () => {
    const track = [north(0, 100), north(5, 101), north(12, 103)];
    expect(resampleAlongTrack(track, 20)).toEqual([
      { lat: track[0]!.lat, lon: 6, elevationM: 100 },
      { lat: track[2]!.lat, lon: 6, elevationM: 103 },
    ]);
  });

  it("returns nothing for no points and the point itself for a single one", () => {
    expect(resampleAlongTrack([], 20)).toEqual([]);
    expect(resampleAlongTrack([north(0, 100)], 20)).toEqual([north(0, 100)]);
  });

  it("refuses a step that is not a positive number", () => {
    expect(() => resampleAlongTrack([north(0), north(50)], 0)).toThrow(RangeError);
    expect(() => resampleAlongTrack([north(0), north(50)], -5)).toThrow(RangeError);
    expect(() => resampleAlongTrack([north(0), north(50)], Number.NaN)).toThrow(RangeError);
  });
});
