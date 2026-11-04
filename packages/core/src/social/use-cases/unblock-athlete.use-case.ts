import { Injectable } from "@nestjs/common";
import { AthleteBlockRepository } from "../repositories/athlete-block.repository.js";

/**
 * `DELETE /v1/me/blocks/:athleteId` (ADR-038 §8): lifts the viewer's own Block, idempotent.
 * Comments and kudos come back at read time; follows deleted by the Block do not. A Block the
 * other athlete made stays.
 */
@Injectable()
export class UnblockAthleteUseCase {
  constructor(private readonly blocks: AthleteBlockRepository) {}

  execute(blockerId: string, blockedId: string): Promise<void> {
    return this.blocks.delete(blockerId, blockedId);
  }
}
