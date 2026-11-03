import { Injectable } from "@nestjs/common";
import { FollowRepository } from "../repositories/follow.repository.js";

/** `DELETE /v1/me/follow-requests/:followerId` (ADR-036 §1): deletes the pending request. Idempotent. */
@Injectable()
export class RefuseFollowRequestUseCase {
  constructor(private readonly follows: FollowRepository) {}

  async execute(userId: string, followerId: string): Promise<void> {
    await this.follows.delete(followerId, userId, "pending");
  }
}
