import { describe, expect, it } from "vitest";
import { decodePolyline, encodePolyline, InvalidPolylineError } from "./index.js";

const googleReference = [
  { lat: 38.5, lon: -120.2 },
  { lat: 40.7, lon: -120.95 },
  { lat: 43.252, lon: -126.453 },
];

describe("encodePolyline", () => {
  it("matches Google's reference vector", () => {
    expect(encodePolyline(googleReference)).toBe("_p~iF~ps|U_ulLnnqC_mqNvxq`@");
  });

  it("returns an empty string for no points", () => {
    expect(encodePolyline([])).toBe("");
  });
});

describe("decodePolyline", () => {
  it("decodes Google's reference vector (polyline5 by default)", () => {
    expect(decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")).toEqual(googleReference);
  });

  it("decodes polyline6, the Mapbox Directions geometry", () => {
    // Mapbox's documented polyline6 sample (`geometries=polyline6`).
    const points = decodePolyline("_izlhA~rlgdF_{geC~ywl@_kwzCn`{nI", 6);
    expect(points).toEqual([
      { lat: 38.5, lon: -120.2 },
      { lat: 40.7, lon: -120.95 },
      { lat: 43.252, lon: -126.453 },
    ]);
  });

  it("round-trips with encodePolyline at precision 6, to the micro-degree", () => {
    const points = [
      { lat: 45.899247, lon: 6.129384 },
      { lat: 45.899251, lon: 6.129399 },
      { lat: -33.868819, lon: 151.209295 },
    ];
    expect(decodePolyline(encodePolyline(points, 6), 6)).toEqual(points);
  });

  it("returns no points for an empty string", () => {
    expect(decodePolyline("", 6)).toEqual([]);
  });

  it("rejects malformed input instead of returning garbage", () => {
    // Truncated value: the last character still has its continuation bit.
    expect(() => decodePolyline("_p~iF~ps|U_", 5)).toThrow(InvalidPolylineError);
    // A latitude without its longitude.
    expect(() => decodePolyline("_p~iF", 5)).toThrow(InvalidPolylineError);
    // Characters outside the encoding alphabet (63..126).
    expect(() => decodePolyline("_p~iF ps|U", 5)).toThrow(InvalidPolylineError);
  });
});
