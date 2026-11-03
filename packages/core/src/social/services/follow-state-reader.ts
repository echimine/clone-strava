import { Injectable } from "@nestjs/common";
import type { FollowState } from "../domain/follow-state.js";
import { FollowRepository } from "../repositories/follow.repository.js";

/** The viewer's relation to one athlete and that athlete's follower count, after a change (ADR-036 §1). */
@Injectable()
export class FollowStateReader {
  constructor(private readonly follows: FollowRepository) {}

  async read(viewerId: string, athleteId: string): Promise<FollowState> {
    const [row, followers] = await Promise.all([
      this.follows.findOne(viewerId, athleteId),
      this.follows.countFollowers([athleteId]),
    ]);
    return {
      athleteId,
      viewerFollowStatus: row?.status ?? "none",
      followerCount: followers.get(athleteId) ?? 0,
    };
  }
}
