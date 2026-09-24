import { Injectable } from "@nestjs/common";
import { FollowUserUseCase } from "./use-cases/follow-user.use-case.js";
import { GetFolloweeIdsUseCase } from "./use-cases/get-followee-ids.use-case.js";

/** Public facade of the `social` module (ADR-021 §1: layer 1, may depend on `users`). */
@Injectable()
export class SocialService {
  constructor(
    private readonly followUserUseCase: FollowUserUseCase,
    private readonly getFolloweeIdsUseCase: GetFolloweeIdsUseCase,
  ) {}

  follow(followerId: string, followeeId: string): Promise<void> {
    return this.followUserUseCase.execute(followerId, followeeId);
  }

  /** Batch read (ADR-021 §2 rule 6, §6): the feed's first step. */
  getFolloweeIds(userId: string): Promise<string[]> {
    return this.getFolloweeIdsUseCase.execute(userId);
  }
}
