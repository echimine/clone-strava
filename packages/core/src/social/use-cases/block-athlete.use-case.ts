import { Inject, Injectable } from "@nestjs/common";
import type { Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import { AthleteBlockRepository } from "../repositories/athlete-block.repository.js";
import { FollowRepository } from "../repositories/follow.repository.js";
import { cannotBlockSelf } from "../services/follow-errors.js";

/**
 * `PUT /v1/me/blocks/:athleteId` (ADR-038 §8): records the Block and deletes the follows and
 * follow requests between the two athletes, both directions, in the same transaction; nothing
 * comes back on unblock. Idempotent. The caller has checked that the athlete exists.
 */
@Injectable()
export class BlockAthleteUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly blocks: AthleteBlockRepository,
    private readonly follows: FollowRepository,
  ) {}

  async execute(blockerId: string, blockedId: string): Promise<void> {
    if (blockerId === blockedId) {
      throw cannotBlockSelf();
    }
    await this.db.transaction(async (tx) => {
      await this.blocks.insertIfAbsent(blockerId, blockedId, tx);
      await this.follows.deleteBetween(blockerId, blockedId, tx);
    });
  }
}
