import type { Itinerary, ItinerarySavedProperties } from "@repo/contracts";

/** Sport categories an Itinerary can be planned for (ADR-030 §2: no `water`). */
export type ItinerarySportCategory = ItinerarySavedProperties["sportCategory"];

/**
 * Properties of `itinerary_created` / `itinerary_updated` (ADR-030 §10,
 * catalog of issue #20): rounded figures (whole km, gain to 10 m, share of
 * straight Legs to 0.1) and never a coordinate.
 */
export function itinerarySavedProperties(
  itinerary: Pick<Itinerary, "id" | "sportTypeCode" | "distanceM" | "elevationGainM" | "elevationSource"> & {
    waypoints: readonly unknown[];
    legs: readonly Pick<Itinerary["legs"][number], "mode">[];
  },
  sportCategory: ItinerarySportCategory,
): ItinerarySavedProperties {
  const straightLegs = itinerary.legs.filter((leg) => leg.mode === "straight").length;
  return {
    itineraryId: itinerary.id,
    sportTypeCode: itinerary.sportTypeCode,
    sportCategory,
    waypointCount: itinerary.waypoints.length,
    straightLegRatio: Math.round((straightLegs / itinerary.legs.length) * 10) / 10,
    distanceKm: Math.round(itinerary.distanceM / 1000),
    elevationGainM: Math.round(itinerary.elevationGainM / 10) * 10,
    elevationSource: itinerary.elevationSource,
  };
}
