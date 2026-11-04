import { ConflictException, Injectable } from "@nestjs/common";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { AdminFailureRepository } from "../repositories/admin-failure.repository.js";
import { activityNotFound } from "../services/activity-not-found.js";
import { ReprocessJobEnqueuer } from "../services/reprocess-job-enqueuer.js";

/**
 * « Recalculer » (`POST /v1/admin/activities/:id/recompute`, ADR-038 §14): a processed Activity
 * whose official values were computed for another sport gets `reprocess-activity` again, under a
 * new job id. `409 not_stale` when its values match its sport; the Activity stays `processed`
 * either way (ADR-033 §5).
 */
@Injectable()
export class RecomputeActivityUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    private readonly failures: AdminFailureRepository,
    private readonly enqueuer: ReprocessJobEnqueuer,
  ) {}

  /** Returns the author and the new job id. */
  async execute(activityId: string, requestId?: string): Promise<{ userId: string; jobId: string }> {
    const stale = await this.failures.findStaleActivity(activityId);
    if (!stale) {
      if (!(await this.activities.findById(activityId))) {
        throw activityNotFound();
      }
      throw new ConflictException({
        code: "not_stale",
        message: "Only processed activities computed for another sport can be recomputed",
      });
    }
    const jobId = await this.enqueuer.enqueueRecompute(
      { activityId: stale.id, userId: stale.userId, requestId },
      new Date(),
    );
    return { userId: stale.userId, jobId };
  }
}
