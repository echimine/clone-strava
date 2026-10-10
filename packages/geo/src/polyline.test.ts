import { describe, expect, it } from "vitest";
import { encodePolyline } from "./index.js";

describe("encodePolyline", () => {
  it("matches Google's reference vector", () => {
    const points = [
      { lat: 38.5, lon: -120.2 },
      { lat: 40.7, lon: -120.95 },
      { lat: 43.252, lon: -126.453 },
    ];
    expect(encodePolyline(points)).toBe("_p~iF~ps|U_ulLnnqC_mqNvxq`@");
  });

  it("returns an empty string for no points", () => {
    expect(encodePolyline([])).toBe("");
  });
});
