import { Injectable } from "@nestjs/common";
import { InjectQueue } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import {
  ACTIVITIES_QUEUE_NAME,
  PROCESS_ACTIVITY_JOB_NAME,
  processActivityJobId,
  type ProcessActivityJob,
} from "@repo/contracts";
import { enqueueUnique } from "../../infrastructure/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { ActivityImportRepository } from "../repositories/activity-import.repository.js";
import { ImportJobEnqueuer } from "../services/import-job-enqueuer.js";
import { ReprocessJobEnqueuer } from "../services/reprocess-job-enqueuer.js";

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
    private readonly reprocessEnqueuer: ReprocessJobEnqueuer,
    @InjectQueue(ACTIVITIES_QUEUE_NAME) private readonly queue: Queue<ProcessActivityJob>,
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
    // The job id of the activity's last edit, so it matches the one the `PATCH` enqueued.
    for (const activity of await this.activities.findWithValuesForAnotherSport()) {
      if (await this.reprocessEnqueuer.enqueue({ activityId: activity.id, userId: activity.userId }, activity.updatedAt)) {
        count++;
      }
    }
    return count;
  }
}
