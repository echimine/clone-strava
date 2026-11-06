import { replayMedals, type Medal } from "../../activities/index.js";

/** ADR-039 §8: Medals of Efforts and Best efforts, one type for both. */
export type { Medal };

/** ADR-038 §16: an Effort's verdict. */
export type EffortStatus = "valid" | "suspicious" | "rejected";

/** What the replay reads of one Effort of an athlete on a Segment. */
export interface MedalEffort {
  id: string;
  startedAt: Date;
  elapsedTimeS: number;
  status: EffortStatus;
}

/**
 * The Medal of each Effort of one athlete on one Segment (ADR-039 §8): the one replay of
 * `activities` (`replayMedals`) over all their Efforts whatever the visibility. Suspicious
 * Efforts count; rejected ones neither count nor get a Medal.
 */
export function replaySegmentMedals(efforts: readonly MedalEffort[]): Map<string, Medal | null> {
  return replayMedals(
    efforts.map((effort) => ({
      id: effort.id,
      startedAt: effort.startedAt,
      timeMs: effort.elapsedTimeS * 1000,
      removed: effort.status === "rejected",
    })),
  );
}
