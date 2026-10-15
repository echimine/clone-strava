import type { TracePause } from "@repo/contracts";

interface Timestamped {
  timestampMs: number;
}

/**
 * A leg straddles a Pause when the Pause lies within its time span
 * (ADR-031 §12): the athlete may have moved (train, car) and nothing about
 * that leg counts.
 */
export function straddlesPause(prev: Timestamped, curr: Timestamped, pauses: TracePause[]): boolean {
  return pauses.some((pause) => prev.timestampMs <= pause.startMs && curr.timestampMs >= pause.endMs);
}
