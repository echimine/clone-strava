import { encodeWithinBudget, type LonLat } from "@repo/geo";

/**
 * Budget of the encoded route kept for the feed (ADR-029): once
 * percent-encoded, a Mapbox Static Images URL must stay under 8192
 * characters, and some polyline characters triple in size.
 */
export const FEED_POLYLINE_MAX_CHARS = 2000;

/** Douglas-Peucker tolerances tried: 5, 10, 20, … 640 m, then the route is not drawn. */
const FIRST_TOLERANCE_M = 5;
const MAX_TOLERANCE_M = 640;

/**
 * polyline5 of the (already privacy-zoned) route for the feed card map
 * (ADR-029): simplified with growing Douglas-Peucker tolerances until it
 * fits {@link FEED_POLYLINE_MAX_CHARS}. `null` when there is nothing to draw.
 */
export function feedPolyline(points: LonLat[], maxChars = FEED_POLYLINE_MAX_CHARS): string | null {
  if (points.length < 2) {
    return null;
  }
  return encodeWithinBudget(points, { maxChars, firstToleranceM: FIRST_TOLERANCE_M, maxToleranceM: MAX_TOLERANCE_M });
}
