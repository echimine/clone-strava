export interface TimeInterval {
  startMs: number;
  endMs: number;
}

/** ADR-028 §6: two activities are the same workout above this overlap. */
export const DUPLICATE_OVERLAP_RATIO = 0.5;

/** Overlap of two intervals as a share of the shorter one (0 when disjoint). */
export function overlapRatio(a: TimeInterval, b: TimeInterval): number {
  const overlap = Math.min(a.endMs, b.endMs) - Math.max(a.startMs, b.startMs);
  const shorter = Math.min(a.endMs - a.startMs, b.endMs - b.startMs);
  if (overlap <= 0 || shorter <= 0) {
    return 0;
  }
  return overlap / shorter;
}
