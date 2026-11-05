import { Inject, Injectable, NotFoundException } from "@nestjs/common";
import type { Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import { BestEffortRepository } from "../repositories/best-effort.repository.js";
import { BestEffortWriter } from "../services/best-effort-writer.js";

/**
 * `DELETE /v1/activities/:id/best-efforts/:distanceM` (ADR-039 §3): the author removes a Best
 * effort of their Activity for good, then their Medals on that distance are replayed, in one
 * transaction. Removing it again changes nothing. `404 best_effort_not_found` for another
 * athlete or a distance the Activity has no Best effort on.
 */
@Injectable()
export class RemoveBestEffortUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly bestEfforts: BestEffortRepository,
    private readonly writer: BestEffortWriter,
  ) {}

  async execute(userId: string, activityId: string, distanceM: number): Promise<void> {
    const removed = await this.db.transaction(async (tx) => {
      await this.bestEfforts.lockAthlete(userId, tx);
      const recordSet = await this.bestEfforts.markRemoved(userId, activityId, distanceM, tx);
      if (recordSet) {
        await this.writer.replay(userId, [{ recordSet, distanceM }], tx);
      }
      return recordSet !== undefined;
    });
    if (!removed) {
      throw new NotFoundException({ code: "best_effort_not_found", message: "Best effort not found" });
    }
  }
}
