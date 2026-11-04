import { ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import { ActivityRemover } from "../services/activity-remover.js";
import { GetVisibleActivityUseCase } from "./get-visible-activity.use-case.js";

/**
 * `DELETE /v1/activities/:id` (ADR-031 §13, ADR-033 §6): the author deletes their activity
 * for good (ADR-017) unless the worker is processing it ({@link ActivityRemover}). Not visible:
 * `404`; visible but someone else's: `403`.
 */
@Injectable()
export class DeleteActivityUseCase {
  constructor(
    private readonly getVisibleActivity: GetVisibleActivityUseCase,
    private readonly remover: ActivityRemover,
  ) {}

  async execute(userId: string, activityId: string): Promise<void> {
    const activity = await this.getVisibleActivity.execute(userId, activityId);
    if (!activity) {
      // Same code as before ADR-033: the app treats it as already deleted (ADR-031 §14).
      throw new NotFoundException({ code: "not_found", message: "Activity not found" });
    }
    if (activity.userId !== userId) {
      throw new ForbiddenException({
        code: "not_activity_author",
        message: "Only the author can delete this activity",
      });
    }
    await this.remover.remove(activity, { bySanction: false });
  }
}
