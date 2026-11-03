/**
 * The viewer's relation to an athlete (ADR-036 §1). `null` stands for the
 * viewer themself wherever a list may contain them.
 */
export type FollowRelation = "none" | "pending" | "accepted";

/** What `PUT` / `DELETE /v1/athletes/:id/follow` answers (ADR-036 §1). */
export interface FollowState {
  athleteId: string;
  viewerFollowStatus: FollowRelation;
  followerCount: number;
}

/** An athlete's accepted followers and accepted followees (ADR-036 §1, §3). */
export interface FollowCounts {
  followerCount: number;
  followingCount: number;
}
