import { encodeWithinBudget, type LonLat } from "@repo/geo";

/**
 * Budget of `map_polyline` (ADR-030 §5, same as ADR-029): once
 * percent-encoded, a Mapbox Static Images URL must stay under 8192
 * characters, and some polyline characters triple in size.
 */
export const ITINERARY_MAP_POLYLINE_MAX_CHARS = 2000;

const FIRST_TOLERANCE_M = 5;

/**
 * polyline5 of the track for the list thumbnail (ADR-030 §5): simplified
 * with a Douglas-Peucker tolerance doubled from 5 m until it fits the
 * budget. Never null for a track of 2 points or more: past the track's
 * extent only its two ends remain, which always fit.
 */
export function itineraryMapPolyline(track: LonLat[], maxChars = ITINERARY_MAP_POLYLINE_MAX_CHARS): string {
  if (track.length < 2) {
    throw new RangeError("An Itinerary track has at least 2 points");
  }
  return encodeWithinBudget(track, { maxChars, firstToleranceM: FIRST_TOLERANCE_M });
}
