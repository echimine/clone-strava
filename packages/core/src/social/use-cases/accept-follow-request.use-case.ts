import { Injectable } from "@nestjs/common";
import { FollowRepository } from "../repositories/follow.repository.js";
import { followRequestNotFound } from "../services/follow-errors.js";

/**
 * `PUT /v1/me/follow-requests/:followerId` (ADR-036 §1): `pending` →
 * `accepted`; `404 follow_request_not_found` without a pending request.
 */
@Injectable()
export class AcceptFollowRequestUseCase {
  constructor(private readonly follows: FollowRepository) {}

  async execute(userId: string, followerId: string): Promise<void> {
    if (!(await this.follows.accept(followerId, userId))) {
      throw followRequestNotFound();
    }
  }
}
