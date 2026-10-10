import { encodePolyline } from "./polyline.js";
import { simplifyTrack } from "./simplify.js";
import type { LonLat } from "./types.js";

export interface EncodeBudget {
  /** Max length of the polyline5. */
  maxChars: number;
  /** First Douglas-Peucker tolerance, in meters, doubled at each round. */
  firstToleranceM: number;
  /**
   * Last tolerance tried before giving up (`null`). Without it, the loop
   * runs until only the two ends remain, and returns them even over budget.
   */
  maxToleranceM?: number;
}

/**
 * polyline5 of `points` simplified with a Douglas-Peucker tolerance doubled
 * from `firstToleranceM` until it fits `maxChars` (ADR-029, ADR-030 §5: the
 * budget of a Mapbox Static Images URL).
 */
export function encodeWithinBudget(points: LonLat[], budget: Omit<EncodeBudget, "maxToleranceM">): string;
export function encodeWithinBudget(points: LonLat[], budget: EncodeBudget): string | null;
export function encodeWithinBudget(points: LonLat[], budget: EncodeBudget): string | null {
  const { maxChars, firstToleranceM, maxToleranceM = Number.POSITIVE_INFINITY } = budget;
  for (let toleranceM = firstToleranceM; toleranceM <= maxToleranceM; toleranceM *= 2) {
    const simplified = simplifyTrack(points, toleranceM);
    const encoded = encodePolyline(simplified);
    if (encoded.length <= maxChars) {
      return encoded;
    }
    if (simplified.length <= 2) {
      // No larger tolerance can drop another point.
      return budget.maxToleranceM === undefined ? encoded : null;
    }
  }
  return null;
}
