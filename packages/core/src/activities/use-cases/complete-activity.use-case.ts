import { Injectable, NotImplementedException } from "@nestjs/common";
import { InjectQueue } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import {
  ACTIVITIES_QUEUE_NAME,
  PROCESS_ACTIVITY_JOB_NAME,
  processActivityJobId,
  type ProcessActivityJob,
} from "@repo/contracts";
import { ActivityRepository } from "../repositories/activity.repository.js";
import type { ActivityRecord } from "../domain/activity-record.js";

/**
 * `POST /v1/activities/:id/complete` (ADR-019 §4): checks the trace exists
 * in the bucket (via the `storage` platform module, injected by the
 * caller), moves `pending` -> `processing`, enqueues `process-activity`
 * with a deterministic job id (ADR-011 §2) right after the commit
 * (ADR-021 §3 "job rules"). Replays on an already-`processing`/`processed`
 * activity are a no-op; `failed` is a conflict (ADR-019 §4).
 */
@Injectable()
export class CompleteActivityUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    @InjectQueue(ACTIVITIES_QUEUE_NAME) private readonly queue: Queue<ProcessActivityJob>,
  ) {}

  async execute(_userId: string, _activityId: string, _requestId?: string): Promise<ActivityRecord> {
    throw new NotImplementedException();
  }

  /** Called once the activity has moved to `processing` and the commit succeeded. */
  private async enqueueProcessing(job: ProcessActivityJob): Promise<void> {
    await this.queue.add(PROCESS_ACTIVITY_JOB_NAME, job, {
      jobId: processActivityJobId(job.activityId),
      attempts: 5,
      backoff: { type: "exponential", delay: 30_000 },
    });
  }
}
