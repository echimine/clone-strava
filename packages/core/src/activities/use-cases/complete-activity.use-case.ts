import { ConflictException, Injectable } from "@nestjs/common";
import { InjectQueue } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import {
  ACTIVITIES_QUEUE_NAME,
  ACTIVITY_TRACE_MAX_BYTES,
  PROCESS_ACTIVITY_JOB_NAME,
  activityTraceKey,
  processActivityJobId,
  type ProcessActivityJob,
} from "@repo/contracts";
import { enqueueUnique } from "../../infrastructure/index.js";
import { StorageService } from "../../storage/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { toActivityRecord, type ActivityRecord } from "../domain/activity-record.js";

/**
 * `POST /v1/activities/:id/complete` (ADR-019 §4): `HEAD` the trace in the
 * bucket, move `pending` -> `processing`, enqueue `process-activity` with
 * its deterministic job id (ADR-011 §2) right after the commit (ADR-021 §3
 * "job rules"). Replays on an already-`processing`/`processed` activity
 * are a no-op; `failed` is a conflict. A lost enqueue is caught by the
 * reconciliation sweep (ADR-019 §7).
 */
@Injectable()
export class CompleteActivityUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    private readonly storage: StorageService,
    @InjectQueue(ACTIVITIES_QUEUE_NAME) private readonly queue: Queue<ProcessActivityJob>,
  ) {}

  async execute(userId: string, activityId: string, requestId?: string): Promise<ActivityRecord> {
    const row = await this.activities.findOwnOrThrow(userId, activityId);
    if (row.processingStatus === "failed") {
      // Reprocessing is triggered from the backoffice (ADR-019 §4, §6).
      throw new ConflictException({ code: "activity_failed", message: "This activity has failed" });
    }
    if (row.processingStatus !== "pending") {
      // Replayed call: already processing or processed, nothing to enqueue.
      return toActivityRecord(row);
    }

    const head = await this.storage.head(activityTraceKey(row.userId, row.id));
    if (!head) {
      throw new ConflictException({ code: "trace_missing", message: "The trace has not been uploaded" });
    }
    if (head.sizeBytes > ACTIVITY_TRACE_MAX_BYTES) {
      throw new ConflictException({ code: "trace_too_large", message: "The trace is too large" });
    }

    if (await this.activities.markProcessingIfPending(row.id)) {
      await enqueueUnique(
        this.queue,
        PROCESS_ACTIVITY_JOB_NAME,
        { activityId: row.id, userId, requestId },
        processActivityJobId(row.id),
      );
    }
    const updated = await this.activities.findById(row.id);
    return toActivityRecord(updated ?? row);
  }
}
