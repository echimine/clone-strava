import { Injectable } from "@nestjs/common";
import type { FollowState } from "../domain/follow-state.js";
import { FollowSettingsRepository } from "../repositories/follow-settings.repository.js";
import { FollowRepository } from "../repositories/follow.repository.js";
import { cannotFollowSelf } from "../services/follow-errors.js";
import { FollowStateReader } from "../services/follow-state-reader.js";

/**
 * `PUT /v1/athletes/:id/follow` (ADR-036 §1): `accepted` at once, or a
 * `pending` request when the athlete approves their followers. Idempotent:
 * an existing row is left as is. The caller has checked that the athlete
 * exists (`apps/api`: `public.user` belongs to `auth`).
 */
@Injectable()
export class FollowAthleteUseCase {
  constructor(
    private readonly follows: FollowRepository,
    private readonly settings: FollowSettingsRepository,
    private readonly state: FollowStateReader,
  ) {}

  async execute(followerId: string, followeeId: string): Promise<FollowState> {
    if (followerId === followeeId) {
      throw cannotFollowSelf();
    }
    const approves = await this.settings.approvesFollowers(followeeId);
    await this.follows.insertIfAbsent(followerId, followeeId, approves ? "pending" : "accepted");
    return this.state.read(followerId, followeeId);
  }
}
