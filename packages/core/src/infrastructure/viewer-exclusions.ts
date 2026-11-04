import { notInArray, type Column, type SQL } from "drizzle-orm";

/**
 * What one viewer must not see (ADR-038 §7, the "viewer filter"), built per request by
 * `apps/api` with one query per owning module, then passed to the read methods of
 * `activities`, `engagement`, `social` and `users` as an exclusion parameter. Those modules
 * never read Blocks, Bans or Reports themselves, so none gains a dependency for it.
 */
export interface ViewerExclusions {
  /**
   * Athletes the viewer must see as nonexistent: blocked in either direction (§8), actively
   * banned (§6). Never the viewer. Their profile, Activities, Media, comments, kudos and
   * follow rows are left out; counters are not changed.
   */
  readonly hiddenAthleteIds: readonly string[];
  /** Activities the viewer reported (§9): gone for them for good, whatever the outcome. */
  readonly reportedActivityIds: readonly string[];
  /** Comments the viewer reported (§9). */
  readonly reportedCommentIds: readonly string[];
}

/** For reads made on no viewer's behalf (jobs, the author's own writes). */
export const NO_EXCLUSIONS: ViewerExclusions = Object.freeze({
  hiddenAthleteIds: [],
  reportedActivityIds: [],
  reportedCommentIds: [],
});

/** `column not in (ids)`, or no condition at all for an empty list (drizzle's `and` skips `undefined`). */
export function notInIds(column: Column, ids: readonly string[]): SQL | undefined {
  return ids.length === 0 ? undefined : notInArray(column, [...ids]);
}

/** Whether `athleteId` is hidden from the viewer. */
export function isAthleteHidden(exclusions: ViewerExclusions, athleteId: string): boolean {
  return exclusions.hiddenAthleteIds.includes(athleteId);
}
