import { Injectable } from "@nestjs/common";
import { FollowRepository } from "../repositories/follow.repository.js";

/**
 * Backs `SocialService.getFolloweeIds` (ADR-021 §2 rule 6, §6 feed
 * example): the accepted followees of a user, used by `activities` to
 * build the feed.
 */
@Injectable()
export class GetFolloweeIdsUseCase {
  constructor(private readonly follows: FollowRepository) {}

  async execute(userId: string): Promise<string[]> {
    const rows = await this.follows.findFolloweeIds(userId);
    return rows.map((row) => row.followeeId);
  }
}
