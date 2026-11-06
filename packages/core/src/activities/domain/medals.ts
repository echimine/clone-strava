/** A Medal (ADR-039 §8): the athlete's 1st, 2nd or 3rd time at the date of the Activity. */
export const MEDALS = ["gold", "silver", "bronze"] as const;
export type Medal = (typeof MEDALS)[number];

/** One of an athlete's times on the same (record set, distance). */
export interface MedalCandidate {
  id: string;
  /** When the Activity started: the Medals are replayed in this order. */
  startedAt: Date;
  timeMs: number;
  /** A removed Best effort counts for nothing. */
  removed: boolean;
}

/**
 * The Medal of each time, replayed in date order (ADR-039 §8): gold, silver, bronze for the
 * 1st, 2nd, 3rd fastest among the times so far, the first time earning gold. An equal time does
 * not beat an earlier one and takes the next Medal. Ties on the date fall back to the id, so
 * the replay is deterministic. Pure.
 */
export function replayMedals(candidates: readonly MedalCandidate[]): Map<string, Medal | null> {
  const ordered = [...candidates].sort(
    (a, b) => a.startedAt.getTime() - b.startedAt.getTime() || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
  );
  const medals = new Map<string, Medal | null>();
  // The three fastest times so far, fastest first: a rank beyond them earns nothing.
  const podium: number[] = [];
  for (const candidate of ordered) {
    if (candidate.removed) {
      medals.set(candidate.id, null);
      continue;
    }
    const rank = podium.filter((time) => time <= candidate.timeMs).length;
    medals.set(candidate.id, MEDALS[rank] ?? null);
    if (rank < MEDALS.length) {
      podium.splice(rank, 0, candidate.timeMs);
      podium.length = Math.min(podium.length, MEDALS.length);
    }
  }
  return medals;
}
