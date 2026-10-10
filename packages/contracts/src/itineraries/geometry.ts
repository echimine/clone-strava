import { z } from "zod";

/**
 * A Waypoint of an Itinerary (`CONTEXT.md`), in WGS 84 degrees: the snapped
 * position when routing snapped it to the network (ADR-030 §2, §6).
 */
export const itineraryWaypointSchema = z.object({
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
});
export type ItineraryWaypoint = z.infer<typeof itineraryWaypointSchema>;

export const itineraryLegModeSchema = z.enum(["follow", "straight"]);
export type ItineraryLegMode = z.infer<typeof itineraryLegModeSchema>;

/**
 * A Leg joins Waypoints n and n+1 (ADR-030 §2, §6). A `follow` Leg carries
 * the Mapbox Directions geometry as is (polyline6); a `straight` Leg has no
 * geometry, the server draws it.
 */
export const itineraryLegSchema = z.discriminatedUnion("mode", [
  z.object({ mode: z.literal("follow"), polyline6: z.string().min(1) }),
  z.object({ mode: z.literal("straight") }),
]);
export type ItineraryLeg = z.infer<typeof itineraryLegSchema>;

/**
 * Waypoints and Legs of an Itinerary, shared by the save and preview bodies
 * (ADR-030 §6). Only the shape is checked here; the invariants (Leg count,
 * 2 to 200 Waypoints, size limits, Leg endpoints) belong to the
 * `itineraries` domain and also answer `422`.
 */
export const itineraryGeometrySchema = z.object({
  waypoints: z.array(itineraryWaypointSchema),
  legs: z.array(itineraryLegSchema),
});
export type ItineraryGeometry = z.infer<typeof itineraryGeometrySchema>;

/**
 * Where an Itinerary's altitudes come from (ADR-030 §3): all IGN, all
 * Open-Meteo, or both (`mixed`). The app prefixes the gain with "≈" unless
 * it is `ign`.
 */
export const itineraryElevationSourceSchema = z.enum(["ign", "mixed", "open_meteo"]);
export type ItineraryElevationSource = z.infer<typeof itineraryElevationSourceSchema>;
