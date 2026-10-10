import { describe, expect, it } from "vitest";
import { itinerarySavedProperties } from "./itinerary-analytics.js";

const itinerary = {
  id: "0b4e7c1e-3c43-4a53-9a5e-0d7f4f1c2a11",
  sportTypeCode: "ride",
  waypoints: [
    { lat: 45.9, lon: 6.12 },
    { lat: 45.91, lon: 6.12 },
    { lat: 45.92, lon: 6.12 },
    { lat: 45.93, lon: 6.12 },
  ],
  legs: [{ mode: "follow" as const }, { mode: "straight" as const }, { mode: "follow" as const }],
  distanceM: 42_499.9,
  elevationGainM: 1_234.9,
  elevationSource: "mixed" as const,
};

describe("itinerarySavedProperties", () => {
  it("rounds the figures as the catalog asks and carries no coordinate", () => {
    expect(itinerarySavedProperties(itinerary, "wheels")).toEqual({
      itineraryId: "0b4e7c1e-3c43-4a53-9a5e-0d7f4f1c2a11",
      sportTypeCode: "ride",
      sportCategory: "wheels",
      waypointCount: 4,
      straightLegRatio: 0.3,
      distanceKm: 42,
      elevationGainM: 1_230,
      elevationSource: "mixed",
    });
  });

  it("rounds halves up: 42.5 km, 1,235 m and two straight Legs out of three", () => {
    const properties = itinerarySavedProperties(
      {
        ...itinerary,
        distanceM: 42_500,
        elevationGainM: 1_235,
        legs: [{ mode: "straight" }, { mode: "straight" }, { mode: "follow" }],
      },
      "foot",
    );
    expect(properties).toMatchObject({ distanceKm: 43, elevationGainM: 1_240, straightLegRatio: 0.7 });
  });
});
