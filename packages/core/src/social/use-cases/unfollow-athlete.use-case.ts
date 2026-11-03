import { Injectable } from "@nestjs/common";
import type { FollowState } from "../domain/follow-state.js";
import { FollowRepository } from "../repositories/follow.repository.js";
import { cannotFollowSelf } from "../services/follow-errors.js";
import { FollowStateReader } from "../services/follow-state-reader.js";

/**
 * `DELETE /v1/athletes/:id/follow` (ADR-036 §1): unfollow, or cancel a
 * pending request. Idempotent. Self is `422 cannot_follow_self`, as for `PUT`.
 */
@Injectable()
export class UnfollowAthleteUseCase {
  constructor(
    private readonly follows: FollowRepository,
    private readonly state: FollowStateReader,
  ) {}

  async execute(followerId: string, followeeId: string): Promise<FollowState> {
    if (followerId === followeeId) {
      throw cannotFollowSelf();
    }
    await this.follows.delete(followerId, followeeId);
    return this.state.read(followerId, followeeId);
  }
}
