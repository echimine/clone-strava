import { Injectable, NotImplementedException } from "@nestjs/common";
import { FollowRepository } from "../repositories/follow.repository.js";

/** `follow` / accept / unfollow (ADR-017): one use case per action, this one for `follow`. */
@Injectable()
export class FollowUserUseCase {
  constructor(private readonly follows: FollowRepository) {}

  async execute(_followerId: string, _followeeId: string): Promise<void> {
    throw new NotImplementedException();
  }
}
