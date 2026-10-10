import { encodePolyline, type LonLat } from "@repo/geo";
import type { Itinerary, ItineraryElevationSource, ItineraryLegMode, ItinerarySummary } from "@repo/contracts";

/** A stored Itinerary as the repositories read it back. */
export interface StoredItinerary {
  id: string;
  name: string;
  sportTypeCode: string;
  distanceM: number;
  elevationGainM: number;
  elevationSource: ItineraryElevationSource;
  track: (LonLat & { altitudeM: number })[];
  createdAt: Date;
  updatedAt: Date;
  waypoints: LonLat[];
  legs: { mode: ItineraryLegMode; path: LonLat[] }[];
}

/** Stored Itinerary -> `GET /v1/itineraries/:id` (ADR-030 §6): paths as polyline6. */
export function toItinerary(stored: StoredItinerary): Itinerary {
  return {
    id: stored.id,
    name: stored.name,
    sportTypeCode: stored.sportTypeCode,
    waypoints: stored.waypoints,
    legs: stored.legs.map((leg) => ({ mode: leg.mode, polyline6: encodePolyline(leg.path, 6) })),
    distanceM: stored.distanceM,
    elevationGainM: stored.elevationGainM,
    elevationSource: stored.elevationSource,
    track: {
      polyline6: encodePolyline(stored.track, 6),
      altitudesM: stored.track.map((point) => point.altitudeM),
    },
    createdAt: stored.createdAt.toISOString(),
    updatedAt: stored.updatedAt.toISOString(),
  };
}

/** A list row (ADR-030 §6). */
export function toItinerarySummary(row: {
  id: string;
  name: string;
  sportTypeCode: string;
  distanceM: number;
  elevationGainM: number;
  mapPolyline: string;
  updatedAt: Date;
}): ItinerarySummary {
  return {
    id: row.id,
    name: row.name,
    sportTypeCode: row.sportTypeCode,
    distanceM: row.distanceM,
    elevationGainM: row.elevationGainM,
    mapPolyline: row.mapPolyline,
    updatedAt: row.updatedAt.toISOString(),
  };
}
