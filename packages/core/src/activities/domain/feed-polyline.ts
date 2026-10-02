import { encodePolyline } from "./encode-polyline.js";
import { simplifyRoute, type LonLat } from "./simplify-route.js";

/**
 * Budget of the encoded route kept for the feed (ADR-029): once
 * percent-encoded, a Mapbox Static Images URL must stay under 8192
 * characters, and some polyline characters triple in size.
 */
export const FEED_POLYLINE_MAX_CHARS = 2000;

const TOLERANCES_M = [5, 10, 20, 40, 80, 160, 320, 640];

/**
 * polyline5 of the (already privacy-zoned) route for the feed card map
 * (ADR-029): simplified with growing Douglas-Peucker tolerances until it
 * fits {@link FEED_POLYLINE_MAX_CHARS}. `null` when there is nothing to draw.
 */
export function feedPolyline(points: LonLat[], maxChars = FEED_POLYLINE_MAX_CHARS): string | null {
  if (points.length < 2) {
    return null;
  }
  for (const tolerance of TOLERANCES_M) {
    const encoded = encodePolyline(simplifyRoute(points, tolerance));
    if (encoded.length <= maxChars) {
      return encoded;
    }
  }
  return null;
}
