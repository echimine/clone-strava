import { Injectable } from "@nestjs/common";
import type { FollowState } from "../domain/follow-state.js";
import { FollowSettingsRepository } from "../repositories/follow-settings.repository.js";
import { FollowRepository } from "../repositories/follow.repository.js";
import { AthleteBlockRepository } from "../repositories/athlete-block.repository.js";
import { blockedAthleteNotFound, cannotFollowSelf } from "../services/follow-errors.js";
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
    private readonly blocks: AthleteBlockRepository,
  ) {}

  async execute(followerId: string, followeeId: string): Promise<FollowState> {
    if (followerId === followeeId) {
      throw cannotFollowSelf();
    }
    // ADR-038 §8: no new Follow while a Block lasts, whoever blocked whom.
    if (await this.blocks.existsBetween(followerId, followeeId)) {
      throw blockedAthleteNotFound();
    }
    const approves = await this.settings.approvesFollowers(followeeId);
    await this.follows.insertIfAbsent(followerId, followeeId, approves ? "pending" : "accepted");
    return this.state.read(followerId, followeeId);
  }
}
