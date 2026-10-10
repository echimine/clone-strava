/** Safeguards on an Itinerary's geometry (ADR-030 §6): violating one answers `422`. */
export const ITINERARY_LIMITS = {
  minWaypoints: 2,
  maxWaypoints: 200,
  /** Points decoded from all `follow` Legs together. */
  maxDecodedPoints: 50_000,
  maxDistanceM: 1_000_000,
  /** Max distance between each end of a `follow` Leg and its Waypoint. */
  legEndpointToleranceM: 30,
} as const;

/**
 * Elevation-gain parameters (ADR-030 §3, §7), passed to `@repo/geo`: one
 * point every 20 m along the track, 2 m hysteresis.
 */
export const ITINERARY_RESAMPLE_STEP_M = 20;
export const ITINERARY_HYSTERESIS_M = 2;
