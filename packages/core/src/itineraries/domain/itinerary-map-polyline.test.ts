import { decodePolyline } from "@repo/geo";
import { describe, expect, it } from "vitest";
import { itineraryMapPolyline } from "./itinerary-map-polyline.js";

/** A zigzag of `count` points ~110 m apart, every turn sharper than any small tolerance. */
function zigzag(count: number) {
  return Array.from({ length: count }, (_, i) => ({ lat: 45 + i * 0.001, lon: 6 + (i % 2) * 0.001 }));
}

describe("itineraryMapPolyline", () => {
  it("keeps every point of a short track, in polyline5", () => {
    const track = zigzag(10);
    expect(decodePolyline(itineraryMapPolyline(track), 5)).toEqual(track);
  });

  it("simplifies a long track until it fits 2,000 characters", () => {
    const encoded = itineraryMapPolyline(zigzag(5_000));
    expect(encoded.length).toBeLessThanOrEqual(2000);
    expect(decodePolyline(encoded, 5).length).toBeGreaterThanOrEqual(2);
  });

  it("falls back to the two ends when no tolerance fits the budget", () => {
    const track = zigzag(50);
    expect(decodePolyline(itineraryMapPolyline(track, 20), 5)).toEqual([track[0], track.at(-1)]);
  });
});
