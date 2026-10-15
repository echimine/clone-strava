import { ConflictException, Injectable, Logger, NotFoundException } from "@nestjs/common";
import { activityTraceKey } from "@repo/contracts";
import { StorageService } from "../../storage/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";

/**
 * `DELETE /v1/activities/:id` (ADR-031 §13, §14): the author deletes an activity the app has
 * not finished sending (`pending`) or that failed, for good (ADR-017), with its trace. Any
 * other state is a conflict; anyone else gets `404`.
 */
@Injectable()
export class DeleteActivityUseCase {
  private readonly logger = new Logger(DeleteActivityUseCase.name);

  constructor(
    private readonly activities: ActivityRepository,
    private readonly storage: StorageService,
  ) {}

  async execute(userId: string, activityId: string): Promise<void> {
    const row = await this.activities.findById(activityId);
    if (!row || row.userId !== userId) {
      throw new NotFoundException({ code: "not_found", message: "Activity not found" });
    }
    if (!(await this.activities.deleteIfPendingOrFailed(row.id))) {
      throw new ConflictException({
        code: "not_deletable",
        message: "Only a pending or failed activity can be deleted",
      });
    }
    // The row is gone: a trace left behind is unreachable, so a failure here is only logged.
    await this.storage.deleteObject(activityTraceKey(row.userId, row.id)).catch((error: unknown) => {
      this.logger.warn(`Trace of deleted activity ${row.id} not removed: ${String(error)}`);
    });
  }
}
