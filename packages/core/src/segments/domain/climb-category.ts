/** ADR-039 §5: the climb category of a Segment, from 4 (easiest) to HC (hors catégorie). */
export type ClimbCategory = "hc" | "1" | "2" | "3" | "4";

/** Lowest score of each category, hardest first: the public Strava and Garmin thresholds. */
const THRESHOLDS: ReadonlyArray<readonly [number, ClimbCategory]> = [
  [80_000, "hc"],
  [64_000, "1"],
  [32_000, "2"],
  [16_000, "3"],
  [8_000, "4"],
];

/**
 * ADR-039 §5: score = length (m) × average grade (%); no category under 8,000. Pure, shared by
 * the Segments an athlete draws and by the Nervo generator (§10).
 */
export function climbCategory(lengthM: number, averageGradePct: number): ClimbCategory | null {
  const score = lengthM * averageGradePct;
  return THRESHOLDS.find(([minScore]) => score >= minScore - 1e-6)?.[1] ?? null;
}
