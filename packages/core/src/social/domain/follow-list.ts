import type { FollowRelation } from "./follow-state.js";

/** Which side of `follow` a list shows (ADR-036 §1). */
export type FollowListKind = "followers" | "following";

/**
 * One athlete of a follow list. The athlete is an id only: `apps/api`
 * assembles identities (ADR-029 §2). `viewerFollowStatus` is `null` for
 * the viewer themself; `since` is when the follow (or the request) was made.
 */
export interface FollowListEntry {
  athleteId: string;
  viewerFollowStatus: FollowRelation | null;
  since: Date;
}

/** A page of a follow list, most recent first; `nextCursor` is null on the last page. */
export interface FollowListPage {
  items: FollowListEntry[];
  nextCursor: string | null;
}
