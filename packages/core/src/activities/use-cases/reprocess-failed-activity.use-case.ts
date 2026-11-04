import { ConflictException, Injectable } from "@nestjs/common";
import { InjectQueue } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import {
  ACTIVITIES_QUEUE_NAME,
  PROCESS_ACTIVITY_JOB_NAME,
  processActivityJobId,
  type ProcessActivityJob,
} from "@repo/contracts";
import { enqueueUnique } from "../../infrastructure/index.js";
import { toActivityRecord, type ActivityRecord } from "../domain/activity-record.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { AdminActivityRepository } from "../repositories/admin-activity.repository.js";
import { activityNotFound } from "../services/activity-not-found.js";

/**
 * « Retraiter » (`POST /v1/admin/activities/:id/reprocess`, ADR-019 §6, ADR-038 §11): a `failed`
 * Activity goes back to `processing` with its error cleared, then `process-activity` is enqueued
 * again under its deterministic id (a finished job of that id is replaced). `409 not_failed` in
 * any other state; a processed Activity is never recomputed from here (ADR-038 §14).
 */
@Injectable()
export class ReprocessFailedActivityUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    private readonly adminActivities: AdminActivityRepository,
    @InjectQueue(ACTIVITIES_QUEUE_NAME) private readonly queue: Queue<ProcessActivityJob>,
  ) {}

  async execute(activityId: string, requestId?: string): Promise<ActivityRecord> {
    const row = await this.activities.findById(activityId);
    if (!row) {
      throw activityNotFound();
    }
    if (!(await this.adminActivities.resetFailedToProcessing(row.id))) {
      throw new ConflictException({ code: "not_failed", message: "Only failed activities can be reprocessed" });
    }
    // Right after the commit (ADR-021 §3); a lost enqueue is caught by the reconciliation (ADR-019 §7).
    await enqueueUnique(
      this.queue,
      PROCESS_ACTIVITY_JOB_NAME,
      { activityId: row.id, userId: row.userId, requestId },
      processActivityJobId(row.id),
    );
    return toActivityRecord((await this.activities.findById(row.id)) ?? row);
  }
}
