/** ADR-039 §8: Medals of Efforts and Best efforts. */
export type Medal = "gold" | "silver" | "bronze";

/** ADR-038 §16: an Effort's verdict. */
export type EffortStatus = "valid" | "suspicious" | "rejected";

/** What the replay reads of one Effort of an athlete on a Segment. */
export interface MedalEffort {
  id: string;
  startedAt: Date;
  elapsedTimeS: number;
  status: EffortStatus;
}

const MEDALS: readonly Medal[] = ["gold", "silver", "bronze"];

/**
 * The Medal of each Effort of one athlete on one Segment (ADR-039 §8), replayed in date order
 * over all their Efforts whatever the visibility: an Effort gets gold, silver or bronze when its
 * time is 1st, 2nd or 3rd among the times done up to it, so the first pass earns gold and an
 * equal time does not beat an earlier one. Suspicious Efforts count; rejected ones neither count
 * nor get a Medal.
 */
export function replaySegmentMedals(efforts: readonly MedalEffort[]): Map<string, Medal | null> {
  const ordered = [...efforts].sort(
    (a, b) => a.startedAt.getTime() - b.startedAt.getTime() || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
  );
  const medals = new Map<string, Medal | null>();
  const earlierTimes: number[] = [];
  for (const effort of ordered) {
    if (effort.status === "rejected") {
      medals.set(effort.id, null);
      continue;
    }
    const rank = 1 + earlierTimes.filter((time) => time <= effort.elapsedTimeS).length;
    medals.set(effort.id, MEDALS[rank - 1] ?? null);
    earlierTimes.push(effort.elapsedTimeS);
  }
  return medals;
}
