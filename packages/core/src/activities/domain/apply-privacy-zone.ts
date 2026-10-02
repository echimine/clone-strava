import { haversineDistanceM } from "./compute-metrics.js";

export interface PrivacyZoneOptions {
  /** `user_profile.privacy_zone_radius_m` (ADR-017). */
  radiusM: number;
}

/**
 * Removes the start and end of the route that lie within `radiusM` of the
 * first and last points (ADR-019 §5 step 6) before it is stored in
 * `activity_track`: the version shown to others never reveals the exact
 * start/end (typically home). The raw trace stays private in the bucket.
 * Returns an empty array when nothing meaningful is left (fewer than two
 * points outside both zones).
 */
export function applyPrivacyZone<T extends { lat: number; lon: number }>(
  routePoints: T[],
  options: PrivacyZoneOptions,
): T[] {
  if (options.radiusM <= 0 || routePoints.length < 2) {
    return routePoints.length < 2 ? [] : routePoints;
  }
  const first = routePoints[0]!;
  const last = routePoints[routePoints.length - 1]!;

  let start = 0;
  while (start < routePoints.length && haversineDistanceM(first, routePoints[start]!) < options.radiusM) {
    start++;
  }
  let end = routePoints.length - 1;
  while (end >= start && haversineDistanceM(last, routePoints[end]!) < options.radiusM) {
    end--;
  }
  const kept = routePoints.slice(start, end + 1);
  return kept.length < 2 ? [] : kept;
}
