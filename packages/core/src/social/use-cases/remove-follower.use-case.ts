import { Injectable } from "@nestjs/common";
import { FollowRepository } from "../repositories/follow.repository.js";

/** `DELETE /v1/me/followers/:followerId` (ADR-036 §1): removes an accepted follower. Idempotent. */
@Injectable()
export class RemoveFollowerUseCase {
  constructor(private readonly follows: FollowRepository) {}

  async execute(userId: string, followerId: string): Promise<void> {
    await this.follows.delete(followerId, userId, "accepted");
  }
}
