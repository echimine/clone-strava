import { Injectable } from "@nestjs/common";
import { InjectQueue } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import {
  ACTIVITIES_QUEUE_NAME,
  PROCESS_ACTIVITY_JOB_NAME,
  REPROCESS_ACTIVITY_JOB_NAME,
  processActivityJobId,
  reprocessActivityJobId,
  type ProcessActivityJob,
  type ReprocessActivityJob,
} from "@repo/contracts";
import { DEFAULT_JOB_RETRY, enqueueUnique } from "../../infrastructure/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { ActivityImportRepository } from "../repositories/activity-import.repository.js";
import { ImportJobEnqueuer } from "../services/import-job-enqueuer.js";

/** ADR-019 §7, ADR-028 §8: older than this in `processing` counts as stuck. */
const STUCK_AFTER_MINUTES = 15;

/**
 * Reconciliation (ADR-019 §7, ADR-028 §8): re-enqueues activities and
 * imports stuck `processing` for more than 15 minutes without a live job,
 * and `reprocess-activity` for processed activities whose official values
 * lag behind a sport change (ADR-033 §5), every 10 minutes. `apps/worker` schedules this use case (no scheduler
 * dependency in `packages/core`, ADR-021 §6).
 */
@Injectable()
export class ReconcileStuckActivitiesUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    private readonly imports: ActivityImportRepository,
    private readonly importEnqueuer: ImportJobEnqueuer,
    @InjectQueue(ACTIVITIES_QUEUE_NAME)
    private readonly queue: Queue<ProcessActivityJob | ReprocessActivityJob>,
  ) {}

  /** Returns the number of jobs re-enqueued. */
  async execute(): Promise<number> {
    let count = 0;
    for (const activity of await this.activities.findStuckProcessing(STUCK_AFTER_MINUTES)) {
      const added = await enqueueUnique(
        this.queue,
        PROCESS_ACTIVITY_JOB_NAME,
        { activityId: activity.id, userId: activity.userId },
        processActivityJobId(activity.id),
      );
      if (added) count++;
    }
    for (const stuckImport of await this.imports.findStuckProcessing(STUCK_AFTER_MINUTES)) {
      if (await this.importEnqueuer.enqueue({ importId: stuckImport.id, userId: stuckImport.userId })) {
        count++;
      }
    }
    for (const activity of await this.activities.findWithValuesForAnotherSport()) {
      if (await this.enqueueReprocessingOnce(activity)) count++;
    }
    return count;
  }

  /**
   * The job id of the activity's last edit, so it matches the one the `PATCH` enqueued. Added
   * only if no job holds that id: a reprocessing that failed for good keeps the old values
   * (ADR-033 §5) instead of being retried by every sweep, until BullMQ drops the failed job.
   */
  private async enqueueReprocessingOnce(activity: {
    id: string;
    userId: string;
    updatedAt: Date;
  }): Promise<boolean> {
    const jobId = reprocessActivityJobId(activity.id, activity.updatedAt);
    if (await this.queue.getJob(jobId)) {
      return false;
    }
    await (this.queue as Queue).add(
      REPROCESS_ACTIVITY_JOB_NAME,
      { activityId: activity.id, userId: activity.userId },
      { ...DEFAULT_JOB_RETRY, jobId },
    );
    return true;
  }
}
