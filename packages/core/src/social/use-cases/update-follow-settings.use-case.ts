import { Inject, Injectable } from "@nestjs/common";
import type { Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import { FollowSettingsRepository } from "../repositories/follow-settings.repository.js";
import { FollowRepository } from "../repositories/follow.repository.js";

/**
 * `PUT /v1/me/follow-settings` (ADR-036 §1): "Approuver mes abonnés".
 * Turning it on affects only new follows; turning it off accepts every
 * pending request in the same transaction.
 */
@Injectable()
export class UpdateFollowSettingsUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly settings: FollowSettingsRepository,
    private readonly follows: FollowRepository,
  ) {}

  async execute(userId: string, approveFollowers: boolean): Promise<{ approveFollowers: boolean }> {
    await this.db.transaction(async (tx) => {
      await this.settings.upsert(userId, approveFollowers, tx);
      if (!approveFollowers) {
        await this.follows.acceptAllPending(userId, tx);
      }
    });
    return { approveFollowers };
  }
}
