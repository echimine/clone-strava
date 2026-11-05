/** ADR-039 §5: the climb category of a Segment, stored as `segments.climb_category`. */
export type ClimbCategory = "hc" | "1" | "2" | "3" | "4";

/** Lowest score of each category, highest first (Strava's and Garmin's public rule). */
const CATEGORY_THRESHOLDS: ReadonlyArray<readonly [ClimbCategory, number]> = [
  ["hc", 80_000],
  ["1", 64_000],
  ["2", 32_000],
  ["3", 16_000],
  ["4", 8_000],
];

/**
 * The climb category from the length × grade rule (ADR-039 §5, §10): score = length in meters ×
 * average grade in percent; no category under 8,000. Shared by Segments drawn by athletes and the
 * Nervo generator.
 */
export function climbCategory(lengthM: number, averageGradePct: number): ClimbCategory | null {
  const score = lengthM * averageGradePct;
  return CATEGORY_THRESHOLDS.find(([, threshold]) => score >= threshold)?.[0] ?? null;
}
