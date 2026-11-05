import type { MatchedEffort } from "./match-segment.js";
import type { EffortStatus } from "./segment-medals.js";

/** An Effort `matchSegment` found, with its Segment. */
export interface FoundEffort extends MatchedEffort {
  segmentId: string;
  segmentDistanceM: number;
}

/** What the sync reads of an Effort already stored for the Activity. */
export interface StoredEffort {
  id: string;
  segmentId: string;
  startIndex: number;
  startedAt: Date;
  elapsedTimeS: number;
  status: EffortStatus;
}

export interface EffortSyncPlan {
  inserts: Array<FoundEffort & { status: EffortStatus }>;
  /** Efforts that still exist (same Segment and start index): new figures, same row and verdict. */
  updates: Array<FoundEffort & { id: string }>;
  deletes: string[];
}

/**
 * Highest plausible average speed on a Segment, in km/h (ADR-038 §16, ADR-039 §6): above it a
 * new Effort is suspicious.
 */
export const MAX_EFFORT_SPEED_KMH: Readonly<Record<string, number>> = {
  run: 25,
  walk: 10,
  hike: 10,
  ride: 80,
};

/**
 * How the stored Efforts of an Activity become the ones just found (ADR-039 §6): an Effort that
 * still exists keeps its row and verdict; a new one inherits the verdict of the old Effort of the
 * same Segment its time overlaps most, else is checked for speed (not for a `private` Activity);
 * an old Effort with no successor goes, with its verdict.
 */
export function planEffortSync(
  previous: readonly StoredEffort[],
  found: readonly FoundEffort[],
  activity: { sportTypeCode: string; visibility: string },
): EffortSyncPlan {
  const plan: EffortSyncPlan = { inserts: [], updates: [], deletes: [] };
  const kept = new Set<string>();
  for (const effort of found) {
    const same = previous.find(
      (old) => old.segmentId === effort.segmentId && old.startIndex === effort.startIndex,
    );
    if (same) {
      kept.add(same.id);
      plan.updates.push({ id: same.id, ...effort });
      continue;
    }
    const status = inheritedStatus(previous, effort) ?? checkedStatus(effort, activity);
    plan.inserts.push({ ...effort, status });
  }
  plan.deletes = previous.filter((old) => !kept.has(old.id)).map((old) => old.id);
  return plan;
}

function inheritedStatus(previous: readonly StoredEffort[], effort: FoundEffort): EffortStatus | undefined {
  let best: { status: EffortStatus; overlapMs: number } | undefined;
  for (const old of previous) {
    if (old.segmentId !== effort.segmentId) {
      continue;
    }
    const oldStart = old.startedAt.getTime();
    const overlapMs =
      Math.min(oldStart + old.elapsedTimeS * 1000, effort.endedAtMs) - Math.max(oldStart, effort.startedAtMs);
    if (overlapMs > 0 && (!best || overlapMs > best.overlapMs)) {
      best = { status: old.status, overlapMs };
    }
  }
  return best?.status;
}

function checkedStatus(effort: FoundEffort, activity: { sportTypeCode: string; visibility: string }): EffortStatus {
  const maxKmh = MAX_EFFORT_SPEED_KMH[activity.sportTypeCode];
  if (activity.visibility === "private" || maxKmh === undefined) {
    return "valid";
  }
  const speedKmh = effort.elapsedTimeS > 0 ? (effort.segmentDistanceM / effort.elapsedTimeS) * 3.6 : Infinity;
  return speedKmh > maxKmh ? "suspicious" : "valid";
}
